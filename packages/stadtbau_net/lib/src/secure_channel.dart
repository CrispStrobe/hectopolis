// SPDX-License-Identifier: AGPL-3.0-or-later
// T-606: end-to-end encryption for play through an internet relay.
//
// A relay forwards frames between a host and its guests. It must not be able
// to read or alter a game, so every message is sealed with a key the relay
// never sees: one derived from the room secret, which travels only inside the
// room code people hand each other. The relay is given a room id derived from
// the same secret by a one-way hash, which is enough to route and nothing more.
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart' show DartSha256;

import 'transport.dart';

/// Wire format version of the sealed channel. Part of every key derivation, so
/// a future change cannot be confused with this one.
const relayProtocolVersion = 1;

const _helloPrefix = 'h$relayProtocolVersion.';
const _sealedPrefix = 'e$relayProtocolVersion.';
const _saltBytes = 32;
const _secretBytes = 16;

final _aead = Chacha20.poly1305Aead();
final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

/// The id a relay routes a room by: a one-way hash of the room secret, so the
/// relay can pair a host with its guests without learning the key that
/// protects what they say.
String relayRoomId(String secret) {
  final digest = const DartSha256().hashSync(
    utf8.encode('hectopolis-relay-v$relayProtocolVersion/room/$secret'),
  );
  return _hex(digest.bytes.sublist(0, 16));
}

/// A fresh 128-bit room secret, as lowercase hex.
String newRelaySecret([Random? random]) {
  final source = random ?? Random.secure();
  return _hex(List<int>.generate(_secretBytes, (_) => source.nextInt(256)));
}

/// Whether [value] has the shape of a room secret this channel accepts.
bool isRelaySecret(String value) =>
    RegExp('^[0-9a-f]{${_secretBytes * 2}}\$').hasMatch(value);

/// Raised when a channel cannot be opened: the peer is not speaking this
/// protocol, used a salt already seen, or holds a different secret.
class SecureChannelException implements Exception {
  const SecureChannelException(this.message);
  final String message;
  @override
  String toString() => 'SecureChannelException: $message';
}

/// A [Transport] whose messages are sealed with ChaCha20-Poly1305 under keys
/// only the two ends of a room know.
///
/// The guest opens with a random 32-byte salt in the clear. Both ends derive a
/// key per direction from the room secret and that salt (HKDF-SHA256), so
/// every connection has keys of its own. Each message is sealed under a
/// 96-bit nonce that counts up from zero and is never sent: the receiver
/// expects exactly the next count, so a frame the relay altered, replayed,
/// reordered or dropped fails to open and the channel closes. The protocol
/// recovers from a closed channel by reconnecting (T-605); it never sees a
/// forged message.
///
/// The host remembers every salt it has accepted, so a recorded connection
/// cannot be replayed into the room from its first frame.
class SecureChannel implements Transport {
  SecureChannel._(
    this._inner,
    this._sendKey,
    this._receiveKey, {
    StreamSubscription<String>? subscription,
    List<String> buffered = const [],
    bool innerDone = false,
  }) {
    final sub =
        subscription ??
        _inner.incoming.listen(null, onError: _onError, onDone: _finish);
    sub
      ..onData(_onFrame)
      ..onError(_onError)
      ..onDone(_finish);
    _subscription = sub;
    buffered.forEach(_onFrame);
    if (innerDone) _finish();
  }

  void _onError(Object error, StackTrace stack) {
    if (!_incoming.isClosed) _incoming.addError(error, stack);
  }

  /// Opens the guest end: sends the salt, then seals from the first message.
  static Future<SecureChannel> guest(
    Transport inner,
    String secret, {
    Random? random,
  }) async {
    _requireSecret(secret);
    final source = random ?? Random.secure();
    final salt = Uint8List.fromList(
      List<int>.generate(_saltBytes, (_) => source.nextInt(256)),
    );
    final keys = await _deriveKeys(secret, salt);
    inner.send('$_helloPrefix${base64Url.encode(salt)}');
    return SecureChannel._(inner, keys.guestToHost, keys.hostToGuest);
  }

