// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stadtbau/game/game_controller.dart';
import 'package:stadtbau/game/session_controller.dart';
import 'package:stadtbau/main.dart';
import 'package:stadtbau_net/stadtbau_net.dart';
import 'package:stadtbau_sim/stadtbau_sim.dart';

void main() {
  testWidgets('the level screen exposes manual local co-op setup', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'stadtbau.onboarding.v1': true});
    await tester.pumpWidget(const HectopolisApp());
    await tester.pumpAndSettle();

    expect(find.text('Build together'), findsOneWidget);
    await tester.tap(find.text('Build together'));
    await tester.pumpAndSettle();

    expect(find.text('Your name'), findsOneWidget);
    expect(find.text('Room code or address'), findsOneWidget);
    expect(find.text('Host a game'), findsOneWidget);
    expect(find.text('Join a game'), findsOneWidget);
    expect(
      find.textContaining('Nothing goes to us or to a third party'),
      findsOneWidget,
    );
  });

  test(
    'the game controller obeys the shared turn, district and stock',
    () async {
      final host = SessionController.host(
        simulation: Simulation.sandbox(width: 8, height: 8),
        playerName: 'Ada',
      );
      final (hostWire, guestWire) = InMemoryTransport.pair();
      host.accept(hostWire);
      final guest = SessionController.join(
        transport: guestWire,
        playerName: 'Linus',
      );
      final game = GameController(size: 8);
      addTearDown(() async {
        game.dispose();
        await guest.close();
        await host.close();
      });
      await InMemoryTransport.settle();

      host.splitIntoStrips();
      guest.setReady(ready: true);
      host.start();
      await InMemoryTransport.settle();
      game.startCooperative(guest);

      expect(game.cooperative, isTrue);
      expect(game.isMyTurn, isFalse); // host opens the round
      expect(game.place(5, 1, TileType.park), isFalse);

      host.endTurn();
      await InMemoryTransport.settle();
      expect(game.isMyTurn, isTrue);
      expect(game.myDistrict?.contains(5, 1), isTrue);
      expect(game.place(1, 1, TileType.park), isFalse); // host's district
      expect(game.place(5, 1, TileType.park), isTrue);
      await InMemoryTransport.settle();

      expect(host.simulation!.state.tileAt(5, 1), TileType.park);
      expect(guest.simulation!.state.hash(), host.simulation!.state.hash());
      expect(
        game.remaining(TileType.park),
        isNull,
      ); // sandbox stock is unlimited

      await guestWire.close();
      await InMemoryTransport.settle();
      expect(game.cooperativeDisconnected, isTrue);
      final (newHostWire, newGuestWire) = InMemoryTransport.pair();
      host.accept(newHostWire);
      await guest.reconnect(newGuestWire);
      await InMemoryTransport.settle();
      expect(game.cooperativeDisconnected, isFalse);
      expect(guest.resumeToken, isNotNull);
      expect(guest.simulation!.state.hash(), host.simulation!.state.hash());
    },
  );
}
