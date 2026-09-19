// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:stadtbau_net/stadtbau_net.dart';
import 'package:stadtbau_sim/stadtbau_sim.dart';

/// Bridges a co-operative session to Flutter (T-603).
///
/// The protocol package knows nothing about widgets and the widgets know
/// nothing about the protocol; this is the one place that holds both. It is a
/// [ChangeNotifier] because that is what the rest of this app uses, and it
/// deliberately exposes plain lists and flags rather than the message types,
/// so a screen cannot accidentally depend on the wire format.
///
/// A [Transport] is injected. Socket ownership stays in [LanSession], so the
/// same controller is driven by an in-memory pair in tests and a WebSocket in
/// the app without either the widgets or the protocol knowing which.
class SessionController extends ChangeNotifier {
  SessionController._({required this.isHost});

  /// Starts a session this device owns, with [simulation] as the world.
  factory SessionController.host({
    required Simulation simulation,
    required String playerName,
    int maxPlayers = 4,
    String Function()? tokenFactory,
  }) {
    final c = SessionController._(isHost: true);
    final host = SessionHost(
      simulation: simulation,
      hostName: playerName,
      maxPlayers: maxPlayers,
      tokenFactory: tokenFactory,
    );
    c._host = host;
    c._players = host.players;
    // The host's own UI is not one of its clients, so it has to listen.
    c._hostSub = host.changes.listen((_) => c._refreshFromHost());
    return c;
  }

  /// Joins a session over an already-connected [transport].
  factory SessionController.join({
    required Transport transport,
    required String playerName,
    String? resumeToken,
  }) {
    final c = SessionController._(isHost: false);
    c._guestName = playerName;
    c._client = SessionClient(
      transport: transport,
      playerName: playerName,
      resumeToken: resumeToken,
    );
    c._clientSub = c._client!.changes.listen((_) => c._onClientChanged());
    return c;
  }

  final bool isHost;

  SessionHost? _host;
  SessionClient? _client;
  String? _guestName;
  StreamSubscription<SessionClient>? _clientSub;
  StreamSubscription<SessionHost>? _hostSub;

  List<PlayerInfo> _players = const [];

  /// Everyone in the session, host first.
  List<PlayerInfo> get players => _players;

  /// The simulation to play: the host's own, or the client's mirror.
  Simulation? get simulation => _host?.simulation ?? _client?.simulation;

  /// This device's player id, once known.
  String? get playerId => _host?.hostPlayerId ?? _client?.playerId;

  bool get started => _host?.started ?? (_client?.started ?? false);

  /// Whose turn it is, or null before the game starts (T-604).
  String? get currentPlayerId =>
      _host?.currentPlayerId ?? _client?.currentPlayerId;

  /// Which round is being played; 0 before the start.
  int get round => _host?.round ?? (_client?.round ?? 0);

  /// Whether this device may build right now.
  bool get isMyTurn => playerId != null && playerId == currentPlayerId;

  /// Ends this player's turn. When the last player ends theirs, the host
  /// moves time on and the next round begins.
  void endTurn() {
    final host = _host;
    if (host != null) {
      host.endTurn(host.hostPlayerId);
    } else {
      _client?.endTurn();
    }
  }

  /// What this device may still build, by tile id; null means unlimited and
  /// an absent key means not allowed (T-604).
  Map<String, int?> get myTileStock {
    final id = playerId;
    if (id == null) return const {};
    for (final p in players) {
      if (p.id == id) return p.tileStock;
    }
    return const {};
  }

  /// Host only: give a player their own allowance of tiles.
  void assignTileStock(String playerId, Map<TileType, int?> stock) {
    _host?.assignTileStock(playerId, stock);
    _refreshFromHost();
  }

  /// Whether every guest has ticked ready, so the host may start.
  bool get canStart =>
      isHost && (_host?.allReady ?? false) && players.length > 1;

  /// Set when a join was refused, so the screen can say why.
  RejectReason? get rejectReason => _client?.rejectReason;

  /// The host's protocol version when that was the reason for a refusal.
  int? get hostProtocolVersion => _client?.hostProtocolVersion;

  /// The token that would reclaim this seat after a drop (T-605). The screen
  /// holds it; it is not shown to anyone.
  String? get resumeToken => _client?.resumeToken;

  bool get disconnected => _client?.phase == SessionPhase.closed;

