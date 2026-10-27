// SPDX-License-Identifier: AGPL-3.0-or-later
// T-606: the app's own session owner, hosting and joining through a relay.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stadtbau/game/game_controller.dart';
import 'package:stadtbau/game/lan_session.dart';
import 'package:stadtbau/game/save_store.dart';
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

  Future<AppLocalizations> pumpSetup(
    WidgetTester tester,
    GameController game,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: CoopSetupScreen(
          gameController: game,
          onLocaleToggle: () {},
          store: SaveStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return AppLocalizations.delegate.load(const Locale('en'));
  }

  testWidgets('a remembered relay address is filled in, and can be forgotten', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'stadtbau.relay.v1': 'relay.example.org',
    });
    final game = GameController(size: 8);
    addTearDown(game.dispose);
    final l10n = await pumpSetup(tester, game);
    // The field's own text: the hint shows the same example host name.
    String typed() => tester
        .widget<TextField>(
          find.widgetWithText(TextField, l10n.coopRelayAddress),
        )
        .controller!
        .text;
    expect(typed(), 'relay.example.org');

    await tester.tap(find.byTooltip(l10n.coopRelayForget));
    await tester.pumpAndSettle();
    expect(typed(), isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('stadtbau.relay.v1'), isNull);
  });

  testWidgets('only an address that worked is remembered', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final game = GameController(size: 8);
    addTearDown(game.dispose);
    final l10n = await pumpSetup(tester, game);
    await tester.enterText(
      find.widgetWithText(TextField, l10n.coopPlayerName),
      'Ada',
    );

    // Refused before connecting: nothing stored.
    await tester.enterText(
      find.widgetWithText(TextField, l10n.coopRelayAddress),
      'ws://relay.example.org',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(OutlinedButton, l10n.coopHostRelay));
    await tester.pump();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('stadtbau.relay.v1'), isNull);

    // A real relay: hosting through it works, and the address is kept.
    final relay = (await tester.runAsync(() => RelayServer.start(port: 0)))!;
    final address = 'ws://127.0.0.1:${relay.port}';
    await tester.enterText(
      find.widgetWithText(TextField, l10n.coopRelayAddress),
      address,
    );
    await tester.pump();
    // Real sockets: tap and wait outside the test's faked clock.
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(OutlinedButton, l10n.coopHostRelay));
      for (
        var i = 0;
        i < 200 && prefs.getString('stadtbau.relay.v1') == null;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    expect(prefs.getString('stadtbau.relay.v1'), address);

    // Leave the lobby, which closes the session, then stop the relay.
    await tester.pump();
    Navigator.of(tester.element(find.byType(Scaffold).last)).pop();
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await relay.close();
    });
  });
}
