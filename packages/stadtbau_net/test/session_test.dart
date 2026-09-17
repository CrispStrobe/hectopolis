// SPDX-License-Identifier: AGPL-3.0-or-later
// T-601: a real host and real clients in one isolate, over the in-memory
// transport. The question these answer is the only one that matters for a
// shared city: does every side hold bit-identical state?
import 'package:stadtbau_net/stadtbau_net.dart';
import 'package:stadtbau_sim/stadtbau_sim.dart';
import 'package:test/test.dart';

/// A host with a small world and [n] joined clients, settled.
///
/// Delivery is asynchronous, as a socket's is, so every test awaits
/// [InMemoryTransport.settle] after acting. That is not test ceremony: a
/// protocol whose correctness depended on synchronous delivery would be
/// broken in the only deployment that matters.
Future<({SessionHost host, List<SessionClient> clients})> _session(
  int n, {
  int size = 12,
  double budget = 100000,
  int maxPlayers = 4,
}) async {
  final host = SessionHost(
    simulation: Simulation(
      state: WorldState.empty(width: size, height: size, budgetKEur: budget),
    ),
    hostName: 'Host',
    maxPlayers: maxPlayers,
  );
  final clients = <SessionClient>[];
  for (var i = 0; i < n; i++) {
    final (hostEnd, clientEnd) = InMemoryTransport.pair();
    host.accept(hostEnd);
    clients.add(
        SessionClient(transport: clientEnd, playerName: 'Player ${i + 1}'));
  }
  await InMemoryTransport.settle();
  return (host: host, clients: clients);
}

