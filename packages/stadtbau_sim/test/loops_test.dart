// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:stadtbau_sim/stadtbau_sim.dart';
import 'package:test/test.dart';

void main() {
  test('every loop is reported and bounded', () {
    final sim = Simulation.sandbox();
    final loops = sim.loops;
    expect(loops.length, CausalLoop.values.length);
    expect({for (final l in loops) l.loop}, CausalLoop.values.toSet());
    for (final l in loops) {
      expect(l.strength, inInclusiveRange(0, 1), reason: l.loop.name);
      expect(l.nodes, isNotEmpty, reason: l.loop.name);
    }
    // Strongest first, so the head of the list is the dominant loop.
    for (var i = 1; i < loops.length; i++) {
      expect(loops[i - 1].strength, greaterThanOrEqualTo(loops[i].strength));
    }
  });

  test('a bare map runs only the loop its land is actually in', () {
    final sim = Simulation.sandbox();
    final byLoop = {for (final l in sim.loops) l.loop: l.strength};
    // No people, no jobs, no money moving: nothing for these to act on.
    expect(byLoop[CausalLoop.crowding], 0);
    expect(byLoop[CausalLoop.taxBase], 0);
    expect(byLoop[CausalLoop.inCommuting], 0);
    expect(byLoop[CausalLoop.fragmentation], 0);
    // The sandbox is young meadow, and meadow keeps growing for ten years.
    // What is outstanding is 1 - biotopeStart, not 1: the model already counts
    // a new meadow as worth part of its value.
    final meadow = SimParams.defaults().tile(TileType.meadow);
    expect(
      byLoop[CausalLoop.regrowth],
      closeTo(1 - meadow.biotopeStart.value, 1e-9),
    );
  });

  LoopActivity of(Simulation s, CausalLoop l) =>
      s.loops.firstWhere((a) => a.loop == l);

  test('jobs without homes drive the in-commuting loop', () {
    final sim = Simulation.sandbox();
    expect(of(sim, CausalLoop.inCommuting).strength, 0);
    // Commercial tiles with no housing anywhere: every job comes from outside.
    for (var x = 2; x < 6; x++) {
      sim.apply(PlaceTile(x, 2, TileType.commercial));
    }
    sim.apply(const AdvanceTick(3));
    expect(of(sim, CausalLoop.inCommuting).strength, closeTo(1, 1e-9));
    expect(sim.loops.first.loop, CausalLoop.inCommuting);
  });

  test('young nature owes what old nature has paid', () {
    final sim = Simulation.sandbox();
    sim.apply(const PlaceTile(4, 4, TileType.forest));
    sim.apply(const AdvanceTick(1));
    final young = of(sim, CausalLoop.regrowth).strength;
    expect(young, greaterThan(0.5), reason: 'a fresh planting owes nearly all');
    sim.apply(const AdvanceTick(600));
    expect(
      of(sim, CausalLoop.regrowth).strength,
      lessThan(young),
      reason: 'and owes less once it has grown',
    );
  });

  test('residents next to a busy road feel the crowding loop', () {
    final sim = Simulation.sandbox();
    expect(of(sim, CausalLoop.crowding).strength, 0);
    for (var y = 0; y < 16; y++) {
      sim.apply(PlaceTile(8, y, TileType.road));
    }
    sim.apply(const PlaceTile(9, 8, TileType.housingHigh));
    sim.apply(const AdvanceTick(12));
    expect(of(sim, CausalLoop.crowding).strength, greaterThan(0));
  });
}
