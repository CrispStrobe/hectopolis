// SPDX-License-Identifier: AGPL-3.0-or-later
// T-601: the mirroring side of a co-operative session.
import 'dart:async';

import 'package:stadtbau_sim/stadtbau_sim.dart';

import 'protocol.dart';
import 'transport.dart';

/// What a client is currently doing.
enum SessionPhase { connecting, lobby, playing, rejected, closed }

/// Mirrors the host's simulation and asks for what the local player wants.
///
/// The client keeps its own [Simulation] and replays the host's [Applied] and
/// [Ticked] messages into it. That is not an optimisation: the fields, the
/// overlays and the indicators are all derived state, and recomputing them
/// locally from the authoritative commands is far cheaper than shipping them.
/// The hash on every message is what makes it safe -- one disagreement and
/// the client throws its world away and takes the host's.
class SessionClient {
  SessionClient({required this.transport, required this.playerName}) {
    _sub = transport.incoming.listen(_onMessage, onDone: _onDone);
    transport.send(Hello(name: playerName).encode());
  }

  final Transport transport;
  final String playerName;

  late final StreamSubscription<String> _sub;
  final StreamController<SessionClient> _changes =
      StreamController<SessionClient>.broadcast(sync: true);

  /// Emits this client whenever anything observable changed, so a UI can
  /// listen once instead of subscribing to six things.
  Stream<SessionClient> get changes => _changes.stream;

  SessionPhase phase = SessionPhase.connecting;
  RejectReason? rejectReason;

  /// Set when the host speaks another protocol version: which version it
  /// speaks, so the UI can say who needs to update.
  int? hostProtocolVersion;

  String? playerId;
  List<PlayerInfo> players = const [];
  bool started = false;

  /// The mirrored world. Null until [Welcome] arrives.
  Simulation? simulation;

  /// Errors the host sent back, by the sequence number of the intent.
  final Map<int, Denied> denials = {};

  /// How many times this client had to take a snapshot because its hash
  /// disagreed with the host's. Zero in a healthy session; a test asserts it,
  /// and a session that keeps resyncing is a determinism bug worth finding.
  int resyncCount = 0;

  int _seq = 0;

  /// Asks the host to do something. Returns the sequence number, which will
  /// come back on [Applied] or in [denials].
  int request(Command command) {
    final seq = ++_seq;
    transport.send(Intent(seq: seq, command: command).encode());
    return seq;
  }

  /// Announces readiness in the lobby.
  void setReady({required bool ready}) =>
      transport.send(ReadyState(ready: ready).encode());

  void _onMessage(String text) {
    NetMessage message;
    try {
      message = NetMessage.decode(text);
    } on ProtocolVersionException catch (e) {
      phase = SessionPhase.rejected;
      rejectReason = RejectReason.protocolMismatch;
      hostProtocolVersion = e.theirs;
      _notify();
      transport.close();
      return;
    } on FormatException {
      return; // a field we do not know about; ignore rather than fall over
    }

    switch (message) {
      case Welcome(:final playerId, :final players, :final state, :final hash):
        this.playerId = playerId;
        this.players = players;
        _adopt(state, hash);
        phase = started ? SessionPhase.playing : SessionPhase.lobby;
      case Rejected(:final reason, :final hostProtocol):
        phase = SessionPhase.rejected;
        rejectReason = reason;
        hostProtocolVersion = hostProtocol;
      case LobbyUpdate(:final players, :final started):
        this.players = players;
        this.started = started;
        if (started && phase == SessionPhase.lobby) {
          phase = SessionPhase.playing;
        }
      case Applied(:final command, :final hash):
        final sim = simulation;
        if (sim == null) return;
        sim.apply(command);
        _verify(hash);
      case Ticked(:final tick, :final hash):
        final sim = simulation;
        if (sim == null) return;
        // Catch up exactly, rather than assuming one tick: a message may have
        // been lost, and the tick number is authoritative.
        final behind = tick - sim.state.tick;
        if (behind > 0) sim.apply(AdvanceTick(behind));
        _verify(hash);
      case Denied(:final seq):
        denials[seq] = message;
      case Snapshot(:final state, :final hash):
        _adopt(state, hash);
      case PlayerLeft(:final playerId):
        players = [
          for (final p in players)
            if (p.id != playerId) p,
        ];
      case Hello() || ReadyState() || Intent() || ResyncRequest():
        return; // client-to-host messages; not ours to handle
    }
    _notify();
  }

  void _adopt(Map<String, dynamic> state, int hash) {
    simulation = Simulation(state: WorldState.fromJson(state));
    final ours = simulation!.state.hash();
    if (ours != hash) {
      // The host's own snapshot does not match its own hash: the two sides
      // disagree about serialisation, not about the game. Nothing a resync
      // can fix, so it is surfaced rather than papered over.
      throw StateError(
          'snapshot hash mismatch: host says $hash, ours is $ours');
    }
  }

  void _verify(int hostHash) {
    final sim = simulation;
    if (sim == null || sim.state.hash() == hostHash) return;
    resyncCount++;
    transport.send(
        ResyncRequest(tick: sim.state.tick, hash: sim.state.hash()).encode());
  }

  void _onDone() {
    if (phase != SessionPhase.rejected) phase = SessionPhase.closed;
    _notify();
  }

  void _notify() {
    if (!_changes.isClosed) _changes.add(this);
  }

  Future<void> dispose() async {
    await _sub.cancel();
    await _changes.close();
    await transport.close();
  }
}
