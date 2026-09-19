// SPDX-License-Identifier: AGPL-3.0-or-later
// T-601: the wire format for co-operative play.
//
// Every message is JSON with a `type` tag and carries the protocol version, so
// two builds that disagree say so at the door instead of desynchronising ten
// minutes in. The version is bumped whenever a field changes meaning; adding
// an optional field does not need a bump, removing or repurposing one does.
//
// The model is host-authoritative. A client never advances its own simulation:
// it sends an [Intent], and the host answers with [Applied] (in the order it
// decided) or [Denied]. The host's [Applied] and [Ticked] messages carry the
// state hash, so a client that has drifted finds out within one tick rather
// than at the end of the game.
import 'dart:convert';

import 'package:stadtbau_sim/stadtbau_sim.dart';

/// Incremented when the meaning of a field changes. Clients and hosts refuse
/// each other on a mismatch; there is no negotiation, because a game that
/// silently disagrees about the rules is worse than one that will not start.
const int protocolVersion = 1;

/// Why a host turned a client away.
enum RejectReason {
  /// The client speaks a different [protocolVersion].
  protocolMismatch,

  /// Every seat is taken.
  sessionFull,

  /// The game has already started and does not accept new players.
  alreadyStarted,

  /// The name is in use by another player in this session.
  nameTaken,

  /// The resume token does not match any seat this session is holding: the
  /// grace period expired, or it belongs to another session (T-605).
  unknownSeat;

  String get id => name;
  static RejectReason fromId(String id) => values.firstWhere(
    (r) => r.id == id,
    orElse: () => throw FormatException('unknown reject reason $id'),
  );
}

/// Why the host would not apply an intent. Simulation-level failures reuse
/// [CommandError]; these are the ones only a session can raise.
enum DenyReason {
  /// The cell is outside the district this player may build in.
  outsideDistrict,

  /// It is not this player's turn.
  notYourTurn,

  /// Only the host may advance time.
  hostOnly,

  /// The simulation itself refused; see [Denied.commandError].
  simulation;

  String get id => name;
  static DenyReason fromId(String id) => values.firstWhere(
    (r) => r.id == id,
    orElse: () => throw FormatException('unknown deny reason $id'),
  );
}

