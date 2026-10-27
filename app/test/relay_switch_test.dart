// SPDX-License-Identifier: AGPL-3.0-or-later
// T-606: the build switch that leaves relay play out (build_features.dart).
// A compile-time constant cannot be flipped inside one run, so CI runs this
// file twice: as built, and with --dart-define=HECTOPOLIS_RELAY=false.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stadtbau/game/build_features.dart';
import 'package:stadtbau/game/game_controller.dart';
import 'package:stadtbau/game/lan_session.dart';
import 'package:stadtbau/l10n/generated/app_localizations.dart';
import 'package:stadtbau/ui/coop_setup_screen.dart';
import 'package:stadtbau_net/stadtbau_net.dart';

void main() {
  testWidgets('the co-op screen offers a relay exactly when the build can', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final game = GameController(size: 8);
    addTearDown(game.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: CoopSetupScreen(gameController: game, onLocaleToggle: () {}),
      ),
    );
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(
      find.text(l10n.coopHostRelay),
      relayEnabled ? findsOneWidget : findsNothing,
    );
    expect(
      find.text(l10n.coopRelayAddress),
      relayEnabled ? findsOneWidget : findsNothing,
    );
    // Without relays the privacy line says what it said before they existed.
    expect(
      find.text(l10n.coopDirectPrivacy),
      relayEnabled ? findsNothing : findsOneWidget,
    );
  });

  test('a build without relays refuses a relay code', () async {
    if (relayEnabled) return; // Covered by relay_session_test.dart.
    final code = RelayCode.create(Uri.parse('wss://relay.example.org'));
    await expectLater(
      LanSession.join(playerName: 'Ada', roomCode: code.toString()),
      throwsFormatException,
    );
    await expectLater(
      LanSession.hostViaRelay(
        playerName: 'Ada',
        relay: Uri.parse('wss://relay.example.org'),
      ),
      throwsUnsupportedError,
    );
  });
}
