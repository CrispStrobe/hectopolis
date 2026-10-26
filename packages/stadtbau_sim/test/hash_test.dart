// SPDX-License-Identifier: AGPL-3.0-or-later
// The world hash is compared between a co-op host and its guests, which may be
// a native app and a browser, so it must come out the same on both. Run in
// the VM and in Chrome (`dart test -p chrome`); the expected values were
// computed in the VM.
import 'package:stadtbau_sim/stadtbau_sim.dart';
import 'package:test/test.dart';

void main() {
  test('a world hashes the same on every platform', () {
    // Doubles that are integral (budgets), fractional populations and an
    // infinite sandbox budget: everything that printed differently before.
    final sandbox = Simulation.sandbox(width: 8, height: 8)
      ..apply(const PlaceTile(2, 2, TileType.housingHigh))
      ..apply(const AdvanceTick(5));
    expect(sandbox.state.hash(), 532814957);
  });

  test('a level a year in hashes the same on every platform', () {
    // Thirteen months of simulation: if the platforms' floating-point maths
    // drifted apart, the worlds themselves would differ, and this would say.
    for (final (id, expected) in [
      ('village', 2585897395),
      ('tuebingen', 19036017),
    ]) {
      final sim = Level.byId(id)!.start()..apply(const AdvanceTick(13));
      expect(sim.state.hash(), expected, reason: id);
    }
  });
}
