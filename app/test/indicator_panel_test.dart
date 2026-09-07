// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stadtbau/game/game_controller.dart';
import 'package:stadtbau/game/experience_settings.dart';
import 'package:stadtbau/l10n/generated/app_localizations.dart';
import 'package:stadtbau/ui/indicator_panel.dart';
import 'package:stadtbau_sim/stadtbau_sim.dart';

Widget _app(
  GameController c, {
  required bool compact,
  Locale locale = const Locale('en'),
}) => MaterialApp(
  locale: locale,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: IndicatorPanel(controller: c, compact: compact),
  ),
);

void main() {
  test('every indicator maps to a model document', () {
    for (final i in Indicator.values) {
      expect(indicatorDocFile[i], isNotNull, reason: i.name);
      expect(indicatorDocUrl(i), startsWith(indicatorDocsBaseUrl));
    }
    expect(
      indicatorDocUrl(Indicator.commuting),
      endsWith('/docs/model/commute.md'),
    );
    expect(indicatorDocUrl(Indicator.climate), endsWith('/docs/model/heat.md'));
    expect(
      indicatorDocUrl(Indicator.housing),
      endsWith('/docs/model/economy.md'),
    );
  });

  testWidgets('tapping a gauge opens the detail sheet with the source link', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(500, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final c = GameController(size: 8);
    addTearDown(c.dispose);
    final t = await AppLocalizations.delegate.load(const Locale('en'));

    await tester.pumpWidget(_app(c, compact: false));
    await tester.pumpAndSettle();

    expect(find.text(t.indicatorSourceLink), findsNothing);
    await tester.tap(find.text(t.indicatorName('noise')));
    await tester.pumpAndSettle();

    expect(find.text(t.indicatorFormulaLabel), findsOneWidget);
    expect(find.text(t.indicatorFormula('noise')), findsOneWidget);
    expect(find.text(t.indicatorSourceLink), findsOneWidget);
    expect(find.text(t.indicatorHint('noise')), findsOneWidget);

    await tester.tap(find.text(t.actionClose));
    await tester.pumpAndSettle();
    expect(find.text(t.indicatorSourceLink), findsNothing);
  });

  testWidgets('the compact strip opens the same sheet on tap', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 300));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final c = GameController(size: 8);
    addTearDown(c.dispose);
    final t = await AppLocalizations.delegate.load(const Locale('en'));

    await tester.pumpWidget(_app(c, compact: true));
    await tester.pumpAndSettle();

    await tester.tap(find.text(t.indicatorName('biodiversity')));
    await tester.pumpAndSettle();
    expect(find.text(t.indicatorSourceLink), findsOneWidget);
    expect(find.text(t.indicatorFormula('biodiversity')), findsOneWidget);
  });

  testWidgets('the sheet is localised in German', (tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final c = GameController(size: 8);
    addTearDown(c.dispose);
    final de = await AppLocalizations.delegate.load(const Locale('de'));

    await tester.pumpWidget(
      _app(c, compact: false, locale: const Locale('de')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(de.indicatorName('budget')));
    await tester.pumpAndSettle();
    expect(find.text(de.indicatorSourceLink), findsOneWidget);
  });

  testWidgets('simple mode keeps technical indicator details out of the flow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(500, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final c = GameController(size: 8)
      ..setExperience(
        const ExperienceSettings(simpleMode: true, haptics: false),
      );
    addTearDown(c.dispose);
    final t = await AppLocalizations.delegate.load(const Locale('en'));

    await tester.pumpWidget(_app(c, compact: false));
    await tester.pump();
    await tester.tap(find.text(t.indicatorName('noise')));
    await tester.pump();

    expect(find.text(t.indicatorSourceLink), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            const {'😄', '🙂', '😐', '🙁', '😠'}.contains(widget.data),
      ),
      findsWidgets,
    );
  });
}
