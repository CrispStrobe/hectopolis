// SPDX-License-Identifier: AGPL-3.0-or-later
// The world hash is compared between a co-op host and its guests, which may be
// a native app and a browser, so it must come out the same on both. Run in
// the VM and in Chrome (`dart test -p chrome`).
import 'package:stadtbau_sim/stadtbau_sim.dart';
import 'package:test/test.dart';

import '../tool/world_hashes.dart';
import 'world_hashes.g.dart';

void main() {
  test('a world hashes the same on every platform', () {
    // Built directly, so the value does not move with the model: integral
    // and fractional doubles and an unlimited budget, everything that printed
    // differently in JavaScript before the hash was made canonical.
    final world = WorldState.fromJson({
      'width': 2,
      'height': 2,
      'tick': 7,
      'budgetKEur': 'unlimited',
      'seed': 3,
      'tiles': ['meadow', 'housing_high', 'road', 'park'],
      'tileAge': [0, 12, 3, 240],
      'population': [0, 1500.0, 0.125, 28.716823772356285],
    });
    expect(world.hash(), 1845398304);
  });

  test('simulated worlds hash as the VM computed them', () {
    // In the VM this checks the generated file is current; in Chrome it
    // checks a browser simulates and hashes exactly what the VM does.
    expect(
      simulatedWorldHashes(),
      simulatedWorldHashesInVm,
      reason:
          'if the model changed, regenerate: dart run tool/world_hashes.dart',
    );
  });
}
