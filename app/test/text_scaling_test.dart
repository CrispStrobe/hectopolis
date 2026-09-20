// SPDX-License-Identifier: AGPL-3.0-or-later
// T-701: the UI at large system font sizes.
//
// WCAG 1.4.4 (Resize Text) asks that text scale to 200 % without loss of
// content or functionality, and both BITV 2.0 and EN 301 549 point at it. On
// a phone or a desktop the player sets that in the OS, not in the app, so the
// app finds out through `MediaQuery.textScaler` and has to cope.
//
// A Flutter overflow is exactly "loss of content": the clipped part is still
// laid out, still in the semantics tree, and invisible. It is reported as an
// error rather than thrown, so a widget test has to install its own
// `FlutterError.onError` to see one -- which is why this bug survived every
// other test in this directory.
//
// What this found when it was written: the compact palette strip clipped by
// 4 px at *100 %* text, on any narrow window, in both languages; the same
// strip and the indicator strip clipped by up to 86 px at 200 %; and the
// roomy app bar overflowed by 87 px at 200 % on a 1400 px desktop, because
// its breakpoint was in pixels while what had to fit was text.
import 'package:flutter/material.dart' hide Simulation;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stadtbau/game/experience_settings.dart';
import 'package:stadtbau/game/game_controller.dart';
import 'package:stadtbau/l10n/generated/app_localizations.dart';
import 'package:stadtbau/ui/game_screen.dart';

/// Renders the game screen and returns every overflow it reported, attributed
/// to the widget that caused it so a failure names a file rather than a pixel
/// count.
Future<List<String>> _overflows(
  WidgetTester tester, {
  required Size size,
  required double scale,
  required String locale,
  required bool simpleMode,
}) async {
  final errors = <String>[];
  final prior = FlutterError.onError;
  FlutterError.onError = (details) {
    // A broken layout reports the same overflow on every frame, and
    // stringifying each one turned a failing run from seconds into minutes.
    // The cap costs nothing when the test passes, and a failure needs one
    // example per site, not thousands.
    if (errors.length >= 32) return;
    final text = details.toString();
    if (!text.contains('overflowed')) {
      prior?.call(details);
      return;
    }
    final lines = text.split('\n');
    final what =
        lines.firstWhere((l) => l.contains('overflowed'), orElse: () => '?');
    final who =
        lines.indexWhere((l) => l.contains('relevant error-causing widget'));
    final where = who >= 0 && who + 2 < lines.length
        ? lines[who + 2].trim().split('/').last
        : 'unattributed';
    errors.add('${what.trim()} in $where');
  };

  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  final controller = GameController(size: 12);
  addTearDown(controller.dispose);
  // Simple mode swaps numbers for icons and drops the cost line, so it is a
  // materially different layout, not a skin.
  controller.setLearningMode(
      simpleMode ? LearningMode.starter : LearningMode.guided);

  await tester.pumpWidget(
    MediaQuery(
      // Reduce-motion for the same reason render_map_png.dart needs it: the
      // map runs a repeating controller and `pumpAndSettle` never returns.
      data: MediaQueryData(
        disableAnimations: true,
        textScaler: TextScaler.linear(scale),
      ),
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          // The same four the app installs. Without the Cupertino one a
          // German build logs a warning through FlutterError, which this test
          // forwards rather than swallows -- correctly, but it is not an
          // overflow and should not be here at all.
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale(locale),
        home: GameScreen(controller: controller, onLocaleToggle: () {}),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // Restore the handler here rather than in a tearDown. The binding asserts if
  // `expect` runs while FlutterError.onError is still overridden -- and the
  // assertion arrives as an uncaught error during teardown, which turned every
  // real failure into a six-minute cascade that hid the failure itself.
  FlutterError.onError = prior;
  return errors.toSet().toList();
}

void main() {
  // A desktop window, a small laptop and a phone in portrait. The narrow
  // layouts are where the strips live, and the wide one is where the app bar
  // lays its actions out inline.
  const sizes = <String, Size>{
    'desktop 1400x1000': Size(1400, 1000),
    'laptop 1100x800': Size(1100, 800),
    'phone 420x900': Size(420, 900),
  };

  // 1.0 is the regression guard -- one of these bugs was present at default
  // settings. 2.0 is what WCAG 1.4.4 asks for. 1.3 and 1.6 are in between
  // because a layout can pass at both ends and fail in the middle, the same
  // lesson the contrast sweep learned about the gauge scale.
  const scales = [1.0, 1.3, 1.6, 2.0];

  for (final entry in sizes.entries) {
    for (final scale in scales) {
      testWidgets('${entry.key} at ${(scale * 100).round()} % text fits',
          (tester) async {
        for (final locale in ['en', 'de']) {
          for (final simpleMode in [false, true]) {
            final found = await _overflows(
              tester,
              size: entry.value,
              scale: scale,
              locale: locale,
              simpleMode: simpleMode,
            );
            expect(
              found,
              isEmpty,
              reason: 'WCAG 1.4.4: content clipped at ${entry.key}, '
                  '${(scale * 100).round()} % text, $locale, '
                  '${simpleMode ? 'simple' : 'expert'} mode:\n'
                  '  ${found.join('\n  ')}',
            );
          }
        }
      });
    }
  }
}
