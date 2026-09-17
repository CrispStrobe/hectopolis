// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:stadtbau_net/stadtbau_net.dart';
import 'package:stadtbau_sim/stadtbau_sim.dart';
import 'package:test/test.dart';

void main() {
  group('wire format', () {
    test('every message survives a round trip', () {
      final messages = <NetMessage>[
        const Hello(name: 'Ada'),
        Welcome(
          playerId: 'p2',
          players: const [
            PlayerInfo(id: 'p1', name: 'Host', isHost: true),
            PlayerInfo(
              id: 'p2',
              name: 'Ada',
              isHost: false,
              district: District(x: 0, y: 0, width: 8, height: 16),
              ready: true,
            ),
          ],
          state: WorldState.empty(width: 4, height: 4, budgetKEur: 0).toJson(),
          hash: 12345,
        ),
        const Rejected(reason: RejectReason.sessionFull),
        const LobbyUpdate(players: [], started: true),
        const ReadyState(ready: true),
        const Intent(seq: 7, command: PlaceTile(1, 2, TileType.park)),
        const Applied(
          playerId: 'p2',
          seq: 7,
          command: RemoveTile(1, 2),
          tick: 9,
          hash: 42,
        ),
        const Denied(seq: 7, reason: DenyReason.outsideDistrict),
        const Denied(
          seq: 8,
          reason: DenyReason.simulation,
          commandError: CommandError.insufficientBudget,
        ),
        const Ticked(tick: 12, hash: 7),
        const ResyncRequest(tick: 12, hash: 8),
        const PlayerLeft(playerId: 'p2'),
      ];
      for (final m in messages) {
        final back = NetMessage.decode(m.encode());
        expect(back.type, m.type);
        expect(back.toJson(), m.toJson(), reason: m.type);
      }
    });

    test('a snapshot carries a world that comes back identical', () {
      final w = WorldState.empty(width: 6, height: 6, budgetKEur: 1000);
      final sim = Simulation(state: w);
      sim.apply(const PlaceTile(1, 1, TileType.housingLow));
      sim.apply(const AdvanceTick(3));
      final message = Snapshot(
        state: sim.state.toJson(),
        hash: sim.state.hash(),
      );
      final back = NetMessage.decode(message.encode()) as Snapshot;
      final restored = WorldState.fromJson(back.state);
      expect(restored.hash(), sim.state.hash());
      expect(back.hash, sim.state.hash());
    });

    test('a different protocol version is a distinct failure', () {
      // Not a FormatException: the caller has to answer it with a Rejected,
      // and "corrupt frame" and "wrong build" need different handling.
      const text = '{"v":999,"type":"hello","name":"Ada"}';
      expect(() => NetMessage.decode(text),
          throwsA(isA<ProtocolVersionException>()));
      try {
        NetMessage.decode(text);
      } on ProtocolVersionException catch (e) {
        expect(e.theirs, 999);
        expect(e.ours, protocolVersion);
      }
    });

    test('unknown types and missing envelopes are format errors', () {
      expect(() => NetMessage.decode('{"v":1,"type":"nonsense"}'),
          throwsFormatException);
      expect(() => NetMessage.decode('{"type":"hello","name":"x"}'),
          throwsFormatException);
      expect(() => NetMessage.decode('[]'), throwsFormatException);
    });

    test('a district covers its own cells and no others', () {
      const d = District(x: 2, y: 3, width: 4, height: 2);
      expect(d.contains(2, 3), isTrue);
      expect(d.contains(5, 4), isTrue);
      expect(d.contains(6, 4), isFalse);
      expect(d.contains(2, 5), isFalse);
      expect(d.contains(1, 3), isFalse);
    });
  });
}
