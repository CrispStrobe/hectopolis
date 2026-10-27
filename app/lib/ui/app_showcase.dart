// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/generated/app_localizations.dart';

/// One of our apps in "Our apps", the gallery in About.
class ShowcaseApp {
  const ShowcaseApp(
    this.slug,
    this.name, {
    this.store,
    this.mac = false,
    this.beta,
    this.self = false,
  });

  /// Icon file name in assets/app_showcase/ and the key of its description
  /// (`aboutAppDescription`).
  final String slug;

  /// A product name, the same in every language.
  final String name;

  /// App Store id, when the app is live there; [mac]: only on the Mac App Store.
  final String? store;
  final bool mac;

  /// Public TestFlight code. Neither this nor [store]: a private beta, listed
  /// as coming soon.
  final String? beta;

  /// Hectopolis itself.
  final bool self;

  String get icon => 'assets/app_showcase/$slug.png';
  Uri? get storeUri =>
      store == null ? null : Uri.parse('https://apps.apple.com/app/id$store');
  Uri? get betaUri => beta == null
      ? null
      : Uri.parse('https://testflight.apple.com/join/$beta');
}

/// Every app of this developer account, as of 2026-10-27: App Store Connect
/// (apps, public TestFlight group links) and the public App Store lookup for
/// which apps are live. The same list as Brickwright's About dialog; links
/// never point anywhere but Apple.
const showcaseApps = [
  ShowcaseApp('brickwright', 'Brickwright', beta: 'UngCMwHZ'),
  ShowcaseApp('cometbeat', 'CometBeat', store: '6791962816', beta: 'cKUMvyqU'),
  ShowcaseApp(
    'crispaudio',
    'CrispAudio',
    store: '6791876962',
    beta: 'YpRwC6wF',
  ),
  ShowcaseApp('crispbingo', 'CrispBingo', beta: '3CG3SfZ9'),
  ShowcaseApp('crispchess', 'CrispChess', beta: 'UCk7DK56'),
  ShowcaseApp('crispcloud', 'CrispCloud', beta: 'eFXzu56b'),
  ShowcaseApp('crispdeck', 'CrispDeck', beta: 'hYwFh4Ut'),
  ShowcaseApp('crispmath', 'CrispMath', beta: 'E6HdVhTx'),
  ShowcaseApp('crispmesh', 'CrispMesh', beta: 'Pk6ds8vY'),
  ShowcaseApp('crisperplayer', 'CrisperPlayer'),
  ShowcaseApp(
    'crisperweaver',
    'CrisperWeaver',
    store: '6789600762',
    beta: 'svwfvHvh',
  ),
  ShowcaseApp('crispsorter', 'CrispSorter', beta: 'eqpChBGM'),
  ShowcaseApp(
    'crispsudoku',
    'CrispSudoku',
    store: '6788990894',
    beta: 'gjFeKMcH',
  ),
  ShowcaseApp('crisptuner', 'CrispTuner', beta: 'nfCbAzy4'),
  ShowcaseApp(
    'hectopolis',
    'Hectopolis',
    store: '6809142647',
    mac: true,
    beta: 'paBCcWnH',
    self: true,
  ),
  ShowcaseApp('kerotakis', 'Kerotakis', store: '6805214816', beta: 'P3WxEdqp'),
  ShowcaseApp('naga', 'Naga – The Snake Game', beta: 'SuVAjkwH'),
  ShowcaseApp(
    'numbernebula',
    'NumberNebula',
    store: '6789984849',
    mac: true,
    beta: 'GDzrzSF5',
  ),
  ShowcaseApp(
    'word_universe',
    'Word Universe',
    store: '6790143931',
    beta: '6CQMmAnt',
  ),
];

/// Live apps first, then betas, each alphabetically; this app last.
List<ShowcaseApp> showcaseOrder() {
  int rank(ShowcaseApp app) => app.self ? 2 : (app.store != null ? 0 : 1);
  return [...showcaseApps]..sort((a, b) {
    final byRank = rank(a).compareTo(rank(b));
    return byRank != 0
        ? byRank
        : a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
}

/// The gallery: a card per app with its icon, a line about it and its links.
class AppShowcase extends StatelessWidget {
  const AppShowcase({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.aboutOurAppsIntro),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = 8.0;
            final columns = ((constraints.maxWidth + gap) / 238).floor().clamp(
              1,
              4,
            );
            final width =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final app in showcaseOrder())
                  SizedBox(
                    width: width,
                    child: _AppTile(app: app),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _AppTile extends StatelessWidget {
  const _AppTile({required this.app});

  final ShowcaseApp app;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Container(
      key: ValueKey('showcase-${app.slug}'),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset(
              app.icon,
              width: 44,
              height: 44,
              excludeFromSemantics: true,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    text: app.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    children: [
                      if (app.self)
                        TextSpan(
                          text: ' (${l10n.aboutThisApp})',
                          style: const TextStyle(fontWeight: FontWeight.w400),
                        ),
                    ],
                  ),
                ),
                Text(
                  l10n.aboutAppDescription(app.slug),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (app.storeUri case final uri?)
                      _StoreLink(
                        app: app,
                        label: app.mac
                            ? l10n.aboutMacAppStore
                            : l10n.aboutAppStore,
                        uri: uri,
                        filled: true,
                      ),
                    if (app.betaUri case final uri?)
                      _StoreLink(
                        app: app,
                        label: l10n.aboutTestFlight,
                        uri: uri,
                        filled: false,
                      ),
                    if (app.store == null && app.beta == null)
                      // Not a link: a pill the size of the buttons beside it.
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          l10n.aboutComingSoon,
                          style: theme.textTheme.labelSmall,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A link to the App Store or TestFlight.
class _StoreLink extends StatelessWidget {
  const _StoreLink({
    required this.app,
    required this.label,
    required this.uri,
    required this.filled,
  });

  final ShowcaseApp app;
  final String label;
  final Uri uri;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final style = ButtonStyle(
      visualDensity: VisualDensity.compact,
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 10),
      ),
      textStyle: WidgetStatePropertyAll(Theme.of(context).textTheme.labelSmall),
    );
    void open() => launchUrl(uri, mode: LaunchMode.externalApplication);
    // The label names the app, so a screen reader does not hear "App Store"
    // nineteen times; the button keeps its own focus and tap semantics.
    final text = Text(
      label,
      semanticsLabel: l10n.aboutAppLink(app.name, label),
    );
    return filled
        ? FilledButton(onPressed: open, style: style, child: text)
        : FilledButton.tonal(onPressed: open, style: style, child: text);
  }
}
