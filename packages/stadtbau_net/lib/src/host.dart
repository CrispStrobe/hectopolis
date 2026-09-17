// SPDX-License-Identifier: AGPL-3.0-or-later
// T-601: the authoritative side of a co-operative session.
import 'dart:async';

import 'package:stadtbau_sim/stadtbau_sim.dart';

import 'protocol.dart';
import 'transport.dart';

/// One connected client, from the host's point of view.
class _Seat {
  _Seat(this.playerId, this.transport, this.subscription);

  /// Only the id. The player's own record lives in [SessionHost._players] and
  /// nowhere else: a seat that cached a copy meant `assignDistrict` updated
  /// one of them and the intent validator read the other, so a district
  /// silently did not apply.
  final String playerId;
  final Transport transport;
  final StreamSubscription<String> subscription;
}

/// Holds the only simulation that counts and tells everyone what happened.
///
/// The host applies commands in the order it receives them and broadcasts the
/// result with its state hash. Clients mirror; they never decide. That costs a
/// round trip on every placement and buys the thing that matters in a game
/// whose whole subject is second-order effects: everyone is looking at the
/// same city.
class SessionHost {
  SessionHost({
    required this.simulation,
    required String hostName,
    this.maxPlayers = 4,
    String Function()? idFactory,
  })  : _nextId = idFactory ?? _sequentialIds(),
        _hostPlayerId = '' {
    _hostPlayerId = _nextId();
    _players[_hostPlayerId] =
        PlayerInfo(id: _hostPlayerId, name: hostName, isHost: true);
  }

  /// Deterministic ids by default: a session's log is easier to read, and a
  /// test does not have to match a random string.
  static String Function() _sequentialIds() {
    var n = 0;
    return () => 'p${++n}';
  }

  final Simulation simulation;
  final int maxPlayers;
  final String Function() _nextId;

  String _hostPlayerId;
  String get hostPlayerId => _hostPlayerId;

  final Map<String, PlayerInfo> _players = {};
  final Map<String, _Seat> _seats = {};
  bool _started = false;

  /// Everyone in the session, host first.
  List<PlayerInfo> get players => [
        _players[_hostPlayerId]!,
        for (final e in _players.entries)
          if (e.key != _hostPlayerId) e.value,
      ];

  bool get started => _started;

  /// Whether every player has ticked ready. The host counts as ready.
  bool get allReady => players
      .where((p) => !p.isHost)
      .every((p) => p.ready);

  /// Assigns the district a player may build in (T-604).
  void assignDistrict(String playerId, District district) {
    final p = _players[playerId];
    if (p == null) return;
    _players[playerId] = p.copyWith(district: district);
    _broadcastLobby();
  }

  /// Starts the game. After this no new players are admitted, because joining
  /// mid-game would need a district carved out of someone else's.
  void start() {
    _started = true;
    _broadcastLobby();
  }

  /// Accepts a connection. The [transport] is read until it closes.
  void accept(Transport transport) {
    late final StreamSubscription<String> sub;
    sub = transport.incoming.listen(
      (text) => _onMessage(transport, text),
      onDone: () => _onDisconnect(transport),
    );
    _pending[transport] = sub;
  }

  final Map<Transport, StreamSubscription<String>> _pending = {};

  void _onMessage(Transport transport, String text) {
    NetMessage message;
    try {
      message = NetMessage.decode(text);
    } on ProtocolVersionException {
      // Answer in our own version so the client can name the mismatch. The
      // frame it cannot parse is still better than silence.
      transport.send(
          const Rejected(reason: RejectReason.protocolMismatch).encode());
      transport.close();
      return;
    } on FormatException {
      // A frame we cannot read is not a reason to drop a playing client: it
      // may be a newer optional field. Ignore it.
      return;
    }

    final seat = _seatOf(transport);
    switch (message) {
      case Hello(:final name):
        _onHello(transport, name);
      case ReadyState(:final ready) when seat != null:
        _players[seat.playerId] = _players[seat.playerId]!.copyWith(
          ready: ready,
        );
        _broadcastLobby();
      case Intent(:final seq, :final command) when seat != null:
        _onIntent(seat, seq, command);
      case ResyncRequest() when seat != null:
        seat.transport.send(_snapshot().encode());
      // Messages only a host sends, or that arrived before the handshake.
      case Hello() ||
            ReadyState() ||
            Intent() ||
            ResyncRequest() ||
            Welcome() ||
            Rejected() ||
            LobbyUpdate() ||
            Applied() ||
            Denied() ||
            Ticked() ||
            Snapshot() ||
            PlayerLeft():
        return;
    }
  }

