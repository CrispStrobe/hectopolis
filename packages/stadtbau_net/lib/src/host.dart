// SPDX-License-Identifier: AGPL-3.0-or-later
// T-601: the authoritative side of a co-operative session.
import 'dart:async';
import 'dart:math';

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
    this.roundMonths = 12,
    String Function()? idFactory,
    String Function()? tokenFactory,
  }) : _nextId = idFactory ?? _sequentialIds(),
       _nextToken = tokenFactory ?? _sequentialTokens(),
       _hostPlayerId = '' {
    _hostPlayerId = _nextId();
    _players[_hostPlayerId] = PlayerInfo(
      id: _hostPlayerId,
      name: hostName,
      isHost: true,
    );
  }

  /// Deterministic ids by default: a session's log is easier to read, and a
  /// test does not have to match a random string.
  static String Function() _sequentialIds() {
    var n = 0;
    return () => 'p${++n}';
  }

  /// Resume tokens, likewise deterministic by default. A real transport
  /// supplies something unguessable: the token is the only thing standing
  /// between a rejoining player and someone else taking their district, so
  /// over a network it must not be a counter. That is the transport's job to
  /// provide, and it is a named parameter so the choice is visible at the
  /// call site rather than buried here.
  static String Function() _sequentialTokens() {
    var n = 0;
    return () => 't${++n}';
  }

  /// Unguessable resume tokens for a host reachable over a real network.
  ///
  /// Tests keep the readable sequential default; a LAN entry point must pass
  /// this factory explicitly so a copied stale token cannot reclaim a seat.
  static String Function() secureTokenFactory() {
    final random = Random.secure();
    return () => List<int>.generate(
      16,
      (_) => random.nextInt(256),
    ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  final Simulation simulation;
  final int maxPlayers;

  /// How far time moves when a round closes (T-604). A year by default: long
  /// enough that a placement has visible consequences by the next turn, short
  /// enough that nobody waits through a decade of someone else's decisions.
  final int roundMonths;
  final String Function() _nextId;
  final String Function() _nextToken;

  String _hostPlayerId;
  String get hostPlayerId => _hostPlayerId;

  /// Emits whenever anything observable changed: a player joined, left, got
  /// a district or a ready flag, or the simulation advanced.
  ///
  /// The host broadcasts to its clients, but the host's *own* UI is not a
  /// client and was getting nothing — so a lobby on the hosting device never
  /// noticed anyone arrive (found by T-603's widget tests). A local observer
  /// needs telling too.
  Stream<SessionHost> get changes => _changes.stream;
  final StreamController<SessionHost> _changes =
      StreamController<SessionHost>.broadcast(sync: true);

  final Map<String, PlayerInfo> _players = {};
  final Map<String, _Seat> _seats = {};

  /// Resume token -> player id, for seats being held open (T-605).
  final Map<String, String> _tokens = {};

  /// Per-player tile allowances (T-604). The municipal budget is shared --
  /// that is the subject of the game -- so these are the only private
  /// resource, and they are what makes a district someone's responsibility
  /// rather than just their patch of map.
  final Map<String, TileBudget> _stock = {};

  List<String> _turnOrder = const [];
  int _turnIndex = 0;
  int _round = 0;
  bool _started = false;

  /// Everyone in the session, host first.
  List<PlayerInfo> get players => [
    _players[_hostPlayerId]!,
    for (final e in _players.entries)
      if (e.key != _hostPlayerId) e.value,
  ];

  bool get started => _started;

  /// Whose turn it is, or null before the game starts (T-604).
  String? get currentPlayerId =>
      _started && _turnOrder.isNotEmpty ? _turnOrder[_turnIndex] : null;

  /// Which round is being played; 0 before the start.
  int get round => _round;

  /// Gives a player their own allowance of tiles.
  void assignTileStock(String playerId, Map<TileType, int?> stock) {
    if (!_players.containsKey(playerId)) return;
    _stock[playerId] = TileBudget(stock);
    _players[playerId] = _players[playerId]!.copyWith(
      tileStock: {for (final e in stock.entries) e.key.id: e.value},
    );
    _broadcastLobby();
  }

  /// Ends [playerId]'s turn. Ignored when it is not their turn, so a late
  /// tap after the turn already moved on cannot skip somebody.
  ///
  /// When the round closes, time moves by [roundMonths] before the next round
  /// starts: consequences land between rounds, not in the middle of one, so
  /// everybody sees the same city while deciding.
  void endTurn(String playerId) {
    if (!_started || currentPlayerId != playerId) return;
    _turnIndex++;
    if (_turnIndex >= _turnOrder.length) {
      _turnIndex = 0;
      _round++;
      final result = simulation.apply(AdvanceTick(roundMonths));
      if (result.ok) {
        _broadcast(
          Ticked(tick: simulation.state.tick, hash: simulation.state.hash()),
        );
      }
    }
    _broadcastTurn();
  }

  void _broadcastTurn() => _broadcast(
    TurnChanged(
      currentPlayerId: currentPlayerId,
      round: _round,
      tick: simulation.state.tick,
    ),
  );

  /// Whether every player has ticked ready. The host counts as ready.
  bool get allReady =>
      players.where((p) => !p.isHost).every((p) => p.ready && p.connected);

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
    // Turn order is the seating order, host first: it is the order everyone
    // already sees in the lobby, so nobody has to be told what it is.
    _turnOrder = [for (final p in players) p.id];
    _turnIndex = 0;
    _round = 1;
    _broadcastLobby();
    _broadcastTurn();
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
        const Rejected(reason: RejectReason.protocolMismatch).encode(),
      );
      transport.close();
      return;
    } on FormatException {
      // A frame we cannot read is not a reason to drop a playing client: it
      // may be a newer optional field. Ignore it.
      return;
    }

    final seat = _seatOf(transport);
    switch (message) {
      case Hello(:final name, :final resumeToken):
        _onHello(transport, name, resumeToken);
      case EndTurn() when seat != null:
        endTurn(seat.playerId);
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
          EndTurn() ||
          TurnChanged() ||
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

  void _onHello(Transport transport, String name, String? resumeToken) {
    final sub = _pending.remove(transport);
    if (sub == null) return; // already seated, or never accepted
    void reject(RejectReason reason) {
      transport.send(Rejected(reason: reason).encode());
      sub.cancel();
      transport.close();
    }

    if (resumeToken != null) {
      final id = _tokens[resumeToken];
      // A token for a seat that is still connected is not a reconnect; it is
      // either a duplicate or someone else holding a stale copy, and honouring
      // it would evict the player sitting there.
      if (id == null || _seats.containsKey(id)) {
        return reject(RejectReason.unknownSeat);
      }
      _seats[id] = _Seat(id, transport, sub);
      _players[id] = _players[id]!.copyWith(connected: true);
      transport.send(_welcomeFor(id, resumeToken, resumed: true).encode());
      _broadcastLobby();
      return;
    }

    // A game in progress has its districts handed out; a new player would
    // need one carved out of someone else's. A *returning* player is handled
    // above, which is why the token check comes first.
    if (_started) return reject(RejectReason.alreadyStarted);
    if (_players.length >= maxPlayers) return reject(RejectReason.sessionFull);
    if (_players.values.any((p) => p.name == name)) {
      return reject(RejectReason.nameTaken);
    }

    final id = _nextId();
    final token = _nextToken();
    _tokens[token] = id;
    _players[id] = PlayerInfo(id: id, name: name, isHost: false);
    _seats[id] = _Seat(id, transport, sub);
    transport.send(_welcomeFor(id, token, resumed: false).encode());
    _broadcastLobby();
  }

  Welcome _welcomeFor(String id, String token, {required bool resumed}) =>
      Welcome(
        playerId: id,
        players: players,
        state: simulation.state.toJson(),
        hash: simulation.state.hash(),
        resumeToken: token,
        resumed: resumed,
        started: _started,
      );

  void _onIntent(_Seat seat, int seq, Command command) {
    // Only the host moves time. Letting any client advance would make the
    // number of ticks depend on who clicked, and the simulation is
    // deterministic per tick, not per wall-clock second.
    if (command is AdvanceTick) {
      seat.transport.send(
        Denied(seq: seq, reason: DenyReason.hostOnly).encode(),
      );
      return;
    }
    if (_started && currentPlayerId != seat.playerId) {
      seat.transport.send(
        Denied(seq: seq, reason: DenyReason.notYourTurn).encode(),
      );
      return;
    }
    final district = _players[seat.playerId]?.district;
    if (district != null && !_withinDistrict(command, district)) {
      seat.transport.send(
        Denied(seq: seq, reason: DenyReason.outsideDistrict).encode(),
      );
      return;
    }
    // A player's own allowance is checked before the simulation, so running
    // out of parks is reported as running out of parks rather than as
    // whatever the shared budget happens to say.
    final stock = _stock[seat.playerId];
    if (stock != null && command is PlaceTile) {
      if (!stock.allowed(command.tile)) {
        seat.transport.send(
          Denied(
            seq: seq,
            reason: DenyReason.simulation,
            commandError: CommandError.tileNotAllowed,
          ).encode(),
        );
        return;
      }
      final left = stock.remaining(command.tile);
      if (left != null && left <= 0) {
        seat.transport.send(
          Denied(
            seq: seq,
            reason: DenyReason.simulation,
            commandError: CommandError.tileExhausted,
          ).encode(),
        );
        return;
      }
    }
    final result = simulation.apply(command);
    if (!result.ok) {
      seat.transport.send(
        Denied(
          seq: seq,
          reason: DenyReason.simulation,
          commandError: result.error,
        ).encode(),
      );
      return;
    }
    if (stock != null && command is PlaceTile) {
      _spend(seat.playerId, command.tile);
    }
    _broadcast(
      Applied(
        playerId: seat.playerId,
        seq: seq,
        command: command,
        tick: simulation.state.tick,
        hash: simulation.state.hash(),
      ),
    );
  }

  static bool _withinDistrict(Command command, District district) =>
      switch (command) {
        PlaceTile(:final x, :final y) => district.contains(x, y),
        RemoveTile(:final x, :final y) => district.contains(x, y),
        AdvanceTick() => true,
      };

  /// The host's own action, which needs no permission but is broadcast the
  /// same way so every client sees one ordered stream. "Authoritative" does
  /// not mean exempt: once play starts the host has the same turn, district
  /// and private tile allowance as every guest.
  CommandResult applyAsHost(Command command) {
    if (_started && currentPlayerId != _hostPlayerId) {
      return const CommandResult.failed(CommandError.tileNotAllowed);
    }
    final district = _players[_hostPlayerId]?.district;
    if (district != null && !_withinDistrict(command, district)) {
      return const CommandResult.failed(CommandError.outOfBounds);
    }
    final stock = _stock[_hostPlayerId];
    if (stock != null && command is PlaceTile) {
      if (!stock.allowed(command.tile)) {
        return const CommandResult.failed(CommandError.tileNotAllowed);
      }
      final left = stock.remaining(command.tile);
      if (left != null && left <= 0) {
        return const CommandResult.failed(CommandError.tileExhausted);
      }
    }
    final result = simulation.apply(command);
    if (!result.ok) return result;
    if (stock != null && command is PlaceTile) {
      _spend(_hostPlayerId, command.tile);
    }
    if (command is AdvanceTick) {
      _broadcast(
        Ticked(tick: simulation.state.tick, hash: simulation.state.hash()),
      );
    } else {
      _broadcast(
        Applied(
          playerId: _hostPlayerId,
          seq: -1, // the host has no sequence of its own to match
          command: command,
          tick: simulation.state.tick,
          hash: simulation.state.hash(),
        ),
      );
    }
    return result;
  }

  Snapshot _snapshot() =>
      Snapshot(state: simulation.state.toJson(), hash: simulation.state.hash());

  void _onDisconnect(Transport transport) {
    _pending.remove(transport)?.cancel();
    for (final entry in _seats.entries.toList()) {
      if (entry.value.transport != transport) continue;
      entry.value.subscription.cancel();
      _seats.remove(entry.key);
      if (_started) {
        // Hold the seat. Dropping the player would free their district for
        // someone else and lose the tiles they still owe, and a dropped
        // connection mid-game is the ordinary case, not the exception
        // (T-605). They come back with their resume token.
        _players[entry.key] = _players[entry.key]!.copyWith(connected: false);
      } else {
        // In the lobby there is nothing to hold, so leaving means leaving.
        _players.remove(entry.key);
        _tokens.removeWhere((_, id) => id == entry.key);
      }
      _broadcast(PlayerLeft(playerId: entry.key));
      _broadcastLobby();
    }
  }

  /// Gives up a held seat for good, freeing its district and its name.
  ///
  /// Not automatic: there is no clock in this package, and a grace period
  /// measured in this layer would be a policy decision made in the wrong
  /// place. The session UI decides when a player is not coming back.
  void releaseSeat(String playerId) {
    if (_seats.containsKey(playerId)) return; // they are connected
    _players.remove(playerId);
    _tokens.removeWhere((_, id) => id == playerId);
    _broadcastLobby();
  }

  /// Takes one tile off a player's allowance and republishes the list.
  void _spend(String playerId, TileType tile) {
    final stock = _stock[playerId];
    final left = stock?.remaining(tile);
    if (stock == null || left == null) return; // unlimited, nothing to spend
    final updated = {
      for (final t in stock.allowedTypes)
        t: t == tile ? left - 1 : stock.remaining(t),
    };
    _stock[playerId] = TileBudget(updated);
    _players[playerId] = _players[playerId]!.copyWith(
      tileStock: {for (final e in updated.entries) e.key.id: e.value},
    );
    _broadcastLobby();
  }

  void _broadcastLobby() => _broadcast(
    LobbyUpdate(
      players: players,
      started: _started,
      currentPlayerId: currentPlayerId,
      round: _round,
    ),
  );

  void _broadcast(NetMessage message) {
    final text = message.encode();
    for (final seat in _seats.values) {
      seat.transport.send(text);
    }
    // Every broadcast is by definition a change worth showing locally, and
    // going through one place means a new message type cannot forget to
    // notify. Safe to fire synchronously: this is a different controller from
    // the transports', so it is not re-entrant on one that is already firing.
    if (!_changes.isClosed) _changes.add(this);
  }

  /// Closes every connection.
  Future<void> dispose() async {
    // See SessionClient.dispose: nothing observes this controller's `done`,
    // and awaiting it hangs under a faked clock.
    unawaited(_changes.close());
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
