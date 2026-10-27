// SPDX-License-Identifier: AGPL-3.0-or-later
// "Our apps" in About: the list of our other apps and their Apple links.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stadtbau/l10n/generated/app_localizations.dart';
import 'package:stadtbau/ui/app_showcase.dart';

Widget _app(Locale locale) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: const Scaffold(body: SingleChildScrollView(child: AppShowcase())),
);

void main() {
  test(
    'every app has its icon, a line in both languages and only Apple links',
    () async {
      expect(showcaseApps.length, greaterThanOrEqualTo(19));
      expect(
        showcaseApps.map((a) => a.slug).toSet(),
        hasLength(showcaseApps.length),
      );
      expect(showcaseApps.where((a) => a.self).map((a) => a.slug), [
        'hectopolis',
      ]);
      final en = await AppLocalizations.delegate.load(const Locale('en'));
      final de = await AppLocalizations.delegate.load(const Locale('de'));
      for (final app in showcaseApps) {
        expect(File(app.icon).existsSync(), isTrue, reason: '${app.slug} icon');
        expect(en.aboutAppDescription(app.slug), isNotEmpty, reason: app.slug);
        expect(de.aboutAppDescription(app.slug), isNotEmpty, reason: app.slug);
        if (app.store != null) {
          expect(app.store, matches(RegExp(r'^\d{9,11}$')), reason: app.slug);
        }
        if (app.beta != null) {
          expect(
            app.beta,
            matches(RegExp(r'^[A-Za-z0-9]{8}$')),
            reason: app.slug,
          );
        }
        for (final uri in [app.storeUri, app.betaUri].nonNulls) {
          expect(uri.scheme, 'https');
          expect(uri.host, anyOf('apps.apple.com', 'testflight.apple.com'));
        }
      }
    },
  );

  test('live apps come first, then betas, and this app last', () {
    final order = showcaseOrder();
    expect(order.last.slug, 'hectopolis');
    final live = order.takeWhile((a) => a.store != null).length;
    expect(order.skip(live).where((a) => a.store != null && !a.self), isEmpty);
    final names = order.take(live).map((a) => a.name.toLowerCase()).toList();
    expect(names, [...names]..sort());
  });

  for (final locale in const [Locale('en'), Locale('de')]) {
    testWidgets('renders store, Mac, TestFlight and coming-soon entries '
        '(${locale.languageCode})', (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_app(locale));
      await tester.pumpAndSettle();
      final l10n = await AppLocalizations.delegate.load(locale);

      for (final app in showcaseApps) {
        expect(find.byKey(ValueKey('showcase-${app.slug}')), findsOneWidget);
      }
      expect(find.text(l10n.aboutMacAppStore), findsNWidgets(2));
      expect(find.text(l10n.aboutComingSoon), findsOneWidget);
      expect(
        find.textContaining(l10n.aboutThisApp, findRichText: true),
        findsOneWidget,
      );
      expect(
        find.text(l10n.aboutAppDescription('crispsudoku')),
        findsOneWidget,
      );
      // Each link names its app for a screen reader.
      expect(
        find.bySemanticsLabel(
          l10n.aboutAppLink('CometBeat', l10n.aboutAppStore),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          l10n.aboutAppLink('Hectopolis', l10n.aboutMacAppStore),
        ),
        findsOneWidget,
      );
      semantics.dispose();
    });
  }

  testWidgets('a phone-width About keeps one app per row without overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 5000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(const Locale('de')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final first = tester.getRect(
      find.byKey(const ValueKey('showcase-cometbeat')),
    );
    final second = tester.getRect(
      find.byKey(const ValueKey('showcase-crispaudio')),
    );
    expect(second.top, greaterThan(first.bottom - 1));
  });
}
