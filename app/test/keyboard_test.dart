// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart' hide Simulation;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stadtbau/game/game_controller.dart';
import 'package:stadtbau/l10n/generated/app_localizations.dart';
import 'package:stadtbau/ui/game_screen.dart';
import 'package:stadtbau_sim/stadtbau_sim.dart';

Widget _app(GameController c) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: GameScreen(controller: c, onLocaleToggle: () {}),
);

void main() {
  testWidgets('digits pick a tile even when the map has lost the keyboard', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final c = GameController(size: 12);
    addTearDown(c.dispose);
    await tester.pumpWidget(_app(c));
    await tester.pump(const Duration(seconds: 1));

    // Tab off the map, the way a keyboard player reaches the palette or the
    // app bar. Every binding used to live on the map's focus node, so this is
    // exactly where the keyboard used to go dead.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final focused = FocusManager.instance.primaryFocus;
    expect(focused?.debugLabel, isNot('map'), reason: 'focus should have moved');

    expect(c.brush, isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.pump();
    expect(c.brush, c.allowedTypes[1]);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(c.brush, isNull);
  });

  test('selecting a brush hands the keyboard back to the map', () {
    final c = GameController(size: 8);
    addTearDown(c.dispose);
    final seen = <int>[];
    c.mapFocusRequests.addListener(() => seen.add(c.mapFocusRequests.value));

    c.setBrush(TileType.forest);
    expect(seen, isNotEmpty, reason: 'a mouse pick should refocus the map');
    final afterTap = seen.length;

    c.selectBrushByIndex(0);
    expect(seen.length, greaterThan(afterTap), reason: 'so should a digit');

    // An index with no tile behind it changes nothing, focus included.
    final afterDigit = seen.length;
    c.selectBrushByIndex(99);
    expect(seen.length, afterDigit);
  });
}
