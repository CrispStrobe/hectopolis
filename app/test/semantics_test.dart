// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart' hide Simulation;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stadtbau/game/game_controller.dart';
import 'package:stadtbau/l10n/generated/app_localizations.dart';
import 'package:stadtbau/ui/game_screen.dart';
import 'package:stadtbau/ui/map_view.dart';
import 'package:stadtbau_sim/stadtbau_sim.dart';

Widget _app(GameController c) => MediaQuery(
  data: const MediaQueryData(disableAnimations: true),
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: GameScreen(controller: c, onLocaleToggle: () {}),
  ),
);

void main() {
  testWidgets('the map announces the cell the cursor is on', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    // The semantics tree is only built when something is listening.
    // Disposed at the end of the body, not in a tearDown: the check for
    // undisposed handles runs first.
    final handle = tester.ensureSemantics();

    final c = GameController(size: 12);
    addTearDown(c.dispose);
    await tester.pumpWidget(_app(c));
    await tester.pump(const Duration(seconds: 1));
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    // Nothing selected yet: the map says so rather than saying nothing.
    expect(
      find.bySemanticsLabel(l10n.a11yMapLabel),
      findsOneWidget,
      reason: 'the map should be a labelled region',
    );

    // Cursor keys are map-scoped by design, so the map has to hold the
    // keyboard first. A tap with no brush selected only selects a cell.
    final mapRect = tester.getRect(find.byType(MapView));
    await tester.tapAt(mapRect.center);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    final cell = c.cursorCell ?? c.selectedCell;
    expect(cell, isNotNull, reason: 'the map should have a cursor by now');

    final node = tester.getSemantics(find.bySemanticsLabel(l10n.a11yMapLabel));
    // The spoken value names the cell and its tile, and carries readings a
    // sighted player gets from the inspector panel.
    expect(node.value, contains('${cell! % c.width}'));
    expect(node.value, contains(l10n.tileName(c.sim.state.tiles[cell].id)));
    expect(node.value.toLowerCase(), contains('decibel'));
    // And it is a live region, so moving the cursor is announced rather than
    // only being readable if the user goes looking.
    expect(
      node.flagsCollection.isLiveRegion,
      isTrue,
      reason: 'cursor moves must be announced',
    );
    handle.dispose();
  });

  testWidgets('every indicator gauge speaks its own reading', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    // Disposed at the end of the body, not in a tearDown: the check for
    // undisposed handles runs first.
    final handle = tester.ensureSemantics();

    final c = GameController(size: 12);
    addTearDown(c.dispose);
    await tester.pumpWidget(_app(c));
    await tester.pump(const Duration(seconds: 1));
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    // A gauge reads "<name>: <value> of 100. <detail>" -- the bar and the
    // number are invisible to a screen reader without it.
    var spoken = 0;
    for (final indicator in Indicator.values) {
      final name = RegExp.escape(l10n.indicatorName(indicator.name));
      final found = find.bySemanticsLabel(RegExp('$name:.*of 100'));
      if (found.evaluate().isNotEmpty) spoken++;
    }
    expect(
      spoken,
      greaterThanOrEqualTo(5),
      reason: 'the gauges on screen should each carry a spoken reading',
    );
    handle.dispose();
  });

  testWidgets('a palette card names its tile, cost and stock', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    // Disposed at the end of the body, not in a tearDown: the check for
    // undisposed handles runs first.
    final handle = tester.ensureSemantics();

    final c = GameController(size: 12);
    addTearDown(c.dispose);
    await tester.pumpWidget(_app(c));
    await tester.pump(const Duration(seconds: 1));
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    final meadow = l10n.tileName(TileType.meadow.id);
    expect(
      find.bySemanticsLabel(RegExp('${RegExp.escape(meadow)}, costs')),
      findsOneWidget,
    );

    // Selecting it changes what the card says, not just how it looks.
    c.setBrush(TileType.meadow);
    await tester.pump();
    expect(
      find.bySemanticsLabel(l10n.a11yTileSelected(meadow)),
      findsOneWidget,
    );
    handle.dispose();
  });
}
