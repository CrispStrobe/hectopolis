// SPDX-License-Identifier: AGPL-3.0-or-later
// T-606: a real game session through a real relay, over sockets on this
// machine, with every frame sealed end to end.
import 'dart:async';

import 'package:stadtbau_net/stadtbau_net.dart';
import 'package:stadtbau_relay/stadtbau_relay.dart';
import 'package:stadtbau_sim/stadtbau_sim.dart';
import 'package:test/test.dart';

Future<void> until(bool Function() condition) async {
  for (var i = 0; i < 1000 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(condition(), isTrue, reason: 'condition never held');
}

void main() {
  late RelayServer relay;
  late RelayCode code;
  final cleanup = <Future<void> Function()>[];

  setUp(() async {
    relay = await RelayServer.start(port: 0);
    code = RelayCode(
      Uri.parse('ws://127.0.0.1:${relay.port}'),
      newRelaySecret(),
    );
  });
  tearDown(() async {
    for (final close in cleanup.reversed) {
      await close();
    }
    cleanup.clear();
    await relay.close();
  });

  Future<SessionHost> host() async {
    final session = SessionHost(
      simulation: Simulation(
        state: WorldState.empty(width: 12, height: 12, budgetKEur: 100000),
      ),
      hostName: 'Host',
    );
    final socket = await WebSocketTransport.connect(code.hostUri);
    final link = RelayHostLink(socket);
    final guests = secureGuests(link, code.secret).listen(session.accept);
    cleanup.add(() async {
      await guests.cancel();
      await link.close();
    });
    // Wait until the relay has registered the room.
    await until(() => relay.rooms.roomCount == 1);
    return session;
  }

  Future<SessionClient> guest(String name, {String? secret}) async {
    final socket = await WebSocketTransport.connect(code.joinUri);
    final channel = await SecureChannel.guest(socket, secret ?? code.secret);
    final client = SessionClient(transport: channel, playerName: name);
    cleanup.add(channel.close);
    return client;
  }

  test('two guests join through the relay and see the same world', () async {
    final h = await host();
    final a = await guest('Ada');
    final b = await guest('Ben');
    await until(() => a.simulation != null && b.simulation != null);
    await until(() => h.players.length == 3);
    expect(a.simulation!.state.hash(), h.simulation.state.hash());
    expect(b.simulation!.state.hash(), h.simulation.state.hash());

    a.request(const PlaceTile(3, 3, TileType.park));
    await until(
      () =>
          b.simulation!.state.tileAt(3, 3) == TileType.park &&
          h.simulation.state.tileAt(3, 3) == TileType.park,
    );
    expect(b.simulation!.state.hash(), h.simulation.state.hash());
  });

  test('a guest without the secret is turned away; the game goes on', () async {
    final h = await host();
    final a = await guest('Ada');
    await until(() => a.simulation != null);
    // Knows the room id (the relay does too) but not the secret.
    final intruder = await guest('Mallory', secret: newRelaySecret());
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(intruder.simulation, isNull);
    expect(h.players.map((p) => p.name), isNot(contains('Mallory')));

    a.request(const PlaceTile(1, 1, TileType.forest));
    await until(() => h.simulation.state.tileAt(1, 1) == TileType.forest);
  });
}
