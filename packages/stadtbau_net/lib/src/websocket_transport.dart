// SPDX-License-Identifier: AGPL-3.0-or-later
// T-602: a Transport over one WebSocket connection.
import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'transport.dart';

/// An ordered text-message transport backed by [WebSocketChannel].
///
/// The package supplies both the browser and `dart:io` client adapters. The
/// LAN server is conditionally imported separately, so importing this class
/// does not make a Flutter web build depend on `dart:io`.
class WebSocketTransport implements Transport {
  WebSocketTransport.fromChannel(WebSocketChannel channel)
    : _channel = channel {
    _subscription = channel.stream.listen(
      (message) {
        if (message is String && !_incoming.isClosed) {
          _incoming.add(message);
        }
      },
      onError: (Object error, StackTrace stack) {
        if (!_incoming.isClosed) _incoming.addError(error, stack);
      },
      onDone: () {
        _closed = true;
        if (!_incoming.isClosed) unawaited(_incoming.close());
      },
      cancelOnError: false,
    );
  }

  /// Connects and completes only after the WebSocket handshake succeeds.
  static Future<WebSocketTransport> connect(Uri uri) async {
    final channel = WebSocketChannel.connect(uri);
    await channel.ready;
    return WebSocketTransport.fromChannel(channel);
  }

  final WebSocketChannel _channel;
  final StreamController<String> _incoming = StreamController<String>.broadcast(
    sync: true,
  );
  late final StreamSubscription<dynamic> _subscription;
  bool _closed = false;

  @override
  Stream<String> get incoming => _incoming.stream;

  @override
  bool get isClosed => _closed;

  @override
  void send(String message) {
    if (!_closed) _channel.sink.add(message);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _channel.sink.close();
    await _subscription.cancel();
    if (!_incoming.isClosed) await _incoming.close();
  }
}
