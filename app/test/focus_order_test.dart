// SPDX-License-Identifier: AGPL-3.0-or-later
// T-701: focus order, checked rather than assumed.
//
// WCAG 2.4.3 (Focus Order) asks that tabbing move through a page in an order
// that preserves meaning and operability, and 2.1.2 (No Keyboard Trap) that it
// can always move on. Both are testable without a screen reader: the traversal
// order is a property of the widget tree, so a widget test can walk it.
//
// What a test cannot check is whether the order *makes sense to a person*.
// What it can check, and what this does, is that every control is reachable,
// that nothing traps the keyboard, and that the order is stable -- so a
// refactor that silently strands a button fails here.
import 'package:flutter/material.dart' hide Simulation;
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stadtbau/game/game_controller.dart';
import 'package:stadtbau/l10n/generated/app_localizations.dart';
import 'package:stadtbau/ui/game_screen.dart';

/// Tabs once and returns a label for whatever holds focus, so an order can be
/// compared as text instead of as opaque node identities.
String _focused() {
  final node = FocusManager.instance.primaryFocus;
  if (node == null) return '<none>';
  final context = node.context;
  if (context == null) return '<detached>';
  final widget = context.widget;
  // A tooltip is the only user-visible name an icon button has, and it is
  // what a screen reader announces, so it is the right label to assert on.
  final tooltip = context.findAncestorWidgetOfExactType<Tooltip>()?.message;
  if (tooltip != null && tooltip.isNotEmpty) return tooltip;
  final semantics = context.findAncestorWidgetOfExactType<Semantics>();
  final label = semantics?.properties.label;
  if (label != null && label.isNotEmpty) return label.split('\n').first;
  return widget.runtimeType.toString();
}

void main() {
  Future<void> pumpGame(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final c = GameController(size: 12);
    addTearDown(c.dispose);
    await tester.pumpWidget(
      // Reduce-motion, for the same reason render_map_png.dart needs it: the
      // map runs a repeating animation controller, so `pumpAndSettle` waits
      // for a tree that never settles and times out.
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: GameScreen(controller: c, onLocaleToggle: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('tabbing reaches every control and never traps the keyboard',
      (tester) async {
    await pumpGame(tester);

    // Walk far enough to come back round: the point is that the traversal
    // closes, not that it is any particular length.
    final seen = <String>[];
    String? firstRepeat;
    for (var i = 0; i < 80; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final label = _focused();
      if (seen.contains(label) && firstRepeat == null) firstRepeat = label;
      seen.add(label);
    }

    expect(firstRepeat, isNotNull,
        reason: 'focus never returned to anything it had already visited, '
            'which means the traversal does not close');
    final unique = seen.toSet();
    expect(unique, isNot(contains('<none>')),
        reason: 'focus fell off the tree: WCAG 2.1.2 keyboard trap');
    expect(unique, isNot(contains('<detached>')));
    expect(unique.length, greaterThan(5),
        reason: 'only ${unique.length} focus stops were reachable by keyboard');
  });

  testWidgets('the app-bar controls are all reachable by keyboard',
      (tester) async {
    await pumpGame(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    // Every tooltip in the app bar names an action a mouse user can take, so
    // each has to be reachable without one.
    final wanted = <String>{
      l10n.actionBackToLevels,
      l10n.actionZoomOut,
      l10n.actionZoomIn,
      l10n.actionZoomReset,
    };
    final seen = <String>{};
    for (var i = 0; i < 80 && !seen.containsAll(wanted); i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      seen.add(_focused());
    }
    expect(seen, containsAll(wanted),
        reason: 'not reachable by Tab: ${wanted.difference(seen)}');
  });

  testWidgets('shift-tab goes back the way it came', (tester) async {
    await pumpGame(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final first = _focused();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final second = _focused();
    expect(second, isNot(first));

    // One step further, then one step back, which must undo it exactly.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await simulateKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await simulateKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(_focused(), second,
        reason: 'backwards traversal did not mirror forwards traversal');
  });
}