/// A rectangle of the map one player is responsible for (T-604). Districts do
/// not overlap; cross-border effects are the point of the mode, so the
/// simulation is shared and only the right to build is divided.
class District {
  const District({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final int x;
  final int y;
  final int width;
  final int height;

  bool contains(int cx, int cy) =>
      cx >= x && cy >= y && cx < x + width && cy < y + height;

  Map<String, dynamic> toJson() => {
    'x': x,
    'y': y,
    'width': width,
    'height': height,
  };

  static District fromJson(Map<String, dynamic> json) => District(
    x: json['x'] as int,
    y: json['y'] as int,
    width: json['width'] as int,
    height: json['height'] as int,
  );

  @override
  String toString() => 'District($x,$y ${width}x$height)';
}

/// One participant as everyone else sees them.
class PlayerInfo {
  const PlayerInfo({
    required this.id,
    required this.name,
    required this.isHost,
    this.district,
    this.ready = false,
    this.connected = true,
    this.tileStock = const {},
  });

  final String id;
  final String name;
  final bool isHost;
  final District? district;
  final bool ready;

  /// False while a player's seat is being held open for them after a dropped
  /// connection (T-605). Their district stays theirs and nobody else may
  /// build in it, so the others need to see that it is empty on purpose.
  final bool connected;

  /// What this player may still build, by tile id; a null value is unlimited
  /// and an absent key is not allowed at all (T-604).
  ///
  /// Everyone sees everyone's stock. The money is shared -- it is one
  /// municipal budget, which is the subject of the game -- so the allowances
  /// are the only private resource, and hiding them would stop people
  /// planning together, which is the mode's whole purpose.
  final Map<String, int?> tileStock;

  PlayerInfo copyWith({
    District? district,
    bool? ready,
    bool? connected,
    Map<String, int?>? tileStock,
  }) => PlayerInfo(
    id: id,
    name: name,
    isHost: isHost,
    district: district ?? this.district,
    ready: ready ?? this.ready,
    connected: connected ?? this.connected,
    tileStock: tileStock ?? this.tileStock,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'isHost': isHost,
    if (district != null) 'district': district!.toJson(),
    'ready': ready,
    'connected': connected,
    if (tileStock.isNotEmpty) 'tileStock': tileStock,
  };

  static PlayerInfo fromJson(Map<String, dynamic> json) => PlayerInfo(
    id: json['id'] as String,
    name: json['name'] as String,
    isHost: json['isHost'] as bool,
    district: json['district'] == null
        ? null
        : District.fromJson(json['district'] as Map<String, dynamic>),
    ready: json['ready'] as bool? ?? false,
    connected: json['connected'] as bool? ?? true,
    tileStock: (json['tileStock'] as Map<String, dynamic>? ?? const {}).map(
      (k, v) => MapEntry(k, v as int?),
    ),
  );
}

/// Base of every message on the wire.
sealed class NetMessage {
  const NetMessage();

  String get type;

  /// The payload without the envelope fields.
  Map<String, dynamic> get body;

  Map<String, dynamic> toJson() => {
    'v': protocolVersion,
    'type': type,
    ...body,
  };

  String encode() => jsonEncode(toJson());

  /// Parses one message.
  ///
  /// Throws [ProtocolVersionException] when the sender speaks another version
  /// -- a distinct type, because the caller must answer that with a
  /// [Rejected] rather than treat it as a corrupt frame.
  static NetMessage decode(String text) {
    final Object? raw = jsonDecode(text);
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('message is not a JSON object');
    }
    final version = raw['v'];
    if (version is! int) {
      throw const FormatException('message has no protocol version');
    }
    if (version != protocolVersion) {
      throw ProtocolVersionException(version);
    }
    final type = raw['type'];
    if (type is! String) {
      throw const FormatException('message has no type');
    }
    return switch (type) {
      'hello' => Hello.fromJson(raw),
      'welcome' => Welcome.fromJson(raw),
      'rejected' => Rejected.fromJson(raw),
      'lobby' => LobbyUpdate.fromJson(raw),
      'ready' => ReadyState.fromJson(raw),
      'endTurn' => EndTurn.fromJson(raw),
      'turn' => TurnChanged.fromJson(raw),
      'intent' => Intent.fromJson(raw),
      'applied' => Applied.fromJson(raw),
      'denied' => Denied.fromJson(raw),
      'ticked' => Ticked.fromJson(raw),
      'resync' => ResyncRequest.fromJson(raw),
      'snapshot' => Snapshot.fromJson(raw),
      'left' => PlayerLeft.fromJson(raw),
      _ => throw FormatException('unknown message type $type'),
    };
  }
}

/// Thrown by [NetMessage.decode] when the version does not match ours.
class ProtocolVersionException implements Exception {
  const ProtocolVersionException(this.theirs);
  final int theirs;
  int get ours => protocolVersion;
  @override
  String toString() =>
      'protocol version mismatch: peer speaks $theirs, we speak $ours';
}

/// client -> host: the first thing a client says.
class Hello extends NetMessage {
  const Hello({required this.name, this.resumeToken});
  final String name;

  /// A token from an earlier [Welcome], to reclaim the same seat after a
  /// dropped connection (T-605). Optional, which is why adding it needed no
  /// protocol bump: an older host ignores the field and answers as it always
  /// did, and an older client simply never sends one.
  final String? resumeToken;

  @override
  String get type => 'hello';
  @override
  Map<String, dynamic> get body => {
    'name': name,
    if (resumeToken != null) 'resumeToken': resumeToken,
  };
  static Hello fromJson(Map<String, dynamic> j) => Hello(
    name: j['name'] as String,
    resumeToken: j['resumeToken'] as String?,
  );
}

/// host -> one client: you are in, here is the world as it stands.
class Welcome extends NetMessage {
  const Welcome({
    required this.playerId,
    required this.players,
    required this.state,
    required this.hash,
    this.resumeToken,
    this.resumed = false,
    this.started = false,
  });

  final String playerId;
  final List<PlayerInfo> players;

  /// Present this on a later [Hello] to reclaim this seat (T-605). Kept out
  /// of [PlayerInfo] deliberately: the lobby list goes to everyone, and a
  /// token that lets someone take your seat is not lobby information.
  final String? resumeToken;

  /// Whether this welcome restored an existing seat rather than creating one.
  final bool resumed;

  /// Whether the game is already running, so a rejoining client goes straight
  /// to playing instead of sitting in a lobby that has moved on.
  final bool started;

