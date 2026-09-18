// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart' hide Simulation;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stadtbau/game/experience_settings.dart';
import 'package:stadtbau/game/game_controller.dart';
import 'package:stadtbau/game/save_store.dart';
import 'package:stadtbau/l10n/generated/app_localizations.dart';
import 'package:stadtbau/main.dart';
import 'package:stadtbau/ui/map_view.dart';
import 'package:stadtbau_sim/stadtbau_sim.dart';

void main() {
  testWidgets(
    'level select opens the sandbox with palette, map and indicators',
    (tester) async {
      // Skip the first-launch onboarding overlay (T-208).
      SharedPreferences.setMockInitialValues({'stadtbau.onboarding.v1': true});
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(const HectopolisApp());
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.grid_on), findsOneWidget);
      await tester.tap(find.byIcon(Icons.grid_on));
      // The game map has intentional continuous ambient animation, so it never
      // reaches pumpAndSettle's definition of idle.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.byIcon(Icons.forest), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    },
  );

  testWidgets('the ambient animation repaints only the moving map layer', (
    tester,
  ) async {
    // Skip the first-launch onboarding overlay (T-208).
    SharedPreferences.setMockInitialValues({'stadtbau.onboarding.v1': true});
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(const HectopolisApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.grid_on));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // Ten frames of nothing but the ambient animation: the moving layer
    // redraws, the still layer underneath must not (task T-202).
    MapPaintCounters.reset();
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(MapPaintCounters.moving, greaterThan(0));
    expect(MapPaintCounters.still, 0);
  });

  testWidgets('a level shows its goals', (tester) async {
    // Skip the first-launch onboarding overlay (T-208).
    SharedPreferences.setMockInitialValues({'stadtbau.onboarding.v1': true});
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(const HectopolisApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.star_border).first);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byIcon(Icons.radio_button_unchecked), findsWidgets);
  });

  test('mission beats arrive in order and stay dismissed', () async {
    SharedPreferences.setMockInitialValues({});
    final level = Level.byId('village')!;
    final beats = level.learning!.beats;
    final c = GameController(size: level.width);
    c.startLevel(level);
    // The briefing owns the start of the mission; beats wait for it.
    expect(c.activeBeat, isNull);
    c.acknowledgeMissionBriefing();

    // Both village beats are keyed to tiles placed, so the test follows the
    // data rather than a number that has to be kept in step with it.
    final firstAt = beats.first.afterTilesPlaced!;
    final secondAt = beats[1].afterTilesPlaced!;

    var placed = 0;
    var cell = 0;
    void buildTo(int target) {
      for (; placed < target && cell < level.map.length; cell++) {
        if (c.place(cell % level.width, cell ~/ level.width, TileType.housingLow)) {
          placed++;
        }
      }
    }

    buildTo(firstAt);
    expect(placed, firstAt, reason: 'needs $firstAt homes for the first beat');
    expect(c.activeBeat?.id, beats.first.id);

    // Only one beat is offered at a time, even once a later one would qualify.
    buildTo(secondAt);
    expect(placed, secondAt, reason: 'needs $secondAt homes for the second');
    for (var i = 0; i < 30; i++) {
      c.step();
    }
    expect(c.activeBeat?.id, beats.first.id);

    c.dismissBeat(beats.first.id);
    expect(c.activeBeat?.id, beats[1].id);
    c.dismissBeat(beats[1].id);
    expect(c.activeBeat, isNull);
  });

  testWidgets('the causal loop view names the loop that is loudest', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'stadtbau.onboarding.v1': true});
    // Wide enough for the two-column layout but not for the roomy app bar,
    // which spreads the overflow menu out into individual buttons.
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(const HectopolisApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.grid_on));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.byIcon(Icons.more_vert));
    // The map animates for ever, so pumpAndSettle never returns here.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.tap(find.text(l10n.causalViewTitle).last);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text(l10n.causalViewTitle), findsWidgets);
    // Loops are listed strongest first. The sandbox is young meadow with
    // nobody in it, so the only loop doing anything is the one waiting for
    // that meadow to grow up, and it should lead.
    expect(
      find.text(l10n.causalLoopName(CausalLoop.regrowth.name)),
      findsOneWidget,
    );
    expect(find.text(l10n.causalDominant), findsOneWidget);
    // That the list holds every loop is the simulation's business, and
    // packages/stadtbau_sim/test/loops_test.dart checks it; the sheet builds
    // its cards lazily, so off-screen ones are not in the tree to find.
  });

  test('autosave round trip restores the world', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SaveStore();
    final c = GameController(size: 8, store: store);
    c.startLevel(Level.byId('village')!);
    c.place(0, 0, TileType.housingLow);
    c.step();
    await store.save('village', c.sim);
    final restored = GameController(size: 8, store: store);
    expect(await restored.restore(), isTrue);
    expect(restored.level?.id, 'village');
    expect(restored.sim.state.tileAt(0, 0), TileType.housingLow);
    expect(restored.sim.state.tick, 1);
    expect(restored.sim.tileBudget.remaining(TileType.housingLow), 15);
    expect(restored.progress, isNotNull);
    c.dispose();
    restored.dispose();
  });

  test('controller places tiles with the brush and advances time', () {
    final c = GameController(size: 8);
    c.setBrush(TileType.road);
    expect(c.place(1, 1, TileType.road), isTrue);
    expect(c.sim.state.tileAt(1, 1), TileType.road);
    c.step();
    expect(c.sim.state.tick, 1);
    c.dispose();
  });

  test(
    'experience settings persist independently of the saved world',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = SaveStore();
      const settings = ExperienceSettings(
        simpleMode: true,
        learningMode: LearningMode.starter,
        cleanVisuals: true,
        ambientAnimations: false,
        trafficAnimations: false,
        placementForecasts: false,
        causalHighlights: false,
        haptics: false,
      );
      await store.saveExperienceSettings(settings);

      final c = GameController(size: 8, store: store);
      await c.loadExperienceSettings();
      expect(c.simpleMode, isTrue);
      expect(c.learningMode, LearningMode.starter);
      expect(c.experience.cleanVisuals, isTrue);
      expect(c.experience.ambientAnimations, isFalse);
      expect(c.experience.trafficAnimations, isFalse);
      expect(c.experience.placementForecasts, isFalse);
      c.dispose();
    },
  );

  test('learning profiles progressively reveal complexity', () {
    final c = GameController(size: 8);
    c.setLearningMode(LearningMode.starter);
    expect(c.simpleMode, isTrue);
    expect(c.experience.placementForecasts, isFalse);
    expect(c.experience.causalHighlights, isFalse);

    c.setLearningMode(LearningMode.explorer);
    expect(c.simpleMode, isFalse);
    expect(c.experience.placementForecasts, isTrue);
    expect(c.experience.causalHighlights, isTrue);
    c.dispose();
  });

  test('what-if experiment can be compared, kept or discarded', () {
    final c = GameController(size: 8);
    final before = c.sim.state.hash();
    c.startExperiment();
    expect(c.experimentActive, isTrue);
    expect(c.place(1, 1, TileType.road), isTrue);
    expect(c.sim.state.hash(), isNot(before));

    c.discardExperiment();
    expect(c.experimentActive, isFalse);
    expect(c.sim.state.hash(), before);

    c.startExperiment();
    expect(c.place(2, 2, TileType.forest), isTrue);
    final kept = c.sim.state.hash();
    c.keepExperiment();
    expect(c.experimentActive, isFalse);
    expect(c.sim.state.hash(), kept);
    c.dispose();
  });

  test('challenge medals persist and merge per level', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SaveStore();
    await store.recordMedals('noise', {'noise_no_roads'});
    await store.recordMedals('noise', {'noise_fast'});
    await store.recordMedals('habitat', {'habitat_fast'});
    final medals = await store.earnedMedals();
    expect(medals['noise'], {'noise_no_roads', 'noise_fast'});
    expect(medals['habitat'], {'habitat_fast'});
  });

  test('builds record actual impacts and a bounded visual timeline', () {
    final c = GameController(size: 8);
    c.setExperience(c.experience.copyWith(haptics: false));
    final initialSamples = c.indicatorHistory.length;

    expect(c.place(1, 1, TileType.road), isTrue);
    expect(c.lastImpact, isNotNull);
    expect(c.lastImpact!.tile, TileType.road);
    expect(c.lastImpact!.affectedCells, contains(c.sim.state.index(1, 1)));
    expect(c.indicatorHistory.length, initialSamples + 1);

    c.step();
    expect(c.lastImpact, isNull);
    expect(c.indicatorHistory.last.tick, 1);
    c.dispose();
  });

  test('air overlay consistently treats a high quality index as helpful', () {
    final c = GameController(size: 8);
    c.setOverlay(MapOverlay.air);
    expect(c.overlayHighIsBad, isFalse);
    expect(c.overlayValue(0), inInclusiveRange(0, 1));
    c.dispose();
  });

  test(
    'starter overlays use bands and selected cells expose nearby causes',
    () {
      final c = GameController(size: 8);
      c.setLearningMode(LearningMode.starter);
      c.place(1, 1, TileType.road);
      c.setOverlay(MapOverlay.noise);
      c.select(c.sim.state.index(2, 2));
      expect(c.overlayValue(0), anyOf(0.0, 0.5, 1.0));
      expect(c.overlayThreshold, 0.5);
      expect(c.selectedCausalSourceCells, contains(c.sim.state.index(1, 1)));
      c.dispose();
    },
  );

  test('experiment overlay represents change around a neutral midpoint', () {
    final c = GameController(size: 8);
    c.setLearningMode(LearningMode.explorer);
    c.setOverlay(MapOverlay.noise);
    c.startExperiment();
    expect(c.overlayValue(0), closeTo(0.5, 0.001));
    expect(c.overlayHighIsBad, isFalse);
    expect(c.overlayMeetsThreshold(0), isFalse);
    c.dispose();
  });

  test('level guidance targets an available tile for the weakest goal', () {
    final c = GameController(size: 8);
    c.setExperience(c.experience.copyWith(haptics: false));
    c.startLevel(Level.byId('village')!);
    final guidance = c.goalGuidance;
    expect(guidance, isNotNull);
    final tile = guidance!.tile;
    if (tile != null) {
      expect(c.sim.tileBudget.allowed(tile), isTrue);
    }
    c.dispose();
  });

  test('a goal with nothing to build toward gets the protect hint', () {
    // habitat carries a housing goal and allows no housing tile: the goal is
    // there to stop the player bulldozing the village. Before this, the hint
    // walked its stages and ended on "explore the map", which is true and
    // useless.
    final level = Level.byId('habitat')!;
    final c = GameController(size: level.width);
    c.startLevel(level);
    final housing = level.goals.firstWhere(
      (g) => g.indicator == Indicator.housing,
    );
    expect(
      guidanceCandidatesFor(housing).any(c.sim.tileBudget.allowed),
      isFalse,
      reason: 'the level is supposed to offer no housing tile',
    );

    // Bulldoze homes until housing is the goal furthest from its target.
    for (var i = 0; i < level.map.length && c.goalGuidance?.indicator != Indicator.housing; i++) {
      if (level.map[i] == TileType.housingLow ||
          level.map[i] == TileType.housingHigh) {
        c.place(i % level.width, i ~/ level.width, TileType.meadow);
      }
    }
    expect(c.goalGuidance?.indicator, Indicator.housing);
    expect(c.goalGuidance?.tile, isNull);
    expect(c.guidanceHasNoBuildableTile, isTrue);

    // And a goal that can be built toward keeps the tile suggestion.
    final village = GameController(size: Level.byId('village')!.width);
    village.startLevel(Level.byId('village')!);
    expect(village.guidanceHasNoBuildableTile, isFalse);
    village.dispose();
    c.dispose();
  });

  test('controller undo and redo restore complete build state', () {
    final c = GameController(size: 8);
    c.sim = Simulation(
      state: WorldState.empty(width: 8, height: 8, budgetKEur: 1000),
      tileBudget: TileBudget({TileType.road: 1, TileType.forest: null}),
    );
    final initialBudget = c.sim.state.budgetKEur;

    expect(c.place(1, 1, TileType.road), isTrue);
    final builtBudget = c.sim.state.budgetKEur;
    expect(c.sim.tileBudget.remaining(TileType.road), 0);
    expect(c.canUndo, isTrue);
    expect(c.canRedo, isFalse);

    c.undo();
    expect(c.sim.state.tileAt(1, 1), TileType.terrain);
    expect(c.sim.state.budgetKEur, initialBudget);
    expect(c.sim.tileBudget.remaining(TileType.road), 1);
    expect(c.canUndo, isFalse);
    expect(c.canRedo, isTrue);

    c.redo();
    expect(c.sim.state.tileAt(1, 1), TileType.road);
    expect(c.sim.state.budgetKEur, builtBudget);
    expect(c.sim.tileBudget.remaining(TileType.road), 0);
    expect(c.canUndo, isTrue);
    expect(c.canRedo, isFalse);

    c.undo();
    expect(c.place(2, 2, TileType.forest), isTrue);
    expect(c.canRedo, isFalse, reason: 'a new edit forks history');
    c.step();
    expect(c.canUndo, isFalse, reason: 'time advancement closes history');
    c.dispose();
  });

  test(
    'placement preview uses a copied simulation and real field changes',
    () async {
      final c = GameController(size: 8);
      c.setBrush(TileType.commercial);
      c.setHover(c.sim.state.index(4, 4));
      final before = c.sim.state.hash();

      final immediate = c.placementPreview;
      expect(immediate, isNotNull);
      expect(immediate!.affectedCells, {c.sim.state.index(4, 4)});
      await Future<void>.delayed(const Duration(milliseconds: 120));
      final preview = c.placementPreview;

      expect(preview, isNotNull);
      expect(preview!.isValid, isTrue);
      expect(preview.tile, TileType.commercial);
      expect(preview.affectedOverlay, MapOverlay.retail);
      expect(preview.affectedCells, contains(c.sim.state.index(4, 4)));
      expect(preview.affectedCells.length, greaterThan(1));
      expect(
        c.sim.state.hash(),
        before,
        reason: 'forecast must not mutate the live world',
      );
      expect(
        identical(c.placementPreview, preview),
        isTrue,
        reason: 'forecast is cached for an unchanged cell',
      );
      c.dispose();
    },
  );
}
