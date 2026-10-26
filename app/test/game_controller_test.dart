// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stadtbau/game/game_controller.dart';
import 'package:stadtbau/game/overlay_math.dart';
import 'package:stadtbau/game/save_store.dart';
import 'package:stadtbau_sim/stadtbau_sim.dart';

// The controller on its own, without a widget tree: placement, history,
// previews, experiments, cursor and guidance. Widget tests cover how the UI
// reads it; these pin the rules it enforces.

void main() {
  // Placement plays haptics and a click through platform channels.
  TestWidgetsFlutterBinding.ensureInitialized();

  late GameController c;

  setUp(() => c = GameController(size: 8));
  tearDown(() => c.dispose());

  group('placement and history', () {
    test('a placement can be undone and redone', () {
      expect(c.canUndo, isFalse);
      expect(c.place(2, 3, TileType.park), isTrue);
      expect(c.sim.state.tileAt(2, 3), TileType.park);
      expect(c.selectedCell, c.sim.state.index(2, 3));
      expect(c.lastImpact?.tile, TileType.park);
      expect(c.lastImpact?.affectedCells, contains(c.sim.state.index(2, 3)));

      c.undo();
      expect(c.sim.state.tileAt(2, 3), TileType.meadow);
      expect(c.canRedo, isTrue);
      expect(c.lastImpact, isNull);

      c.redo();
      expect(c.sim.state.tileAt(2, 3), TileType.park);
    });

    test('a fresh placement drops the redo stack', () {
      c.place(0, 0, TileType.park);
      c.undo();
      c.place(1, 1, TileType.forest);
      expect(c.canRedo, isFalse);
    });

    test('placing the tile already there fails and records why', () {
      expect(c.place(0, 0, TileType.meadow), isFalse);
      expect(c.lastError, CommandError.sameTile);
      expect(c.canUndo, isFalse);
    });

    test('clearing a cell is undoable and reports the removed tile', () {
      c.place(4, 4, TileType.road);
      expect(c.clear(4, 4), isTrue);
      expect(c.lastImpact?.removed, isTrue);
      expect(c.lastImpact?.tile, TileType.road);
      c.undo();
      expect(c.sim.state.tileAt(4, 4), TileType.road);
    });

    test('advancing time clears history so undo cannot rewind months', () {
      c.place(0, 0, TileType.park);
      final tick = c.sim.state.tick;
      c.step();
      expect(c.sim.state.tick, tick + 1);
      expect(c.canUndo, isFalse);
      expect(c.canRedo, isFalse);
    });

    test('every model change bumps the visual revision', () {
      final r0 = c.visualRevision;
      c.place(0, 0, TileType.park);
      final r1 = c.visualRevision;
      expect(r1, greaterThan(r0));
      c.setHover(5);
      c.select(5);
      expect(c.visualRevision, r1);
    });

    test('the indicator timeline is bounded', () {
      for (var i = 0; i < 100; i++) {
        c.step();
      }
      expect(c.indicatorHistory.length, 48);
      expect(c.indicatorHistory.last.tick, c.sim.state.tick);
    });
  });

  group('placement preview', () {
    test('there is none without a brush or a target cell', () {
      expect(c.placementPreview, isNull);
      c.setBrush(TileType.park);
      expect(c.placementPreview, isNull);
      c.setHover(9);
      expect(c.placementPreview?.cell, 9);
      expect(c.placementPreview?.isValid, isTrue);
    });

    test('flags a tile the player cannot afford', () {
      c.sim = Simulation(
        state: WorldState.empty(width: 8, height: 8, budgetKEur: 0, seed: 1),
      );
      c.setBrush(TileType.housingHigh);
      c.setHover(0);
      expect(c.placementPreview?.error, CommandError.insufficientBudget);
    });

    test('flags the tile already on the cell', () {
      c.setBrush(TileType.meadow);
      c.setHover(0);
      expect(c.placementPreview?.error, CommandError.sameTile);
    });

    test('never mutates the authoritative simulation', () {
      c.setExperience(c.experience.copyWith(placementForecasts: true));
      c.setBrush(TileType.industry);
      c.setHover(10);
      c.placementPreview;
      expect(c.sim.state.tiles[10], TileType.meadow);
    });
  });

  group('brush and cursor', () {
    test('choosing the active brush again puts it down', () {
      c.setBrush(TileType.park);
      expect(c.brush, TileType.park);
      c.setBrush(TileType.park);
      expect(c.brush, isNull);
    });

    test('digit selection ignores indices without a tile', () {
      c.selectBrushByIndex(0);
      expect(c.brush, c.allowedTypes.first);
      c.selectBrushByIndex(99);
      expect(c.brush, c.allowedTypes.first);
    });

    test('the first move only shows the cursor, later moves clamp', () {
      c.moveCursor(1, 0);
      expect(c.cursorCell, c.sim.state.index(4, 4));
      for (var i = 0; i < 10; i++) {
        c.moveCursor(-1, -1);
      }
      expect(c.cursorCell, 0);
      expect(c.selectedCell, 0);
    });

    test('activating the cursor places the brush', () {
      c.setCursor(3);
      expect(c.activateCursor(), isFalse); // no brush: selects
      c.setBrush(TileType.park);
      expect(c.activateCursor(), isTrue);
      expect(c.sim.state.tiles[3], TileType.park);
      expect(c.clearCursor(), isTrue);
      expect(c.sim.state.tiles[3], TileType.meadow);
    });
  });

  group('experiments', () {
    test('discarding restores the world from before', () {
      c.place(0, 0, TileType.park);
      c.startExperiment();
      expect(c.experimentActive, isTrue);
      expect(c.canUndo, isFalse);
      c.place(1, 1, TileType.industry);
      expect(c.experimentDeltas, isNotEmpty);
      c.discardExperiment();
      expect(c.experimentActive, isFalse);
      expect(c.sim.state.tileAt(1, 1), TileType.meadow);
      expect(c.sim.state.tileAt(0, 0), TileType.park);
    });

    test('keeping leaves the changes in place', () {
      c.startExperiment();
      c.place(1, 1, TileType.industry);
      c.keepExperiment();
      expect(c.experimentActive, isFalse);
      expect(c.sim.state.tileAt(1, 1), TileType.industry);
    });

    test('starting an experiment pauses the clock', () {
      c.setSpeed(3);
      c.startExperiment();
      expect(c.speed, 0);
    });
  });

  group('levels', () {
    test('a level with teaching content opens with its briefing', () {
      final level = Level.builtIn().firstWhere((l) => l.learning != null);
      c.startLevel(level);
      expect(c.level, level);
      expect(c.progress, isNotNull);
      expect(c.missionBriefingPending, isTrue);
      expect(c.activeBeat, isNull); // nothing is offered over the briefing
      c.acknowledgeMissionBriefing();
      expect(c.missionBriefingPending, isFalse);
    });

    test('the goal hint walks overlay, then brush', () {
      // The first level whose opening position leaves a goal unmet and
      // offers a tile toward it.
      GoalGuidance? guidance;
      for (final level in Level.builtIn()) {
        c.startLevel(level);
        guidance = c.goalGuidance;
        if (guidance?.tile != null) break;
      }
      expect(guidance?.tile, isNotNull);
      guidance!;
      c.advanceGuidance(guidance);
      expect(c.guidanceStage, 1);
      expect(c.overlay, guidanceOverlay(guidance));
      c.advanceGuidance(guidance);
      c.advanceGuidance(guidance);
      expect(c.guidanceStage, 3);
      c.advanceGuidance(guidance);
      expect(c.brush, guidance.tile);
    });

    test('starting the sandbox forgets the level', () {
      c.startLevel(Level.builtIn().first);
      c.startSandbox(6, 6);
      expect(c.level, isNull);
      expect(c.progress, isNull);
      expect(c.width, 6);
    });
  });

  group('persistence', () {
    test('a sandbox survives a restart through the save store', () async {
      SharedPreferences.setMockInitialValues({});
      final store = SaveStore();
      final first = GameController(size: 8, store: store);
      first.place(2, 2, TileType.forest);
      await store.save(null, first.sim);
      first.dispose();

      final second = GameController(size: 8, store: store);
      addTearDown(second.dispose);
      expect(await second.restore(), isTrue);
      expect(second.sim.state.tileAt(2, 2), TileType.forest);
      expect(second.level, isNull);
    });

    test('nothing to restore leaves the controller alone', () async {
      SharedPreferences.setMockInitialValues({});
      final fresh = GameController(size: 8, store: SaveStore());
      addTearDown(fresh.dispose);
      expect(await fresh.restore(), isFalse);
    });
  });

  group('overlay math', () {
    test('identical simulations have no deltas and affect only the cell', () {
      final a = Simulation.sandbox(width: 8, height: 8);
      final b = a.copy();
      expect(indicatorDeltas(a, b).values, everyElement(0));
      expect(affectedCells(MapOverlay.noise, a, b, 5), {5});
    });

    test('a road raises noise around it', () {
      final a = Simulation.sandbox(width: 8, height: 8);
      final b = a.copy()..apply(const PlaceTile(4, 4, TileType.road));
      final cells = affectedCells(
        previewOverlayFor(TileType.road),
        a,
        b,
        b.state.index(4, 4),
      );
      expect(cells.length, greaterThan(1));
    });

    test('normalised overlay values stay in 0..1', () {
      final sim = Simulation.sandbox(width: 8, height: 8)
        ..apply(const PlaceTile(1, 1, TileType.industry))
        ..apply(const PlaceTile(2, 1, TileType.road));
      for (final overlay in MapOverlay.values) {
        for (var i = 0; i < sim.state.cellCount; i++) {
          expect(
            normalOverlayValue(overlay, sim, i),
            inInclusiveRange(0, 1),
            reason: '$overlay at $i',
          );
        }
      }
    });

    test('only noise, heat and traffic read high as bad', () {
      expect(MapOverlay.values.where(overlayHighIsBadFor).toSet(), {
        MapOverlay.noise,
        MapOverlay.heat,
        MapOverlay.traffic,
      });
    });
  });
}