  /// Replaces a dropped guest connection while presenting the same resume
  /// token, so the host returns the held seat and its district (T-605).
  Future<void> reconnect(Transport transport) async {
    if (isHost || _guestName == null) return;
    final oldSub = _clientSub;
    if (oldSub != null) await oldSub.cancel();
    final old = _client;
    final token = old?.resumeToken;
    if (old != null) await old.dispose();
    _client = SessionClient(
      transport: transport,
      playerName: _guestName!,
      resumeToken: token,
    );
    _clientSub = _client!.changes.listen((_) => _onClientChanged());
    notifyListeners();
  }

  /// Accepts a guest. Host only; the transport comes from outside.
  void accept(Transport transport) {
    final host = _host;
    if (host == null) return;
    host.accept(transport);
    _refreshFromHost();
  }

  /// Divides the map into one district per player (T-604).
  ///
  /// Vertical strips, in player order. Strips rather than quadrants because
  /// every strip then touches both the top and bottom edge of the map: with
  /// quadrants the player in the far corner can be shielded from everyone
  /// else's noise and traffic, and a mode whose whole point is that effects
  /// cross borders should not hand anyone a quiet corner.
  void splitIntoStrips() {
    final host = _host;
    if (host == null) return;
    final n = players.length;
    if (n == 0) return;
    final width = host.simulation.state.width;
    final height = host.simulation.state.height;
    final each = width ~/ n;
    for (var i = 0; i < n; i++) {
      final last = i == n - 1;
      host.assignDistrict(
        players[i].id,
        District(
          x: i * each,
          y: 0,
          // The last strip takes the remainder, so no column is unassigned
          // when the width does not divide evenly.
          width: last ? width - i * each : each,
          height: height,
        ),
      );
      host.assignTileStock(players[i].id, {
        for (final tile in host.simulation.tileBudget.allowedTypes)
          tile: switch (host.simulation.tileBudget.remaining(tile)) {
            null => null,
            final count => count ~/ n + (i < count % n ? 1 : 0),
          },
      });
    }
    _refreshFromHost();
  }

  /// Gives one player a district explicitly.
  void assignDistrict(String playerId, District district) {
    _host?.assignDistrict(playerId, district);
    _refreshFromHost();
  }

  /// Guest only: announce readiness.
  void setReady({required bool ready}) => _client?.setReady(ready: ready);

  /// Host only: begin. No new players are admitted afterwards.
  void start() {
    _host?.start();
    _refreshFromHost();
  }

  /// Host only: give up a seat that is being held open for a player who is
  /// not coming back (T-605).
  void releaseSeat(String playerId) {
    _host?.releaseSeat(playerId);
    _refreshFromHost();
  }

  /// Asks for a command to be applied: directly when hosting, as an intent
  /// when joined.
  void request(Command command) {
    if (_host != null) {
      _host!.applyAsHost(command);
      notifyListeners();
    } else {
      _client?.request(command);
    }
  }

  /// The district this device may build in, if one was assigned.
  District? get myDistrict {
    final id = playerId;
    if (id == null) return null;
    for (final p in players) {
      if (p.id == id) return p.district;
    }
    return null;
  }

  void _refreshFromHost() {
    final host = _host;
    if (host == null) return;
    _players = host.players;
    notifyListeners();
  }

  void _onClientChanged() {
    _players = _client!.players;
    notifyListeners();
  }

  /// Closes the session and waits for it. Prefer this where you can await;
  /// [dispose] exists because `ChangeNotifier.dispose` is synchronous and
  /// widget teardown will not await anything.
  Future<void> close() async {
    // Explicit null checks rather than `await _host?.dispose()`. Awaiting a
    // null-aware call whose receiver is null stalls under `flutter_test`'s
    // faked clock -- a guest has no host and a host has no client, so half of
    // these are null every time, and the teardown never finished (T-603).
    final hostSub = _hostSub;
    if (hostSub != null) await hostSub.cancel();
    final clientSub = _clientSub;
    if (clientSub != null) await clientSub.cancel();
    final host = _host;
    if (host != null) await host.dispose();
    final client = _client;
    if (client != null) await client.dispose();
  }

  @override
  void dispose() {
    // Fire and forget: a widget being torn down cannot wait, and there is
    // nothing useful to do if closing a transport fails at this point.
    close();
    super.dispose();
  }
}
