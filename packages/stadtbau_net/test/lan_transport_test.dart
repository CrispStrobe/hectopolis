// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';
import 'dart:io';

import 'package:stadtbau_net/stadtbau_net.dart';
import 'package:stadtbau_sim/stadtbau_sim.dart';
import 'package:test/test.dart';

void main() {
  test('network resume tokens are random 128-bit values', () {
    final next = SessionHost.secureTokenFactory();
    final values = {for (var i = 0; i < 20; i++) next()};
    expect(values, hasLength(20));
    expect(
      values.every((value) => RegExp(r'^[0-9a-f]{32}$').hasMatch(value)),
      isTrue,
    );
  });

  test('room codes are strict and round-trip', () {
    final uri = parseRoomCode('192.168.1.7:43121/abc123');
    expect(uri, Uri.parse('ws://192.168.1.7:43121/abc123'));
    expect(
      parseRoomCode('wss://host.example:443/room'),
      Uri.parse('wss://host.example:443/room'),
    );
    for (final bad in ['', 'host', 'http://host:80/room', 'host:80/a/b']) {
      expect(() => parseRoomCode(bad), throwsFormatException, reason: bad);
    }
  });

  test('a LAN WebSocket preserves ordered text messages', () async {
    if (!lanHostingSupported) return;
    final server = await startLanServer();
    addTearDown(server.close);

    final accepted = server.connections.first;
    final client = await WebSocketTransport.connect(server.uriFor('127.0.0.1'));
    addTearDown(client.close);
    final host = await accepted;
    addTearDown(host.close);

    final hostMessages = <String>[];
    final clientMessages = <String>[];
    final hostSub = host.incoming.listen(hostMessages.add);
    final clientSub = client.incoming.listen(clientMessages.add);
    addTearDown(hostSub.cancel);
    addTearDown(clientSub.cancel);

    client.send('one');
    client.send('two');
    host.send('answer');
    await _until(() => hostMessages.length == 2 && clientMessages.length == 1);

    expect(hostMessages, ['one', 'two']);
    expect(clientMessages, ['answer']);
  });

  test('the room secret rejects an unrelated WebSocket path', () async {
    if (!lanHostingSupported) return;
    final server = await startLanServer();
    addTearDown(server.close);
    final wrong = Uri.parse('ws://127.0.0.1:${server.port}/not-the-room');
    expect(WebSocketTransport.connect(wrong), throwsA(anything));
  });

  test(
    'a stalled handshake times out instead of hanging the join UI',
    () async {
      if (!lanHostingSupported) return;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((_) {
        // Deliberately never answer the upgrade request.
      });
      addTearDown(() => server.close(force: true));

      final uri = Uri.parse('ws://127.0.0.1:${server.port}/stalled');
      await expectLater(
        WebSocketTransport.connect(
          uri,
          timeout: const Duration(milliseconds: 50),
        ),
        throwsA(isA<TimeoutException>()),
      );
    },
  );

  test('a real socket carries a whole authoritative session', () async {
    if (!lanHostingSupported) return;
    final server = await startLanServer();
    final host = SessionHost(
      simulation: Simulation.sandbox(width: 8, height: 8),
      hostName: 'Ada',
      tokenFactory: SessionHost.secureTokenFactory(),
    );
    final accepts = server.connections.listen(host.accept);
    final wire = await WebSocketTransport.connect(server.uriFor('127.0.0.1'));
    final client = SessionClient(transport: wire, playerName: 'Linus');
    addTearDown(() async {
      await client.dispose();
      await host.dispose();
      await accepts.cancel();
      await server.close();
    });

    await _until(() => client.phase == SessionPhase.lobby);
    expect(client.resumeToken, matches(RegExp(r'^[0-9a-f]{32}$')));
    client.request(const PlaceTile(2, 2, TileType.park));
    await _until(() => host.simulation.state.tileAt(2, 2) == TileType.park);
    await _until(
      () => client.simulation?.state.hash() == host.simulation.state.hash(),
    );
    expect(client.resyncCount, 0);
  });
}

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition not reached');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
