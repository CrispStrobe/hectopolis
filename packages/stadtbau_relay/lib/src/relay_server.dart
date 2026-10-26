// SPDX-License-Identifier: AGPL-3.0-or-later
// T-606: the relay. It pairs a hosting device with its guests by room id and
// forwards their frames; it knows nothing about the game. Everything a host
// and its guests say to each other is sealed with the room secret
// (stadtbau_net's SecureChannel), so the relay forwards text it cannot read
// and cannot alter without the alteration being detected.
//
// What it does see, and therefore what someone running one learns: that a
// room exists (by an id derived from its secret by a one-way hash), how many
// guests it has, when frames pass and how large they are, and the IP addresses
// connecting to it. It logs none of that beyond aggregate counts.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Bounds on what one relay will carry. The defaults suit a club or a school
/// running its own relay; raise them deliberately.
class RelayLimits {
  const RelayLimits({
    this.maxRooms = 200,
    this.maxGuestsPerRoom = 6,
    this.maxFrameChars = 4 * 1024 * 1024,
    this.maxFramesPerMinute = 6000,
    this.pingInterval = const Duration(seconds: 30),
  });

  final int maxRooms;

  /// Co-op takes four players, so three guests; the rest is headroom for a
  /// guest reconnecting before the relay has noticed the old connection drop.
  final int maxGuestsPerRoom;

  /// A full snapshot of the largest map is well under a megabyte, sealed.
  final int maxFrameChars;
  final int maxFramesPerMinute;
  final Duration pingInterval;
}

/// WebSocket close codes the relay sends, so a client can say why.
abstract final class RelayCloseCode {
  static const roomTaken = 4009;
  static const noSuchRoom = 4004;
  static const roomFull = 4029;
  static const tooBusy = 4003;
  static const tooFast = 4028;
  // 1009 means the same, but it is reserved for the protocol layer: an
  // application may only send 1000 or 3000-4999, and a 1009 arrives as none.
  static const frameTooLarge = 4013;
}

final _roomId = RegExp(r'^[0-9a-f]{32}$');

/// The routing core, separate from the sockets so tests can drive it.
class RelayRooms {
  RelayRooms([this.limits = const RelayLimits()]);

  final RelayLimits limits;
  final _rooms = <String, _Room>{};

  int get roomCount => _rooms.length;
  int get guestCount =>
      _rooms.values.fold(0, (sum, room) => sum + room.guests.length);

  /// A hosting device connects for [roomId].
  void host(String roomId, WebSocketChannel socket) {
    if (_rooms.containsKey(roomId)) {
      unawaited(socket.sink.close(RelayCloseCode.roomTaken, 'room taken'));
      return;
    }
    if (_rooms.length >= limits.maxRooms) {
      unawaited(socket.sink.close(RelayCloseCode.tooBusy, 'relay full'));
      return;
    }
    final room = _Room(_Peer(socket, limits));
    _rooms[roomId] = room;
    room.host.listen(
      (frame) {
        final Object? envelope;
        try {
          envelope = jsonDecode(frame);
        } on FormatException {
          return;
        }
        if (envelope is! Map<String, Object?>) return;
        final ch = envelope['ch'];
        if (ch is! int) return;
        final guest = room.guests[ch];
        if (guest == null) return;
        switch (envelope['op']) {
          case 'data':
            final m = envelope['m'];
            if (m is String) guest.send(m);
          case 'close':
            room.guests.remove(ch);
            guest.close();
        }
      },
      onDone: () {
        // The room ends with its host.
        if (identical(_rooms[roomId], room)) _rooms.remove(roomId);
        // Cleared first: closing a guest runs its own onDone, which would
        // otherwise remove it from the map this loop is walking.
        final guests = room.guests.values.toList();
        room.guests.clear();
        for (final guest in guests) {
          guest.close();
        }
      },
    );
  }