  /// The full world, as [WorldState.toJson]. A joining client always starts
  /// from a snapshot; diffs only make sense once both sides agree on a base.
  final Map<String, dynamic> state;
  final int hash;

  @override
  String get type => 'welcome';
  @override
  Map<String, dynamic> get body => {
    'playerId': playerId,
    'players': [for (final p in players) p.toJson()],
    'state': state,
    'hash': hash,
    if (resumeToken != null) 'resumeToken': resumeToken,
    'resumed': resumed,
    'started': started,
  };

  static Welcome fromJson(Map<String, dynamic> j) => Welcome(
    playerId: j['playerId'] as String,
    players: [
      for (final p in j['players'] as List<dynamic>)
        PlayerInfo.fromJson(p as Map<String, dynamic>),
    ],
    state: j['state'] as Map<String, dynamic>,
    hash: j['hash'] as int,
    resumeToken: j['resumeToken'] as String?,
    resumed: j['resumed'] as bool? ?? false,
    started: j['started'] as bool? ?? false,
  );
}

/// host -> one client: you are not in, and why.
class Rejected extends NetMessage {
  const Rejected({required this.reason, this.hostProtocol = protocolVersion});
  final RejectReason reason;

  /// Sent even on a version mismatch, so the client can say *which* side is
  /// old rather than "connection failed".
  final int hostProtocol;

  @override
  String get type => 'rejected';
  @override
  Map<String, dynamic> get body => {
    'reason': reason.id,
    'hostProtocol': hostProtocol,
  };

  static Rejected fromJson(Map<String, dynamic> j) => Rejected(
    reason: RejectReason.fromId(j['reason'] as String),
    hostProtocol: j['hostProtocol'] as int? ?? protocolVersion,
  );
}

/// host -> all: who is here, with what district, and who is ready.
class LobbyUpdate extends NetMessage {
  const LobbyUpdate({
    required this.players,
    required this.started,
    this.currentPlayerId,
    this.round = 0,
  });

  final List<PlayerInfo> players;
  final bool started;

  /// Whose turn it is (T-604), null before the game starts.
  final String? currentPlayerId;
  final int round;

  @override
  String get type => 'lobby';
  @override
  Map<String, dynamic> get body => {
    'players': [for (final p in players) p.toJson()],
    'started': started,
    if (currentPlayerId != null) 'currentPlayerId': currentPlayerId,
    'round': round,
  };
  static LobbyUpdate fromJson(Map<String, dynamic> j) => LobbyUpdate(
    players: [
      for (final p in j['players'] as List<dynamic>)
        PlayerInfo.fromJson(p as Map<String, dynamic>),
    ],
    started: j['started'] as bool,
    currentPlayerId: j['currentPlayerId'] as String?,
    round: j['round'] as int? ?? 0,
  );
}

/// client -> host: my turn is over (T-604).
///
/// A new message type rather than a new field, and additive either way: an
/// older host ignores a frame it cannot parse, and an older client never
/// sends one. Turn order only exists once a game has started, so nothing
/// before this point changes meaning.
class EndTurn extends NetMessage {
  const EndTurn();
  @override
  String get type => 'endTurn';
  @override
  Map<String, dynamic> get body => const {};
  static EndTurn fromJson(Map<String, dynamic> j) => const EndTurn();
}

/// host -> all: whose turn it is now, and which round we are in (T-604).
class TurnChanged extends NetMessage {
  const TurnChanged({
    required this.currentPlayerId,
    required this.round,
    required this.tick,
  });

  /// Null before the game starts and after it ends.
  final String? currentPlayerId;
  final int round;
  final int tick;

  @override
  String get type => 'turn';
  @override
  Map<String, dynamic> get body => {
    if (currentPlayerId != null) 'currentPlayerId': currentPlayerId,
    'round': round,
    'tick': tick,
  };

