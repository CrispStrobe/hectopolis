// SPDX-License-Identifier: AGPL-3.0-or-later
/// Scripted App Store / Play Store screenshot tour (tasks T-402 / T-403).
///
/// This drives the *real* app on a real device, simulator or emulator and
/// captures a screenshot at every stop. The bytes only reach the host machine
/// through the `flutter drive` adaptor, so run it as:
///
/// ```sh
/// cd app
/// SCREENSHOT_DEVICE="iPhone 16 Pro Max" flutter drive \
///   --driver=test_driver/integration_test.dart \
///   --target=integration_test/screenshots_test.dart \
///   -d <device-id>
/// ```
///
/// `test_driver/integration_test.dart` writes them to
/// `app/screenshots/<device>/<locale>_<stop>.png`. See
/// `docs/release/screenshots.md` for the whole pipeline.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stadtbau/game/game_controller.dart';
import 'package:stadtbau/l10n/generated/app_localizations.dart';
import 'package:stadtbau/main.dart';
import 'package:stadtbau/ui/game_screen.dart';
import 'package:stadtbau/ui/level_select_screen.dart';
import 'package:stadtbau_sim/stadtbau_sim.dart';

/// One tile placement of the showcase city.
typedef Move = (int x, int y, TileType tile);

/// The tour runs once per locale; every screenshot name carries the code as a
/// prefix (`en_02_map.png`). The app has no `locale` constructor argument, so
/// the language is switched through the UI's translate button, exactly the way
/// a player would (see [_ensureLocale]).
const List<String> _locales = <String>['en', 'de'];

/// The level the showcase city is built in: the largest map, the widest tile
/// budget and six goals, so the goals panel is worth a screenshot.
const String _levelId = 'quarter';

/// Months simulated before the map/overlay/inspector stops, and again before
/// the goals stop, so that the last screenshot shows a grown city.
const int _monthsBeforeMap = 24;
const int _monthsBeforeGoals = 36;

/// `SaveStore._onboardingKey` in `lib/game/save_store.dart` — pre-seeding it
/// keeps the first-run overlay out of the screenshots. The key is duplicated
/// here on purpose (it is private); [_dismissOverlays] is the safety net if it
/// ever changes.
const String _onboardingSeenKey = 'stadtbau.onboarding.v1';

/// macOS has no `integration_test` screenshot channel implementation. Its CI
/// job supplies this compile-time path, so the same real widget surface can be
/// encoded directly without host screen-recording permissions.
const String _directScreenshotOutput = String.fromEnvironment(
  'SCREENSHOT_OUTPUT',
);
const Key _captureKey = ValueKey<String>('store-screenshot-surface');