  /// Opens the host end on a channel whose first frame must be a guest's
  /// salt. [seenSalts] is shared across every channel of one hosted room.
  static Future<SecureChannel> host(
    Transport inner,
    String secret, {
    required Set<String> seenSalts,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    _requireSecret(secret);
    // One subscription from the start: the stream is a broadcast, and a
    // guest's first sealed message may arrive while the keys are still being
    // derived. Re-subscribing after `first` would drop it, and the counter
    // check would then close a good channel.
    final hello = Completer<String>();
    final buffered = <String>[];
    var innerDone = false;
    final subscription = inner.incoming.listen(
      (frame) {
        if (!hello.isCompleted) {
          hello.complete(frame);
        } else {
          buffered.add(frame);
        }
      },
      onDone: () {
        innerDone = true;
        if (!hello.isCompleted) {
          hello.completeError(const SecureChannelException('closed early'));
        }
      },
    );
    Never refuse(String why) {
      unawaited(subscription.cancel());
      unawaited(inner.close());
      throw SecureChannelException(why);
    }

    final String opening;
    try {
      opening = await hello.future.timeout(timeout);
    } on Object {
      refuse('no opening frame');
    }
    if (!opening.startsWith(_helloPrefix)) refuse('not a sealed channel');
    final encoded = opening.substring(_helloPrefix.length);
    final Uint8List salt;
    try {
      salt = base64Url.decode(encoded);
    } on FormatException {
      refuse('malformed salt');
    }
    if (salt.length != _saltBytes) refuse('malformed salt');
    if (!seenSalts.add(encoded)) refuse('salt already used: a replay');
    final keys = await _deriveKeys(secret, salt);
    return SecureChannel._(
      inner,
      keys.hostToGuest,
      keys.guestToHost,
      subscription: subscription,
      buffered: buffered,
      innerDone: innerDone,
    );
  }

  static void _requireSecret(String secret) {
    if (!isRelaySecret(secret)) {
      throw ArgumentError.value(secret, 'secret', 'not a room secret');
    }
  }

  static Future<({SecretKey guestToHost, SecretKey hostToGuest})> _deriveKeys(
    String secret,
    Uint8List salt,
  ) async {
    final ikm = SecretKey(_unhex(secret));
    Future<SecretKey> derive(String direction) => _hkdf.deriveKey(
      secretKey: ikm,
      nonce: salt,
      info: utf8.encode('hectopolis relay v$relayProtocolVersion $direction'),
    );
    return (
      guestToHost: await derive('guest-to-host'),
      hostToGuest: await derive('host-to-guest'),
    );
  }

  final Transport _inner;
  final SecretKey _sendKey;
  final SecretKey _receiveKey;
  late final StreamSubscription<String> _subscription;
  final StreamController<String> _incoming = StreamController<String>.broadcast(
    sync: true,
  );

  var _sent = 0;
  var _received = 0;
  var _closed = false;

  // Sealing is asynchronous and [send] is not, so sends queue behind one
  // another, and so do opens: both directions keep the order they were given.
  Future<void> _sending = Future<void>.value();
  Future<void> _opening = Future<void>.value();

  @override
  Stream<String> get incoming => _incoming.stream;

  @override
  bool get isClosed => _closed;

  @override
  void send(String message) {
    if (_closed) return;
    final counter = _sent++;
    _sending = _sending.then((_) async {
      if (_closed) return;
      final box = await _aead.encrypt(
        utf8.encode(message),
        secretKey: _sendKey,
        nonce: _nonce(counter),
      );
      if (_closed) return;
      final sealed = Uint8List.fromList([...box.cipherText, ...box.mac.bytes]);
      _inner.send('$_sealedPrefix${base64Url.encode(sealed)}');
    });
  }

  void _onFrame(String frame) {
    if (_closed) return;
    final counter = _received++;
    _opening = _opening.then((_) async {
      if (_closed) return;
      final String clear;
      try {
        clear = await _open(frame, counter);
      } on Object {
        // Altered, replayed, reordered or missing: whatever it was, nothing
        // after it can be trusted on this channel.
        await close();
        return;
      }
      if (!_closed && !_incoming.isClosed) _incoming.add(clear);
    });
  }

  Future<String> _open(String frame, int counter) async {
    if (!frame.startsWith(_sealedPrefix)) {
      throw const SecureChannelException('unsealed frame');
    }
    final sealed = base64Url.decode(frame.substring(_sealedPrefix.length));
    if (sealed.length < 16) throw const SecureChannelException('short frame');
    final split = sealed.length - 16;
    final clear = await _aead.decrypt(
      SecretBox(
        sealed.sublist(0, split),
        nonce: _nonce(counter),
        mac: Mac(sealed.sublist(split)),
      ),
      secretKey: _receiveKey,
    );
    return utf8.decode(clear);
  }

  static List<int> _nonce(int counter) {
    final nonce = Uint8List(12);
    // Two 32-bit halves, not setUint64: compiled to JavaScript, Dart has no
    // 64-bit ByteData accessors, and on the web every seal threw. A counter
    // stays far below 2^53, where JavaScript numbers are still exact.
    ByteData.sublistView(nonce)
      ..setUint32(4, counter ~/ 0x100000000)
      ..setUint32(8, counter % 0x100000000);
    return nonce;
  }

  void _finish() {
    _closed = true;
    _opening.whenComplete(() {
      if (!_incoming.isClosed) unawaited(_incoming.close());
    });
  }

  @override
  Future<void> close() async {
    if (_closed && _incoming.isClosed) return;
    _closed = true;
    await _subscription.cancel();
    await _inner.close();
    if (!_incoming.isClosed) await _incoming.close();
  }
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List _unhex(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);
