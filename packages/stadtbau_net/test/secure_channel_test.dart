// SPDX-License-Identifier: AGPL-3.0-or-later
// T-606: what the relay can and cannot do to a game. Each property is checked
// by a relay in the middle that misbehaves in exactly one way.
import 'dart:async';
import 'dart:convert';

import 'package:stadtbau_net/stadtbau_net.dart';
import 'package:test/test.dart';

/// Waits for [condition], since sealing is asynchronous.
Future<void> until(bool Function() condition) async {
  for (var i = 0; i < 400 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  expect(condition(), isTrue, reason: 'condition never held');
}

/// A relay between a guest and a host that forwards frames through [alter],
/// which may change, drop (return null) or duplicate them.
class Middle {
  Middle({List<String> Function(String frame, int index)? toHost}) {
    final (guestEnd, a) = InMemoryTransport.pair();
    final (b, hostEnd) = InMemoryTransport.pair();
    guest = guestEnd;
    host = hostEnd;
    var index = 0;
    a.incoming.listen((frame) {
      final out = toHost == null ? [frame] : toHost(frame, index);
      index++;
      out.forEach(b.send);
      seen.add(frame);
    }, onDone: b.close);
    b.incoming.listen(a.send, onDone: a.close);
  }

  late final Transport guest;
  late final Transport host;
  final seen = <String>[];
}

void main() {
  final secret = newRelaySecret();

  Future<(SecureChannel, SecureChannel)> open(
    Middle m, {
    String? hostSecret,
    Set<String>? seen,
  }) async {
    final hosting = SecureChannel.host(
      m.host,
      hostSecret ?? secret,
      seenSalts: seen ?? {},
    );
    final guest = await SecureChannel.guest(m.guest, secret);
    return (guest, await hosting);
  }

  test('messages arrive intact and in order, both ways', () async {
    final m = Middle();
    final (guest, host) = await open(m);
    final atHost = <String>[], atGuest = <String>[];
    host.incoming.listen(atHost.add);
    guest.incoming.listen(atGuest.add);
    for (var i = 0; i < 20; i++) {
      guest.send('g$i');
      host.send('h$i');
    }
    await until(() => atHost.length == 20 && atGuest.length == 20);
    expect(atHost, [for (var i = 0; i < 20; i++) 'g$i']);
    expect(atGuest, [for (var i = 0; i < 20; i++) 'h$i']);
  });

  test('the relay sees neither the secret nor the messages', () async {
    final m = Middle();
    final (guest, host) = await open(m);
    final atHost = <String>[];
    host.incoming.listen(atHost.add);
    guest.send('{"type":"hello","name":"Ada"}');
    await until(() => atHost.isNotEmpty);
    final wire = m.seen.join('\n');
    expect(wire, isNot(contains('Ada')));
    expect(wire, isNot(contains(secret)));
    expect(wire, isNot(contains('hello')));
  });

  test('a guest holding another secret cannot open the channel', () async {
    final m = Middle();
    final (guest, host) = await open(m, hostSecret: newRelaySecret());
    final atHost = <String>[];
    host.incoming.listen(atHost.add);
    guest.send('move');
    await until(() => host.isClosed);
    expect(atHost, isEmpty);
  });

  test('an altered frame closes the channel instead of delivering', () async {
    final m = Middle(
      toHost: (frame, i) {
        if (i != 2) return [frame];
        // Flip one character of the sealed payload.
        final c = frame.codeUnitAt(frame.length - 3);
        return [
          frame.substring(0, frame.length - 3) +
              String.fromCharCode(c == 0x41 ? 0x42 : 0x41) +
              frame.substring(frame.length - 2),
        ];
      },
    );
    final (guest, host) = await open(m);
    final atHost = <String>[];
    host.incoming.listen(atHost.add);
    guest
      ..send('first')
      ..send('second')
      ..send('third');
    await until(() => host.isClosed);
    expect(atHost, ['first']);
  });

  test('a replayed frame closes the channel', () async {
    final m = Middle(toHost: (frame, i) => i == 1 ? [frame, frame] : [frame]);
    final (guest, host) = await open(m);
    final atHost = <String>[];
    host.incoming.listen(atHost.add);
    guest
      ..send('once')
      ..send('later');
    await until(() => host.isClosed);
    expect(atHost, ['once']);
  });

  test('a dropped frame closes the channel rather than skip a move', () async {
    final m = Middle(toHost: (frame, i) => i == 1 ? [] : [frame]);
    final (guest, host) = await open(m);
    final atHost = <String>[];
    host.incoming.listen(atHost.add);
    guest
      ..send('dropped')
      ..send('after');
    await until(() => host.isClosed);
    expect(atHost, isEmpty);
  });

  test('a recorded connection cannot be replayed into the room', () async {
    final seen = <String>{};
    final first = Middle();
    final (guest, host) = await open(first, seen: seen);
    final atHost = <String>[];
    host.incoming.listen(atHost.add);
    guest.send('join');
    await until(() => atHost.isNotEmpty);

    // Play the recording back on a fresh channel to the same host room.
    final (replayer, hostEnd) = InMemoryTransport.pair();
    final hosting = SecureChannel.host(hostEnd, secret, seenSalts: seen);
    first.seen.forEach(replayer.send);
    await expectLater(hosting, throwsA(isA<SecureChannelException>()));
  });

  test('a first sealed frame racing the key derivation is not lost', () async {
    // The guest sends straight after its salt; the host is still deriving.
    final (guestEnd, hostEnd) = InMemoryTransport.pair();
    final hosting = SecureChannel.host(hostEnd, secret, seenSalts: {});
    final guest = await SecureChannel.guest(guestEnd, secret);
    guest.send('immediately');
    final host = await hosting;
    final atHost = <String>[];
    host.incoming.listen(atHost.add);
    await until(() => atHost.isNotEmpty);
    expect(atHost, ['immediately']);
  });

  group('relay codes', () {
    test('round-trip, and keep the secret away from the relay', () {
      final code = RelayCode.create(Uri.parse('wss://relay.example.org'));
      final parsed = RelayCode.tryParse(code.toString())!;
      expect(parsed.secret, code.secret);
      expect(parsed.joinUri.toString(), isNot(contains(code.secret)));
      expect(parsed.hostUri.path, '/v1/host/${code.roomId}');
      expect(parsed.joinUri.path, '/v1/join/${code.roomId}');
    });

    test('keep a relay served under a path', () {
      final code = RelayCode(
        Uri.parse('wss://example.org/hectopolis'),
        newRelaySecret(),
      );
      final parsed = RelayCode.tryParse(code.toString())!;
      expect(parsed.joinUri.path, '/hectopolis/v1/join/${code.roomId}');
    });

    test('are not mistaken for LAN codes, or the other way round', () {
      expect(
        RelayCode.tryParse('192.168.1.5:41234/${newRelaySecret()}'),
        isNull,
      );
      final relay = RelayCode.create(Uri.parse('wss://relay.example.org'));
      expect(() => parseRoomCode(relay.toString()), throwsFormatException);
    });

    test('refuse plain ws except on the device itself', () {
      final s = newRelaySecret();
      expect(RelayCode.tryParse('ws://relay.example.org/r/$s'), isNull);
      expect(RelayCode.tryParse('ws://127.0.0.1:8080/r/$s'), isNotNull);
      expect(RelayCode.parseRelayAddress('relay.example.org')!.scheme, 'wss');
      expect(RelayCode.parseRelayAddress('ws://relay.example.org'), isNull);
    });
  });

  group('host link', () {
    test('splits one relay connection into one channel per guest', () async {
      final (relaySide, hostSide) = InMemoryTransport.pair();
      final link = RelayHostLink(hostSide);
      final channels = <Transport>[];
      link.channels.listen(channels.add);
      final atHost = <int, List<String>>{};
      relaySide.send(jsonEncode({'op': 'open', 'ch': 1}));
      relaySide.send(jsonEncode({'op': 'open', 'ch': 2}));
      await until(() => channels.length == 2);
      for (final (i, c) in channels.indexed) {
        atHost[i] = [];
        c.incoming.listen(atHost[i]!.add);
      }
      relaySide.send(jsonEncode({'op': 'data', 'ch': 2, 'm': 'to two'}));
      relaySide.send(jsonEncode({'op': 'data', 'ch': 1, 'm': 'to one'}));
      final fromHost = <Map<String, Object?>>[];
      relaySide.incoming.listen(
        (f) => fromHost.add(jsonDecode(f) as Map<String, Object?>),
      );
      channels[0].send('reply');
      await until(() => atHost[0]!.isNotEmpty && atHost[1]!.isNotEmpty);
      await until(() => fromHost.isNotEmpty);
      expect(atHost[0], ['to one']);
      expect(atHost[1], ['to two']);
      expect(fromHost.single, {'op': 'data', 'ch': 1, 'm': 'reply'});

      relaySide.send(jsonEncode({'op': 'close', 'ch': 2}));
      await until(() => channels[1].isClosed);
      expect(channels[0].isClosed, isFalse);
      await relaySide.close();
      await until(() => channels[0].isClosed);
    });
  });
}