void main() {
  group('handshake', () {
    test('a client is welcomed with the world and the same hash', () async {
      final s = await _session(1);
      final c = s.clients.single;
      expect(c.phase, SessionPhase.lobby);
      expect(c.playerId, isNotNull);
      expect(c.simulation, isNotNull);
      expect(c.simulation!.state.hash(), s.host.simulation.state.hash());
      expect(c.players.map((p) => p.name), ['Host', 'Player 1']);
      expect(c.players.first.isHost, isTrue);
    });

    test('a full session turns a client away', () async {
      final s = await _session(1, maxPlayers: 2);
      final (hostEnd, clientEnd) = InMemoryTransport.pair();
      s.host.accept(hostEnd);
      final late = SessionClient(transport: clientEnd, playerName: 'Late');
      await InMemoryTransport.settle();
      expect(late.phase, SessionPhase.rejected);
      expect(late.rejectReason, RejectReason.sessionFull);
      expect(late.simulation, isNull);
    });

    test('a duplicate name is refused', () async {
      final s = await _session(1);
      final (hostEnd, clientEnd) = InMemoryTransport.pair();
      s.host.accept(hostEnd);
      final twin = SessionClient(transport: clientEnd, playerName: 'Player 1');
      await InMemoryTransport.settle();
      expect(twin.rejectReason, RejectReason.nameTaken);
    });

    test('joining after the start is refused', () async {
      final s = await _session(1);
      s.host.start();
      final (hostEnd, clientEnd) = InMemoryTransport.pair();
      s.host.accept(hostEnd);
      final late = SessionClient(transport: clientEnd, playerName: 'Late');
      await InMemoryTransport.settle();
      expect(late.rejectReason, RejectReason.alreadyStarted);
    });

    test('a client on another protocol version is told which side is old', () async {
      final s = await _session(0);
      final (hostEnd, clientEnd) = InMemoryTransport.pair();
      s.host.accept(hostEnd);
      final seen = <String>[];
      clientEnd.incoming.listen(seen.add);
      // A build from the future says hello.
      clientEnd.send('{"v":99,"type":"hello","name":"Future"}');
      await InMemoryTransport.settle();
      expect(seen, hasLength(1));
      final answer = NetMessage.decode(seen.single) as Rejected;
      expect(answer.reason, RejectReason.protocolMismatch);
      expect(answer.hostProtocol, protocolVersion);
    });
  });

  group('authority', () {
    test('a placement reaches every client and keeps hashes equal', () async {
      final s = await _session(2);
      final seq = s.clients.first.request(const PlaceTile(3, 3, TileType.park));
      await InMemoryTransport.settle();
      expect(seq, 1);
      expect(s.clients.first.denials, isEmpty);
      final hostHash = s.host.simulation.state.hash();
      for (final c in s.clients) {
        expect(c.simulation!.state.tiles[3 * 12 + 3], TileType.park);
        expect(c.simulation!.state.hash(), hostHash);
        expect(c.resyncCount, 0);
      }
    });

    test('a client may not advance time', () async {
      final s = await _session(1);
      final c = s.clients.single;
      final seq = c.request(const AdvanceTick(5));
      await InMemoryTransport.settle();
      expect(c.denials[seq]?.reason, DenyReason.hostOnly);
      expect(s.host.simulation.state.tick, 0);
    });

    test('the host advancing time pulls every client along exactly', () async {
      final s = await _session(2);
      s.host.applyAsHost(const AdvanceTick(7));
      await InMemoryTransport.settle();
      expect(s.host.simulation.state.tick, 7);
      for (final c in s.clients) {
        expect(c.simulation!.state.tick, 7);
        expect(c.simulation!.state.hash(), s.host.simulation.state.hash());
        expect(c.resyncCount, 0);
      }
    });

    test('a district confines where a player may build', () async {
      final s = await _session(1);
      final c = s.clients.single;
      s.host.assignDistrict(
          c.playerId!, const District(x: 0, y: 0, width: 6, height: 12));
      await InMemoryTransport.settle();
      final inside = c.request(const PlaceTile(2, 2, TileType.park));
      final outside = c.request(const PlaceTile(9, 2, TileType.park));
      await InMemoryTransport.settle();
      expect(c.denials[inside], isNull);
      expect(c.denials[outside]?.reason, DenyReason.outsideDistrict);
      expect(s.host.simulation.state.tiles[2 * 12 + 2], TileType.park);
      expect(s.host.simulation.state.tiles[2 * 12 + 9], isNot(TileType.park));
    });

    test("a simulation refusal is passed back with the simulation's reason", () async {
      final s = await _session(1, budget: 10); // 10 k€ buys nothing
      final c = s.clients.single;
      final seq = c.request(const PlaceTile(1, 1, TileType.commercial));
      await InMemoryTransport.settle();
      expect(c.denials[seq]?.reason, DenyReason.simulation);
      expect(c.denials[seq]?.commandError, CommandError.insufficientBudget);
    });

    test('the host and a client building in turn stay identical', () async {
      final s = await _session(2);
      final a = s.clients[0];
      final b = s.clients[1];
      for (var i = 0; i < 6; i++) {
        a.request(PlaceTile(i, 1, TileType.housingLow));
        s.host.applyAsHost(PlaceTile(i, 3, TileType.road));
        b.request(PlaceTile(i, 5, TileType.park));
        s.host.applyAsHost(const AdvanceTick(2));
        await InMemoryTransport.settle();
      }
      final hash = s.host.simulation.state.hash();
      expect(a.simulation!.state.hash(), hash);
      expect(b.simulation!.state.hash(), hash);
      expect(a.resyncCount, 0);
      expect(b.resyncCount, 0);
      expect(a.simulation!.state.tick, s.host.simulation.state.tick);
    });
  });

  group('sync', () {
    test('a client that missed a message repairs itself from a snapshot', () async {
      final s = await _session(1);
      final c = s.clients.single;
      // Simulate a lost frame: apply something on the host without telling
      // anyone, which is exactly the state a dropped Applied leaves behind.
      s.host.simulation.apply(const PlaceTile(4, 4, TileType.industry));
      await InMemoryTransport.settle();
      expect(c.simulation!.state.hash(),
          isNot(s.host.simulation.state.hash()));

      // The next authoritative message carries the host's hash, so the
      // client notices within one tick rather than at the end of the game.
      s.host.applyAsHost(const AdvanceTick());
      await InMemoryTransport.settle();
      expect(c.resyncCount, 1);
      expect(c.simulation!.state.hash(), s.host.simulation.state.hash());
      expect(c.simulation!.state.tiles[4 * 12 + 4], TileType.industry);
    });

    test('a healthy session never resyncs', () async {
      final s = await _session(3);
      for (var i = 0; i < 4; i++) {
        for (final c in s.clients) {
          c.request(PlaceTile(i, i, TileType.meadow));
        }
        s.host.applyAsHost(const AdvanceTick(3));
        await InMemoryTransport.settle();
      }
      for (final c in s.clients) {
        expect(c.resyncCount, 0);
      }
    });
  });

  group('lobby', () {
    test('ready state travels to every client', () async {
      final s = await _session(2);
      expect(s.host.allReady, isFalse);
      s.clients[0].setReady(ready: true);
      await InMemoryTransport.settle();
      expect(s.host.allReady, isFalse);
      s.clients[1].setReady(ready: true);
      await InMemoryTransport.settle();
      expect(s.host.allReady, isTrue);
      for (final c in s.clients) {
        expect(c.players.where((p) => p.ready).length, 2);
      }
    });

    test('starting the game moves every client into play', () async {
      final s = await _session(2);
      s.host.start();
      await InMemoryTransport.settle();
      for (final c in s.clients) {
        expect(c.started, isTrue);
        expect(c.phase, SessionPhase.playing);
      }
    });

    test('a departure is announced and the player list shrinks', () async {
      final s = await _session(2);
      await s.clients[1].dispose();
      await InMemoryTransport.settle();
      expect(s.host.players.map((p) => p.name), ['Host', 'Player 1']);
      expect(s.clients[0].players.map((p) => p.name), ['Host', 'Player 1']);
    });
  });
}