  _Seat? _seatOf(Transport t) {
    for (final seat in _seats.values) {
      if (seat.transport == t) return seat;
    }
    return null;
  }

  void _onHello(Transport transport, String name) {
    final sub = _pending.remove(transport);
    if (sub == null) return; // already seated, or never accepted
    void reject(RejectReason reason) {
      transport.send(Rejected(reason: reason).encode());
      sub.cancel();
      transport.close();
    }

    if (_started) return reject(RejectReason.alreadyStarted);
    if (_players.length >= maxPlayers) return reject(RejectReason.sessionFull);
    if (_players.values.any((p) => p.name == name)) {
      return reject(RejectReason.nameTaken);
    }

    final id = _nextId();
    _players[id] = PlayerInfo(id: id, name: name, isHost: false);
    _seats[id] = _Seat(id, transport, sub);
    transport.send(Welcome(
      playerId: id,
      players: players,
      state: simulation.state.toJson(),
      hash: simulation.state.hash(),
    ).encode());
    _broadcastLobby();
  }

  void _onIntent(_Seat seat, int seq, Command command) {
    // Only the host moves time. Letting any client advance would make the
    // number of ticks depend on who clicked, and the simulation is
    // deterministic per tick, not per wall-clock second.
    if (command is AdvanceTick) {
      seat.transport
          .send(Denied(seq: seq, reason: DenyReason.hostOnly).encode());
      return;
    }
    final district = _players[seat.playerId]?.district;
    if (district != null && !_withinDistrict(command, district)) {
      seat.transport
          .send(Denied(seq: seq, reason: DenyReason.outsideDistrict).encode());
      return;
    }
    final result = simulation.apply(command);
    if (!result.ok) {
      seat.transport.send(Denied(
        seq: seq,
        reason: DenyReason.simulation,
        commandError: result.error,
      ).encode());
      return;
    }
    _broadcast(Applied(
      playerId: seat.playerId,
      seq: seq,
      command: command,
      tick: simulation.state.tick,
      hash: simulation.state.hash(),
    ));
  }

  static bool _withinDistrict(Command command, District district) =>
      switch (command) {
        PlaceTile(:final x, :final y) => district.contains(x, y),
        RemoveTile(:final x, :final y) => district.contains(x, y),
        AdvanceTick() => true,
      };

  /// The host's own action, which needs no permission but is broadcast the
  /// same way so every client sees one ordered stream.
  CommandResult applyAsHost(Command command) {
    final result = simulation.apply(command);
    if (!result.ok) return result;
    if (command is AdvanceTick) {
      _broadcast(
          Ticked(tick: simulation.state.tick, hash: simulation.state.hash()));
    } else {
      _broadcast(Applied(
        playerId: _hostPlayerId,
        seq: -1, // the host has no sequence of its own to match
        command: command,
        tick: simulation.state.tick,
        hash: simulation.state.hash(),
      ));
    }
    return result;
  }

  Snapshot _snapshot() => Snapshot(
        state: simulation.state.toJson(),
        hash: simulation.state.hash(),
      );

  void _onDisconnect(Transport transport) {
    _pending.remove(transport)?.cancel();
    for (final entry in _seats.entries.toList()) {
      if (entry.value.transport != transport) continue;
      entry.value.subscription.cancel();
      _seats.remove(entry.key);
      _players.remove(entry.key);
      _broadcast(PlayerLeft(playerId: entry.key));
      _broadcastLobby();
    }
  }

  void _broadcastLobby() =>
      _broadcast(LobbyUpdate(players: players, started: _started));

  void _broadcast(NetMessage message) {
    final text = message.encode();
    for (final seat in _seats.values) {
      seat.transport.send(text);
    }
  }

  /// Closes every connection.
  Future<void> dispose() async {
    for (final seat in _seats.values) {
      await seat.subscription.cancel();
      await seat.transport.close();
    }
    for (final sub in _pending.values) {
      await sub.cancel();
    }
    _seats.clear();
    _pending.clear();
  }
}
