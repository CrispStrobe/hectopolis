// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:stadtbau/l10n/generated/app_localizations.dart';
import 'package:stadtbau/ui/about_screen.dart';

Widget _app(Locale locale) => MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const AboutScreen(),
    );

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Hectopolis',
      packageName: 'com.crispstrobe.hectopolis',
      version: '0.1.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  for (final locale in const [Locale('en'), Locale('de')]) {
    testWidgets('renders every section and the licenses button (${locale.languageCode})', (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_app(locale));
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(locale);
      for (final label in [
        l10n.aboutProvider,
        l10n.aboutContact,
        l10n.aboutPrivacy,
        l10n.aboutDisclaimer,
        l10n.aboutLicense,
        l10n.aboutDataSources,
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text(AboutScreen.email), findsOneWidget);
      expect(find.text(AboutScreen.phone), findsOneWidget);
      expect(find.textContaining('Bundeskompensationsverordnung'), findsOneWidget);
      expect(find.text(l10n.aboutVersionLabel('0.1.0+1')), findsOneWidget);
      // The licenses button sits below the data-source list, which grows as
      // sources are added, and German wraps longer than English. Scrolling to
      // it is the check; a taller surface only postpones the same failure.
      await tester.scrollUntilVisible(
        find.text(l10n.aboutOpenSourceLicenses),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(l10n.aboutOpenSourceLicenses), findsOneWidget);
    });
  }

  testWidgets('the licenses page opens and lists the app license', (tester) async {
    // A viewport taller than the content can put the last button's centre
    // exactly on the lower hit-test boundary as dependency licences grow.
    // Exercise the real scroll path instead.
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(const Locale('en')));
    await tester.pumpAndSettle();
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.scrollUntilVisible(
      find.text(l10n.aboutOpenSourceLicenses),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text(l10n.aboutOpenSourceLicenses));
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
  });
}
