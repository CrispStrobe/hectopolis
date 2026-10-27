// SPDX-License-Identifier: AGPL-3.0-or-later
// T-606: playing through a self-hosted relay.
//
// The host keeps one connection to the relay and receives every guest over
// it; the relay wraps each guest's frames in a small envelope naming the
// channel. This file undoes that wrapping, so the host sees one [Transport] per
// guest exactly as it does on a LAN, and the session logic does not change.
// It opens no sockets itself: the app connects (`WebSocketTransport`) and
// hands the connection in, which keeps networking at the reviewed boundary.
import 'dart:async';
import 'dart:convert';

import 'secure_channel.dart';
import 'transport.dart';

/// A relay room code: the relay's address and the room secret.
///
/// Written `wss://relay.example.org/r/<secret>`, optionally under a path the
/// relay is served from (`wss://example.org/hectopolis/r/<secret>`). The
/// `/r/` segment keeps it apart from a LAN code (`address:port/secret`). Only
/// `wss` is accepted, except for a relay on the device itself, which a
/// developer runs without a certificate.
///
/// The secret never reaches the relay: it is given [roomId], a one-way hash,
/// and the secret keys the encryption between host and guests.
class RelayCode {
  RelayCode(this.relay, this.secret) {
    if (!isRelaySecret(secret)) {
      throw ArgumentError.value(secret, 'secret', 'not a room secret');
    }
    if (!_acceptable(relay)) {
      throw ArgumentError.value(relay, 'relay', 'must use wss://');
    }
  }

  /// A new room on [relay], with a fresh secret.
  factory RelayCode.create(Uri relay) => RelayCode(relay, newRelaySecret());

  /// Parses a typed or pasted relay code, or returns null if [value] is not
  /// one (it may be a LAN code instead).
  static RelayCode? tryParse(String value) {
    final Uri uri;
    try {
      uri = Uri.parse(value.trim());
    } on FormatException {
      return null;
    }
    final segments = uri.pathSegments;
    if (segments.length < 2 || segments[segments.length - 2] != 'r') {
      return null;
    }
    final secret = segments.last.toLowerCase();
    if (!isRelaySecret(secret)) return null;
    final relay = uri.replace(
      pathSegments: segments.sublist(0, segments.length - 2),
      query: null,
      fragment: null,
    );
    if (!_acceptable(relay)) return null;
    return RelayCode(relay, secret);
  }

  /// Parses the address a host types for its relay, such as
  /// `relay.example.org` or `wss://example.org/hectopolis`. Returns null when
  /// it is not a usable relay address.
  static Uri? parseRelayAddress(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final Uri uri;
    try {
      uri = Uri.parse(trimmed.contains('://') ? trimmed : 'wss://$trimmed');
    } on FormatException {
      return null;
    }
    if (uri.host.isEmpty) return null;
    final relay = uri.replace(query: null, fragment: null);
    return _acceptable(relay) ? relay : null;
  }

  static bool _acceptable(Uri relay) {
    if (relay.host.isEmpty) return false;
    if (relay.scheme == 'wss') return true;
    return relay.scheme == 'ws' && _loopback(relay.host);
  }

  static bool _loopback(String host) =>
      host == 'localhost' || host == '127.0.0.1' || host == '::1';

  final Uri relay;
  final String secret;

  /// What the relay is told: enough to pair a host with its guests.
  String get roomId => relayRoomId(secret);

  Uri get hostUri => _endpoint('host');
  Uri get joinUri => _endpoint('join');

  Uri _endpoint(String role) => relay.replace(
    pathSegments: [
      ...relay.pathSegments.where((s) => s.isNotEmpty),
      'v$relayProtocolVersion',
      role,
      roomId,
    ],
  );

  @override
  String toString() => relay
      .replace(
        pathSegments: [
          ...relay.pathSegments.where((s) => s.isNotEmpty),
          'r',
          secret,
        ],
      )
      .toString();
}

/// The hosting device's end of a relay room: one connection to the relay,
/// split back into one [Transport] per guest.
///
/// Frames between the relay and the host are JSON envelopes,
/// `{"op": "open" | "data" | "close", "ch": <int>, "m": <frame>}`. Guests send
/// plain frames and never see an envelope; the relay adds and removes them.
class RelayHostLink {
  RelayHostLink(this._relay) {
    _subscription = _relay.incoming.listen(
      _onEnvelope,
      onDone: _onRelayGone,
      onError: (Object _) => _onRelayGone(),
    );
  }

  final Transport _relay;
  late final StreamSubscription<String> _subscription;
  final _channels = <int, _RelayChannel>{};
  final _opened = StreamController<Transport>.broadcast(sync: true);

  /// One [Transport] per guest the relay connects, as they arrive.
  Stream<Transport> get channels => _opened.stream;

  /// Whether the connection to the relay has gone, and the room with it.
  bool get isClosed => _relay.isClosed;

  void _onEnvelope(String frame) {
    final Object? decoded;
    try {
      decoded = jsonDecode(frame);
    } on FormatException {
      return;
    }
    if (decoded is! Map<String, Object?>) return;
    final op = decoded['op'];
    final ch = decoded['ch'];
    if (ch is! int) return;
    switch (op) {
      case 'open':
        if (_channels.containsKey(ch)) return;
        final channel = _RelayChannel(this, ch);
        _channels[ch] = channel;
        if (!_opened.isClosed) _opened.add(channel);
      case 'data':
        final m = decoded['m'];
        if (m is String) _channels[ch]?._deliver(m);
      case 'close':
        _channels.remove(ch)?._finish();
    }
  }

  void _send(int ch, String op, [String? message]) {
    _relay.send(jsonEncode({'op': op, 'ch': ch, 'm': ?message}));
  }

  void _onRelayGone() {
    for (final channel in _channels.values.toList()) {
      channel._finish();
    }
    _channels.clear();
    if (!_opened.isClosed) unawaited(_opened.close());
  }

  Future<void> close() async {
    await _subscription.cancel();
    _onRelayGone();
    await _relay.close();
  }
}

class _RelayChannel implements Transport {
  _RelayChannel(this._link, this._ch);

  final RelayHostLink _link;
  final int _ch;
  final _incoming = StreamController<String>.broadcast(sync: true);
  var _closed = false;

  @override
  Stream<String> get incoming => _incoming.stream;

  @override
  bool get isClosed => _closed;

  @override
  void send(String message) {
    if (!_closed) _link._send(_ch, 'data', message);
  }

  void _deliver(String message) {
    if (!_closed && !_incoming.isClosed) _incoming.add(message);
  }

  void _finish() {
    _closed = true;
    if (!_incoming.isClosed) unawaited(_incoming.close());
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _link._channels.remove(_ch);
    _link._send(_ch, 'close');
    _finish();
  }
}

/// The guests of a relay room, each behind a [SecureChannel], ready for
/// `SessionHost.accept`. A guest that fails to open its channel (another
/// secret, a replayed salt, or silence) is dropped without holding up the
/// others.
Stream<Transport> secureGuests(RelayHostLink link, String secret) {
  final seen = <String>{};
  final out = StreamController<Transport>.broadcast(sync: true);
  link.channels.listen(
    (channel) {
      SecureChannel.host(channel, secret, seenSalts: seen).then((secured) {
        if (out.isClosed) {
          unawaited(secured.close());
        } else {
          out.add(secured);
        }
      }, onError: (Object _) {});
    },
    onDone: () {
      if (!out.isClosed) unawaited(out.close());
    },
  );
  return out.stream;
}