  static TurnChanged fromJson(Map<String, dynamic> j) => TurnChanged(
    currentPlayerId: j['currentPlayerId'] as String?,
    round: j['round'] as int,
    tick: j['tick'] as int,
  );
}

/// client -> host: I am (not) ready to start.
class ReadyState extends NetMessage {
  const ReadyState({required this.ready});
  final bool ready;
  @override
  String get type => 'ready';
  @override
  Map<String, dynamic> get body => {'ready': ready};
  static ReadyState fromJson(Map<String, dynamic> j) =>
      ReadyState(ready: j['ready'] as bool);
}

/// client -> host: please do this. [seq] is the client's own counter, echoed
/// back in [Applied] or [Denied] so an answer can be matched to a request
/// (and so an optimistic local preview can be rolled back).
class Intent extends NetMessage {
  const Intent({required this.seq, required this.command});
  final int seq;
  final Command command;
  @override
  String get type => 'intent';
  @override
  Map<String, dynamic> get body => {'seq': seq, 'command': command.toJson()};
  static Intent fromJson(Map<String, dynamic> j) => Intent(
    seq: j['seq'] as int,
    command: Command.fromJson(j['command'] as Map<String, dynamic>),
  );
}

/// host -> all: this happened, at this tick, in this order.
class Applied extends NetMessage {
  const Applied({
    required this.playerId,
    required this.seq,
    required this.command,
    required this.tick,
    required this.hash,
  });

  final String playerId;
  final int seq;
  final Command command;
  final int tick;

  /// The host's state hash after applying. A client compares it with its own
  /// and asks for a [Snapshot] when they differ.
  final int hash;

  @override
  String get type => 'applied';
  @override
  Map<String, dynamic> get body => {
    'playerId': playerId,
    'seq': seq,
    'command': command.toJson(),
    'tick': tick,
    'hash': hash,
  };

  static Applied fromJson(Map<String, dynamic> j) => Applied(
    playerId: j['playerId'] as String,
    seq: j['seq'] as int,
    command: Command.fromJson(j['command'] as Map<String, dynamic>),
    tick: j['tick'] as int,
    hash: j['hash'] as int,
  );
}

/// host -> one client: no, and why.
class Denied extends NetMessage {
  const Denied({required this.seq, required this.reason, this.commandError});
  final int seq;
  final DenyReason reason;

  /// Set when [reason] is [DenyReason.simulation]: the simulation's own error.
  final CommandError? commandError;

  @override
  String get type => 'denied';
  @override
  Map<String, dynamic> get body => {
    'seq': seq,
    'reason': reason.id,
    if (commandError != null) 'commandError': commandError!.name,
  };

  static Denied fromJson(Map<String, dynamic> j) => Denied(
    seq: j['seq'] as int,
    reason: DenyReason.fromId(j['reason'] as String),
    commandError: j['commandError'] == null
        ? null
        : CommandError.values.firstWhere(
            (e) => e.name == j['commandError'] as String,
          ),
  );
}

/// host -> all: time moved.
class Ticked extends NetMessage {
  const Ticked({required this.tick, required this.hash});
  final int tick;
  final int hash;
  @override
  String get type => 'ticked';
  @override
  Map<String, dynamic> get body => {'tick': tick, 'hash': hash};
  static Ticked fromJson(Map<String, dynamic> j) =>
      Ticked(tick: j['tick'] as int, hash: j['hash'] as int);
}

/// client -> host: my hash disagrees with yours, send me the world.
class ResyncRequest extends NetMessage {
  const ResyncRequest({required this.tick, required this.hash});
  final int tick;
  final int hash;
  @override
  String get type => 'resync';
  @override
  Map<String, dynamic> get body => {'tick': tick, 'hash': hash};
  static ResyncRequest fromJson(Map<String, dynamic> j) =>
      ResyncRequest(tick: j['tick'] as int, hash: j['hash'] as int);
}

/// host -> one client: the world, again, from scratch.
class Snapshot extends NetMessage {
  const Snapshot({required this.state, required this.hash});
  final Map<String, dynamic> state;
  final int hash;
  @override
  String get type => 'snapshot';
  @override
  Map<String, dynamic> get body => {'state': state, 'hash': hash};
  static Snapshot fromJson(Map<String, dynamic> j) => Snapshot(
    state: j['state'] as Map<String, dynamic>,
    hash: j['hash'] as int,
  );
}

/// host -> all: someone is gone.
class PlayerLeft extends NetMessage {
  const PlayerLeft({required this.playerId});
  final String playerId;
  @override
  String get type => 'left';
  @override
  Map<String, dynamic> get body => {'playerId': playerId};
  static PlayerLeft fromJson(Map<String, dynamic> j) =>
      PlayerLeft(playerId: j['playerId'] as String);
}
