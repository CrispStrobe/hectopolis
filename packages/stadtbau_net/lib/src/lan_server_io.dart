// SPDX-License-Identifier: AGPL-3.0-or-later
// Native side of T-602. This file is never imported by a web build.
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'lan_server_base.dart';
import 'transport.dart';
import 'websocket_transport.dart';

const supported = true;

String _secret() {
  final random = Random.secure();
  return List<int>.generate(
    16,
    (_) => random.nextInt(256),
  ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

Future<LanServer> start({required int port}) async {
  final secret = _secret();
  final accepted = StreamController<Transport>.broadcast(sync: true);
  final socketHandler = webSocketHandler((WebSocketChannel channel, String? _) {
    accepted.add(WebSocketTransport.fromChannel(channel));
  }, pingInterval: const Duration(seconds: 15));
  Future<Response> handler(Request request) async {
    if (request.url.path != secret) return Response.notFound('Not found');
    return socketHandler(request);
  }

  final server = await shelf_io.serve(
    handler,
    InternetAddress.anyIPv4,
    port,
    shared: false,
  );
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLoopback: false,
  );
  final addresses = <String>{
    for (final interface in interfaces)
      for (final address in interface.addresses)
        if (!address.isLinkLocal) address.address,
  }.toList()..sort();
  return _IoLanServer(
    server: server,
    accepted: accepted,
    roomSecret: secret,
    addresses: addresses.isEmpty ? const ['127.0.0.1'] : addresses,
  );
}

class _IoLanServer extends LanServer {
  _IoLanServer({
    required this._server,
    required this._accepted,
    required this.roomSecret,
    required this.addresses,
  });

  final HttpServer _server;
  final StreamController<Transport> _accepted;

  @override
  int get port => _server.port;

  @override
  final String roomSecret;

  @override
  final List<String> addresses;

  @override
  Stream<Transport> get connections => _accepted.stream;

  @override
  Future<void> close() async {
    await _server.close(force: true);
    await _accepted.close();
  }
}
