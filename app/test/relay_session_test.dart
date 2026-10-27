// SPDX-License-Identifier: AGPL-3.0-or-later
// T-606: the app's own session owner, hosting and joining through a relay.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stadtbau/game/game_controller.dart';
import 'package:stadtbau/game/lan_session.dart';
import 'package:stadtbau/l10n/generated/app_localizations.dart';
import 'package:stadtbau/ui/coop_setup_screen.dart';
import 'package:stadtbau_net/stadtbau_net.dart';
import 'package:stadtbau_relay/stadtbau_relay.dart';

Future<void> until(bool Function() condition) async {
  for (var i = 0; i < 1000 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(condition(), isTrue, reason: 'condition never held');
}

void main() {
  test('a host and a guest meet through a relay with the shown code', () async {
    final relay = await RelayServer.start(port: 0);
    addTearDown(relay.close);
    final host = await LanSession.hostViaRelay(
      playerName: 'Ada',
      relay: Uri.parse('ws://127.0.0.1:${relay.port}'),
    );
    addTearDown(host.close);

    final code = host.roomCodes.single;
    expect(RelayCode.tryParse(code), isNotNull, reason: code);
    final guest = await LanSession.join(playerName: 'Linus', roomCode: code);
    addTearDown(guest.close);

    await until(() => host.controller.players.length == 2);
    await until(() => guest.controller.players.length == 2);
    expect(guest.canReconnect, isTrue);
  });

  testWidgets('an unusable relay address says so instead of connecting', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    // Tall enough that the whole form is on screen.
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
    final button = find.widgetWithText(OutlinedButton, l10n.coopHostRelay);
    await tester.enterText(
      find.widgetWithText(TextField, l10n.coopPlayerName),
      'Ada',
    );
    await tester.pump();
    expect(tester.widget<OutlinedButton>(button).onPressed, isNull);

    // Plain ws:// to a remote host is refused: the game only uses wss://.
    await tester.enterText(
      find.widgetWithText(TextField, l10n.coopRelayAddress),
      'ws://relay.example.org',
    );
    await tester.pump();
    await tester.tap(button);
    await tester.pump();
    expect(find.text(l10n.coopRelayAddressInvalid), findsOneWidget);
  });
}
