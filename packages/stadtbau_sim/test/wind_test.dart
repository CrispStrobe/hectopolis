// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:stadtbau_sim/src/generated/default_params.dart';
import 'package:stadtbau_sim/stadtbau_sim.dart';
import 'package:test/test.dart';

/// The shipped parameters with the air section overridden, the way a level
/// does it through paramOverrides.
SimParams _withAir(Map<String, dynamic> air) {
  final json = jsonDecode(defaultParamsJson) as Map<String, dynamic>;
  final section = json['air'] as Map<String, dynamic>;
  for (final entry in air.entries) {
    section[entry.key] = {'value': entry.value, 'source': 'test'};
  }
  return SimParams.fromJson(json);
}

/// Concentration at (x, y) with a single industry tile in the middle.
Simulation _plume(SimParams params) {
  final w = WorldState.empty(width: 21, height: 21, budgetKEur: 1e9);
  final sim = Simulation(state: w, params: params);
  sim.apply(const PlaceTile(10, 10, TileType.industry));
  return sim;
}

void main() {
  test('calm air is exactly the isotropic model', () {
    final sim = _plume(_withAir({'windSpeedMs': 0}));
    final f = sim.fields;
    double at(int x, int y) => f.airConcentration[sim.state.index(x, y)];
    // Four cells at equal distance must receive equal amounts.
    expect(at(10, 6), closeTo(at(10, 14), 1e-12));
    expect(at(6, 10), closeTo(at(14, 10), 1e-12));
    expect(at(10, 6), closeTo(at(6, 10), 1e-12));
  });

  test('wind carries the plume downwind and starves the upwind side', () {
    // Wind from the north blows towards the south, which is +y on the grid.
    final sim = _plume(_withAir({'windFromDegrees': 0, 'windSpeedMs': 4}));
    final f = sim.fields;
    double at(int x, int y) => f.airConcentration[sim.state.index(x, y)];
    expect(
      at(10, 14),
      greaterThan(at(10, 6)),
      reason: 'south of the source should get more than north of it',
    );
    expect(
      at(10, 14),
      greaterThan(at(14, 10)),
      reason: 'and more than the same distance crosswind',
    );
    // Crosswind is narrowed, so it loses against calm at the same distance.
    final calm = _plume(_withAir({'windSpeedMs': 0}));
    expect(
      at(14, 10),
      lessThan(calm.fields.airConcentration[calm.state.index(14, 10)]),
    );
  });

  test('the wind turns with the parameter', () {
    // From the west: the plume runs east, +x.
    final sim = _plume(_withAir({'windFromDegrees': 270, 'windSpeedMs': 4}));
    final f = sim.fields;
    double at(int x, int y) => f.airConcentration[sim.state.index(x, y)];
    expect(at(14, 10), greaterThan(at(6, 10)));
    expect(at(14, 10), greaterThan(at(10, 14)));
  });

  test('wind moves pollution about rather than creating it', () {
    double burden(SimParams p) {
      final sim = _plume(p);
      var sum = 0.0;
      for (final v in sim.fields.airConcentration) {
        sum += v;
      }
      return sum;
    }

    // The kernel is renormalised for the wind, so the total in the field is
    // the same emission spread differently -- give or take what the plume
    // pushes past the radius cut-off.
    final calm = burden(_withAir({'windSpeedMs': 0}));
    final windy = burden(_withAir({'windFromDegrees': 0, 'windSpeedMs': 4}));
    expect(windy, closeTo(calm, calm * 0.2));
  });

  test('the breakdown still adds up to the field under wind', () {
    final sim = _plume(_withAir({'windFromDegrees': 0, 'windSpeedMs': 4}));
    final cell = sim.state.index(10, 13);
    var sum = 0.0;
    for (final c in sim.explainAir(10, 13)) {
      sum += c.value;
    }
    expect(sum, closeTo(sim.fields.airConcentration[cell], 1e-9));
  });
}
