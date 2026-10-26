// SPDX-License-Identifier: AGPL-3.0-or-later
// T-606: the relay over real sockets on this machine.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:stadtbau_relay/stadtbau_relay.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const room = '0123456789abcdef0123456789abcdef';

/// A connection with its frames collected, and the close code once closed.
class Peer {
  Peer(this.socket) {
    socket.stream.listen(
      (m) => frames.add(m as String),
      onDone: () => done.complete(socket.closeCode),
    );
  }
  final WebSocketChannel socket;
  final frames = <String>[];
  final done = Completer<int?>();
  List<Map<String, Object?>> get envelopes => [
    for (final f in frames) jsonDecode(f) as Map<String, Object?>,
  ];
}

Future<void> until(bool Function() condition) async {
  for (var i = 0; i < 500 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 4));
  }
  expect(condition(), isTrue, reason: 'condition never held');
}

void main() {
  late RelayServer server;
  final open = <WebSocketChannel>[];

  Future<Peer> connect(String path) async {
    final socket = IOWebSocketChannel.connect(
      Uri.parse('ws://127.0.0.1:${server.port}/$path'),
    );
    await socket.ready;
    open.add(socket);
    return Peer(socket);
  }

  setUp(() async {
    server = await RelayServer.start(
      port: 0,
      limits: const RelayLimits(maxGuestsPerRoom: 2, maxFrameChars: 1000),
    );
  });
  tearDown(() async {
    for (final s in open) {
      await s.sink.close();
    }
    open.clear();
    await server.close();
  });

  test('answers a health check and refuses other paths', () async {
    final client = HttpClient();
    addTearDown(client.close);
    Future<int> status(String path) async {
      final req = await client.get('127.0.0.1', server.port, path);
      return (await req.close()).statusCode;
    }

    expect(await status('/healthz'), 200);
    expect(await status('/'), 404);
    expect(await status('/v1/host/not-a-room-id'), 404);
    expect(await status('/v1/watch/$room'), 404);
  });

  test('pairs guests with their host by room and channel', () async {
    final host = await connect('v1/host/$room');
    final a = await connect('v1/join/$room');
    final b = await connect('v1/join/$room');
    await until(() => host.frames.length == 2);
    final channels = [for (final e in host.envelopes) e['ch']! as int];
    expect(host.envelopes.map((e) => e['op']), ['open', 'open']);

    a.socket.sink.add('from a');
    b.socket.sink.add('from b');
    await until(() => host.frames.length == 4);
    expect(host.envelopes.sublist(2), [
      {'op': 'data', 'ch': channels[0], 'm': 'from a'},
      {'op': 'data', 'ch': channels[1], 'm': 'from b'},
    ]);

    host.socket.sink.add(
      jsonEncode({'op': 'data', 'ch': channels[1], 'm': 'to b'}),
    );
    await until(() => b.frames.isNotEmpty);
    expect(b.frames, ['to b']);
    expect(a.frames, isEmpty);
  });

  test('a room has one host', () async {
    await connect('v1/host/$room');
    final second = await connect('v1/host/$room');
    expect(await second.done.future, RelayCloseCode.roomTaken);
  });

  test('a guest cannot join a room nobody hosts', () async {
    final guest = await connect('v1/join/$room');
    expect(await guest.done.future, RelayCloseCode.noSuchRoom);
  });

  test('a room takes no more than its guests', () async {
    await connect('v1/host/$room');
    await connect('v1/join/$room');
    await connect('v1/join/$room');
    final third = await connect('v1/join/$room');
    expect(await third.done.future, RelayCloseCode.roomFull);
  });

  test('the room ends with its host', () async {
    final host = await connect('v1/host/$room');
    final guest = await connect('v1/join/$room');
    await until(() => host.frames.isNotEmpty);
    await host.socket.sink.close();
    await guest.done.future;
    expect(server.rooms.roomCount, 0);
  });

  test('a guest leaving tells the host', () async {
    final host = await connect('v1/host/$room');
    final guest = await connect('v1/join/$room');
    await until(() => host.frames.length == 1);
    await guest.socket.sink.close();
    await until(() => host.frames.length == 2);
    expect(host.envelopes.last['op'], 'close');
  });

  test('a host can close one guest', () async {
    final host = await connect('v1/host/$room');
    final guest = await connect('v1/join/$room');
    await until(() => host.frames.isNotEmpty);
    final ch = host.envelopes.single['ch'];
    host.socket.sink.add(jsonEncode({'op': 'close', 'ch': ch}));
    await guest.done.future;
    expect(server.rooms.guestCount, 0);
  });

  test('an oversized frame closes the connection', () async {
    await connect('v1/host/$room');
    final guest = await connect('v1/join/$room');
    guest.socket.sink.add('x' * 1001);
    expect(await guest.done.future, RelayCloseCode.frameTooLarge);
  });
}
