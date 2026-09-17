// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/custom_licenses.dart';
import 'doc_links.dart';

/// About / legal screen, laid out like our sibling apps: app header with
/// version, provider (Impressum), contact, privacy, disclaimer, license
/// (AGPL plus the app-store exception), data sources, and the aggregated
/// open-source license list Flutter collects via `LicenseRegistry`.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  // Provider identification (Impressum), the same developer as our sibling
  // apps. Not localised: an address is an address in every language.
  static const provider = 'Christian Ströbele\nNikolausstr. 5\n70190 Stuttgart\nDeutschland / Germany';
  static const email = 'postmaster@crispstro.be';
  static const phone = '+49 176 6421 8601';
  static const phoneUri = 'tel:+4917664218601';
  static const repoUrl = repositoryUrl;
  static const agplUrl = 'https://www.gnu.org/licenses/agpl-3.0.html';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.aboutTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const _AppHeader(),
              const SizedBox(height: 12),
              _SectionCard(icon: Icons.business, label: l10n.aboutProvider, child: const Text(provider)),
              _SectionCard(
                icon: Icons.alternate_email,
                label: l10n.aboutContact,
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _LinkText(text: email, uri: 'mailto:$email'),
                    SizedBox(height: 4),
                    _LinkText(text: phone, uri: phoneUri),
                    SizedBox(height: 4),
                    _LinkText(text: repoUrl, uri: repoUrl),
                  ],
                ),
              ),
              _SectionCard(icon: Icons.privacy_tip_outlined, label: l10n.aboutPrivacy, child: Text(l10n.aboutPrivacyText)),
              _SectionCard(icon: Icons.gavel, label: l10n.aboutDisclaimer, child: Text(l10n.aboutDisclaimerText)),
              _SectionCard(
                icon: Icons.copyright,
                label: l10n.aboutLicense,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.aboutLicenseText),
                    const SizedBox(height: 8),
                    Text(l10n.aboutExceptionText),
                    const SizedBox(height: 8),
                    const _LinkText(text: agplUrl, uri: agplUrl),
                  ],
                ),
              ),
              _SectionCard(
                icon: Icons.menu_book_outlined,
                label: l10n.aboutDataSources,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.aboutDataSourcesText),
                    const SizedBox(height: 8),
                    for (final s in dataSources)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text('• ${s.title} — ${s.license}', style: Theme.of(context).textTheme.bodySmall),
                      ),
                    const SizedBox(height: 8),
                    const _LinkText(text: modelDocsUrl, uri: modelDocsUrl),
                    const SizedBox(height: 4),
                    const _LinkText(text: sourcesDocUrl, uri: sourcesDocUrl),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              OutlinedButton.icon(
                icon: const Icon(Icons.description_outlined),
                label: Text(l10n.aboutOpenSourceLicenses),
                onPressed: () => _showLicenses(context, l10n),
              ),
              const SizedBox(height: 24),
              Text(
                l10n.appLegalese(DateTime.now().year),
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showLicenses(BuildContext context, AppLocalizations l10n) async {
    ensureCustomLicensesRegistered();
    final info = await PackageInfo.fromPlatform();
    if (!context.mounted) return;
    showLicensePage(
      context: context,
      applicationName: l10n.appTitle,
      applicationVersion: '${info.version}+${info.buildNumber}',
      applicationLegalese: l10n.appLegalese(DateTime.now().year),
    );
  }
}

/// App icon + name + version + tagline, in a card.
class _AppHeader extends StatelessWidget {
  const _AppHeader();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.location_city, size: 28, color: scheme.onPrimaryContainer),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.appTitle, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 4),
                  FutureBuilder<PackageInfo>(
                    future: PackageInfo.fromPlatform(),
                    builder: (context, snap) => Text(
                      snap.hasData ? l10n.aboutVersionLabel('${snap.data!.version}+${snap.data!.buildNumber}') : '…',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(l10n.aboutTagline, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A labelled card section with a leading icon.
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.icon, required this.label, required this.child});

  final IconData icon;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(label, style: Theme.of(context).textTheme.titleSmall)),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

/// Tappable text that launches [uri] (mailto, tel or https).
class _LinkText extends StatelessWidget {
  const _LinkText({required this.text, required this.uri});

  final String text;
  final String uri;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final parsed = Uri.parse(uri);
        if (await canLaunchUrl(parsed)) await launchUrl(parsed);
      },
      child: Text(
        text,
        style: TextStyle(color: Theme.of(context).colorScheme.primary, decoration: TextDecoration.underline),
      ),
    );
  }
}
