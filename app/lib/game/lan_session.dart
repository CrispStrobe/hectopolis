// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'package:stadtbau_net/stadtbau_net.dart';
import 'package:stadtbau_sim/stadtbau_sim.dart';

import 'build_features.dart';
import 'session_controller.dart';

/// Owns the socket resources around a [SessionController].
///
/// Keeping this out of widgets gives every exit path one close operation and
/// makes it impossible for a lobby to leave a listening port behind.
class LanSession {
  LanSession._({
    required this.controller,
    this.server,
    this.roomCodes = const [],
    this._accepts,
    this._joinCode,
    this._relay,
  });

  final SessionController controller;
  final LanServer? server;
  final List<String> roomCodes;
  final StreamSubscription<Transport>? _accepts;
  final String? _joinCode;
  final RelayHostLink? _relay;

  static Future<LanSession> host({
    required String playerName,
    int width = 16,
    int height = 16,
  }) async {
    final server = await startLanServer();
    final controller = SessionController.host(
      simulation: Simulation.sandbox(width: width, height: height),
      playerName: playerName,
      tokenFactory: SessionHost.secureTokenFactory(),
    );
    final accepts = server.connections.listen(controller.accept);
    return LanSession._(
      controller: controller,
      server: server,
      roomCodes: [
        for (final address in server.addresses) server.roomCode(address),
      ],
      accepts: accepts,
    );
  }

  /// Hosts through a relay at [relay] (T-606): one outgoing connection,
  /// so it works where a LAN listener cannot, a browser included. Every guest
  /// arrives behind a [SecureChannel] keyed by the room secret, which the
  /// relay never sees.
  static Future<LanSession> hostViaRelay({
    required String playerName,
    required Uri relay,
    int width = 16,
    int height = 16,
  }) async {
    if (!relayEnabled) {
      throw UnsupportedError('this build does not play through a relay');
    }
    final code = RelayCode.create(relay);
    final link = RelayHostLink(await WebSocketTransport.connect(code.hostUri));
    final controller = SessionController.host(
      simulation: Simulation.sandbox(width: width, height: height),
      playerName: playerName,
      tokenFactory: SessionHost.secureTokenFactory(),
    );
    final accepts = secureGuests(link, code.secret).listen(controller.accept);
    return LanSession._(
      controller: controller,
      roomCodes: [code.toString()],
      accepts: accepts,
      relay: link,
    );
  }

  /// A LAN code connects directly; a relay code connects to the relay and
  /// seals the channel with the code's secret.
  static Future<Transport> _connect(String roomCode) async {
    // Without relays a relay code falls through to the LAN parser, which
    // refuses it: this build connects to nothing but the local network.
    final relayCode = relayEnabled ? RelayCode.tryParse(roomCode) : null;
    if (relayCode == null) {
      return WebSocketTransport.connect(parseRoomCode(roomCode));
    }
    final socket = await WebSocketTransport.connect(relayCode.joinUri);
    return SecureChannel.guest(socket, relayCode.secret);
  }

  static Future<LanSession> join({
    required String playerName,
    required String roomCode,
    String? resumeToken,
  }) async {
    final transport = await _connect(roomCode);
    return LanSession._(
      controller: SessionController.join(
        transport: transport,
        playerName: playerName,
        resumeToken: resumeToken,
      ),
      joinCode: roomCode,
    );
  }

  bool get canReconnect => _joinCode != null;

  Future<bool> reconnect() async {
    final code = _joinCode;
    if (code == null) return false;
    try {
      final transport = await _connect(code);
      await controller.reconnect(transport);
      return true;
    } on Object {
      return false;
    }
  }

  Future<void> close() async {
    final accepts = _accepts;
    if (accepts != null) await accepts.cancel();
    await controller.close();
    final listening = server;
    if (listening != null) await listening.close();
    await _relay?.close();
  }
}