  /// A guest connects to [roomId].
  void join(String roomId, WebSocketChannel socket) {
    final room = _rooms[roomId];
    if (room == null) {
      unawaited(socket.sink.close(RelayCloseCode.noSuchRoom, 'no such room'));
      return;
    }
    if (room.guests.length >= limits.maxGuestsPerRoom) {
      unawaited(socket.sink.close(RelayCloseCode.roomFull, 'room full'));
      return;
    }
    final ch = room.nextChannel++;
    final guest = _Peer(socket, limits);
    room.guests[ch] = guest;
    room.host.send(jsonEncode({'op': 'open', 'ch': ch}));
    guest.listen(
      (frame) =>
          room.host.send(jsonEncode({'op': 'data', 'ch': ch, 'm': frame})),
      onDone: () {
        if (room.guests.remove(ch) != null) {
          room.host.send(jsonEncode({'op': 'close', 'ch': ch}));
        }
      },
    );
  }

  Future<void> closeAll() async {
    for (final room in _rooms.values.toList()) {
      room.host.close();
    }
    _rooms.clear();
  }
}

class _Room {
  _Room(this.host);
  final _Peer host;
  final guests = <int, _Peer>{};
  var nextChannel = 1;
}

/// One connection, with the frame-size and frame-rate limits applied.
class _Peer {
  _Peer(this._socket, this._limits);

  final WebSocketChannel _socket;
  final RelayLimits _limits;
  var _windowStart = DateTime.now();
  var _framesInWindow = 0;
  var _closed = false;

  void listen(
    void Function(String) onFrame, {
    required void Function() onDone,
  }) {
    _socket.stream.listen(
      (Object? message) {
        if (_closed) return;
        if (message is! String) return;
        if (message.length > _limits.maxFrameChars) {
          close(RelayCloseCode.frameTooLarge, 'frame too large');
          return;
        }
        final now = DateTime.now();
        if (now.difference(_windowStart) > const Duration(minutes: 1)) {
          _windowStart = now;
          _framesInWindow = 0;
        }
        if (++_framesInWindow > _limits.maxFramesPerMinute) {
          close(RelayCloseCode.tooFast, 'too many frames');
          return;
        }
        onFrame(message);
      },
      onDone: () {
        _closed = true;
        onDone();
      },
      onError: (Object _) {},
      cancelOnError: false,
    );
  }

  void send(String frame) {
    if (!_closed) _socket.sink.add(frame);
  }

  void close([int? code, String? reason]) {
    if (_closed) return;
    _closed = true;
    unawaited(_socket.sink.close(code, reason));
  }
}

/// The relay as an HTTP server: `/v1/host/<room>` and `/v1/join/<room>` take
/// WebSocket connections, `/healthz` answers a load balancer.
///
/// It speaks plain `ws://`; put it behind a reverse proxy that terminates TLS,
/// because the game only connects to a relay over `wss://`
/// (docs/relay-hosting.md).
class RelayServer {
  RelayServer._(this._server, this.rooms);

  static Future<RelayServer> start({
    Object address = '127.0.0.1',
    int port = 8080,
    RelayLimits limits = const RelayLimits(),
  }) async {
    final rooms = RelayRooms(limits);
    final server = await shelf_io.serve(handler(rooms), address, port);
    return RelayServer._(server, rooms);
  }

  /// The request handler, also usable inside another shelf pipeline.
  static Handler handler(RelayRooms rooms) {
    return (Request request) {
      final segments = request.url.pathSegments;
      if (segments.length == 1 && segments.single == 'healthz') {
        return Response.ok('ok');
      }
      if (segments.length != 3 || segments[0] != 'v1') {
        return Response.notFound('not found');
      }
      final role = segments[1];
      final roomId = segments[2];
      if (!_roomId.hasMatch(roomId) || (role != 'host' && role != 'join')) {
        return Response.notFound('not found');
      }
      return webSocketHandler(
        (WebSocketChannel socket, String? _) => role == 'host'
            ? rooms.host(roomId, socket)
            : rooms.join(roomId, socket),
        pingInterval: rooms.limits.pingInterval,
      )(request);
    };
  }

  final HttpServer _server;
  final RelayRooms rooms;

  int get port => _server.port;

  Future<void> close() async {
    await rooms.closeAll();
    await _server.close(force: true);
  }
}
