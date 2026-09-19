// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'package:stadtbau_net/stadtbau_net.dart';
import 'package:stadtbau_sim/stadtbau_sim.dart';

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
  });

  final SessionController controller;
  final LanServer? server;
  final List<String> roomCodes;
  final StreamSubscription<Transport>? _accepts;
  final String? _joinCode;

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

  static Future<LanSession> join({
    required String playerName,
    required String roomCode,
    String? resumeToken,
  }) async {
    final transport = await WebSocketTransport.connect(parseRoomCode(roomCode));
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
      final transport = await WebSocketTransport.connect(parseRoomCode(code));
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
  }
}
