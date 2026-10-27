// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'game/game_controller.dart';
import 'game/save_store.dart';
import 'l10n/generated/app_localizations.dart';
import 'ui/level_select_screen.dart';

void main() {
  runApp(const HectopolisApp());
}

class HectopolisApp extends StatefulWidget {
  const HectopolisApp({super.key});

  @override
  State<HectopolisApp> createState() => _HectopolisAppState();
}

class _HectopolisAppState extends State<HectopolisApp> {
  final SaveStore _store = SaveStore();
  late final GameController _controller = GameController(store: _store);
  Locale? _locale;

  void _toggleLocale() {
    setState(() {
      final current = _locale ?? WidgetsBinding.instance.platformDispatcher.locale;
      _locale = current.languageCode == 'de' ? const Locale('en') : const Locale('de');
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      locale: _locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF2E7D32), useMaterial3: true, fontFamily: _webFontFamily),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF2E7D32),
        brightness: Brightness.dark,
        useMaterial3: true,
        fontFamily: _webFontFamily,
      ),
      home: LevelSelectScreen(controller: _controller, store: _store, onLocaleToggle: _toggleLocale),
    );
  }
}

/// The bundled Roboto, on the web; the platform's own font elsewhere.
///
/// Material picks its typography by platform, and on the web that is the
/// platform the *browser* runs on: Apple's system font on a Mac or an iPhone,
/// Segoe UI on Windows. A web build has neither, so CanvasKit fetched a
/// fallback for every character from U+00A0 up -- every €, ·, × and umlaut --
/// from fonts.gstatic.com, the request T-702 promises never happens. Only
/// Linux and Android browsers got Roboto, which is why the origin check, run
/// in Chrome on Linux, never saw it. Native builds have their system fonts and
/// keep them.
const String? _webFontFamily = kIsWeb ? 'Roboto' : null;
