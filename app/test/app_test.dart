// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart' hide Simulation;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stadtbau/game/experience_settings.dart';
import 'package:stadtbau/game/game_controller.dart';
import 'package:stadtbau/game/save_store.dart';
import 'package:stadtbau/main.dart';
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
