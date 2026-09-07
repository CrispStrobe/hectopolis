// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