Future<void> main() async {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('store screenshot tour', (tester) async {
    // Hosted Mac runners expose a smaller virtual display and AppKit shrinks
    // the requested 1280×800 window to fit it. The store capture renders the
    // widget surface itself, so give that surface the exact accepted Mac App
    // Store dimensions independent of the runner's display.
    if (_directScreenshotOutput.isNotEmpty) {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
    }

    // No-op off Android; on Android it swaps the Flutter surface for an image
    // reader, without which takeScreenshot() throws. Exactly once per test.
    await binding.convertFlutterSurfaceToImage();

    expect(
      Level.byId(_levelId),
      isNotNull,
      reason: 'level "$_levelId" is gone from data/levels',
    );

    for (final locale in _locales) {
      await _tour(tester, binding, locale);
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}

/// One full pass of the tour in [locale], from a clean install.
Future<void> _tour(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
  String locale,
) async {
  // Deterministic state: no autosave, no stars, onboarding already seen.
  SharedPreferences.setMockInitialValues(<String, Object>{
    _onboardingSeenKey: true,
  });

  // A per-locale key forces a fresh HectopolisApp state (and therefore a fresh
  // GameController and Navigator); re-pumping the identical widget would only
  // update the existing element and leave the previous run's route on top.
  await tester.pumpWidget(
    RepaintBoundary(
      key: _captureKey,
      child: HectopolisApp(key: ValueKey<String>('run-$locale')),
    ),
  );
  await _settle(tester);
  await _dismissOverlays(tester);
  await _ensureLocale(tester, locale);

  await _shot(tester, binding, locale, '01_levels');

  await _openLevel(tester);
  final controller = tester
      .widget<GameScreen>(find.byType(GameScreen))
      .controller;
  controller.setSpeed(0); // no tick timer may fire while a screenshot is taken

  _buildShowcase(controller);
  _advance(controller, _monthsBeforeMap);
  controller.select(null);
  controller.setOverlay(MapOverlay.none);
  await _settle(tester);
  await _dismissOverlays(tester);
  await _shot(tester, binding, locale, '02_map');

  controller.setOverlay(MapOverlay.noise);
  await _shot(tester, binding, locale, '03_noise_overlay');

  controller.setOverlay(MapOverlay.air);
  await _shot(tester, binding, locale, '04_air_overlay');

  controller.setOverlay(MapOverlay.none);
  controller.select(controller.sim.state.index(3, 3)); // an apartment block
  await _shot(tester, binding, locale, '05_inspector');

  _advance(controller, _monthsBeforeGoals);
  controller.select(null);
  controller.setOverlay(MapOverlay.green); // the recreation goal, visualised
  await _settle(tester);
  await _dismissOverlays(tester);
  await _shot(tester, binding, locale, '06_goals');
}

/// Tap the [_levelId] card on the level select screen and wait for the game.
Future<void> _openLevel(WidgetTester tester) async {
  final l10n = AppLocalizations.of(
    tester.element(find.byType(LevelSelectScreen)),
  );
  final card = find.widgetWithText(Card, l10n.levelTitle(_levelId));
  expect(
    card,
    findsOneWidget,
    reason: 'no level card titled "${l10n.levelTitle(_levelId)}"',
  );
  await tester.ensureVisible(card);
  await _settle(tester);
  await tester.tap(card);
  await _settle(tester);
  await _dismissOverlays(tester);
  expect(find.byType(GameScreen), findsOneWidget);
}

/// Build the showcase city by driving the controller directly — the same plan
/// `packages/stadtbau_sim/test/level_solutions_test.dart` solves "quarter"
/// with, so it is known to fit the tile and money budget.
void _buildShowcase(GameController controller) {
  for (final (x, y, tile) in _showcaseMoves()) {
    final placed = controller.place(x, y, tile);
    if (!placed) {
      fail(
        'screenshot tour: cannot place ${tile.id} at ($x,$y): ${controller.lastError}',
      );
    }
  }
}

List<Move> _showcaseMoves() {
  final moves = <Move>[];
  void rect(int x0, int y0, int w, int h, TileType t) {
    for (var y = y0; y < y0 + h; y++) {
      for (var x = x0; x < x0 + w; x++) {
        moves.add((x, y, t));
      }
    }
  }

  rect(1, 7, 14, 1, TileType.road); // east-west spine off the access road
  rect(7, 1, 1, 6, TileType.road); // north branch
  rect(2, 3, 4, 2, TileType.housingHigh); // apartment blocks
  rect(9, 3, 4, 2, TileType.housingHigh);
  rect(2, 10, 4, 2, TileType.housingLow); // detached homes
  rect(9, 10, 4, 2, TileType.housingLow);
  rect(3, 5, 4, 1, TileType.commercial); // shops and offices on the spine
  rect(8, 5, 4, 1, TileType.commercial);
  rect(2, 9, 4, 1, TileType.park); // parks between homes and spine
  rect(9, 9, 2, 1, TileType.park);
  rect(13, 0, 3, 16, TileType.forest); // wood along the eastern edge
  rect(0, 0, 13, 2, TileType.forest); // and along the northern edge
  return moves;
}

/// Advance the clock [months] steps, stopping early once the level is over so
/// that the end-of-level dialog never lands in a screenshot.
void _advance(GameController controller, int months) {
  for (var m = 0; m < months; m++) {
    controller.step();
    if (controller.endPending || (controller.progress?.allMet ?? false)) return;
  }
}

/// Switch the app to [languageCode] by tapping the translate action, which
/// flips between the two supported locales.
Future<void> _ensureLocale(WidgetTester tester, String languageCode) async {
  for (var attempt = 0; attempt < 3; attempt++) {
    final context = tester.element(find.byType(LevelSelectScreen));
    if (Localizations.localeOf(context).languageCode == languageCode) return;
    await tester.tap(find.byIcon(Icons.translate).first);
    await _settle(tester);
  }
  fail('screenshot tour: could not switch the app to "$languageCode"');
}

/// Close anything modal that sits on top of the tour: the first-run onboarding
/// overlay, the end-of-level dialog, a stray popup menu. Every one of those is
/// an [AlertDialog]/[Dialog] whose first [TextButton] is the way out (Skip,
/// Cancel, Keep playing); a first-run overlay that is not a dialog is caught by
/// the "Skip"-style label heuristic instead. All of it is optional: when there
/// is nothing to close this returns immediately.
Future<void> _dismissOverlays(WidgetTester tester) async {
  for (var attempt = 0; attempt < 4; attempt++) {
    final dialog = find.byWidgetPredicate(
      (w) => w is Dialog || w is AlertDialog,
    );
    Finder? button;
    if (dialog.evaluate().isNotEmpty) {
      final buttons = find.descendant(
        of: dialog.first,
        matching: find.byType(TextButton),
      );
      if (buttons.evaluate().isNotEmpty) button = buttons.first;
    } else {
      final skip = find.byWidgetPredicate(_isSkipButton);
      if (skip.evaluate().isNotEmpty) button = skip.first;
    }
    if (button == null) return;
    await tester.tap(button, warnIfMissed: false);
    await _settle(tester);
  }
}

/// A [TextButton] labelled like a "skip the intro" button in either language.
bool _isSkipButton(Widget widget) {
  if (widget is! TextButton) return false;
  final child = widget.child;
  if (child is! Text) return false;
  final label = (child.data ?? '').trim().toLowerCase();
  return const <String>{
    'skip',
    'überspringen',
    'uberspringen',
    'weiter',
    'los geht’s',
    "los geht's",
    'got it',
    'verstanden',
    'fertig',
    'done',
  }.contains(label);
}

/// Let the frame settle and then hold the screen for a few real frames, so the
/// device surface shows the finished state (and any tap highlight has faded)
/// before the pixels are read.
Future<void> _settle(WidgetTester tester, {int holdFrames = 10}) async {
  // Map traffic and ambient details animate continuously, so pumpAndSettle
  // would correctly never consider a game screen idle. A bounded second is
  // enough for navigation, sheets and the 650 ms overlay interpolation.
  for (var i = 0; i < holdFrames + 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Capture one stop of the tour. The name is what the driver writes to disk.
Future<void> _shot(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
  String locale,
  String stop,
) async {
  await _settle(tester);
  if (_directScreenshotOutput.isNotEmpty) {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_captureKey),
    );
    final context = tester.element(find.byKey(_captureKey));
    final ratio = View.of(context).devicePixelRatio.clamp(1.0, 2.0).toDouble();
    final image = await boundary.toImage(pixelRatio: ratio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) fail('could not encode $locale $stop as PNG');
    final directory = Directory(_directScreenshotOutput);
    await directory.create(recursive: true);
    final file = File('${directory.path}/${locale}_$stop.png');
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
    return;
  }
  await binding.takeScreenshot('${locale}_$stop');
}
