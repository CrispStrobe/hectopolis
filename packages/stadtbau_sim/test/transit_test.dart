// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:stadtbau_sim/src/generated/default_params.dart';
import 'package:stadtbau_sim/stadtbau_sim.dart';
import 'package:test/test.dart';

SimParams _withCommute(Map<String, dynamic> overrides) {
  final json = jsonDecode(defaultParamsJson) as Map<String, dynamic>;
  final section = json['commute'] as Map<String, dynamic>;
  for (final entry in overrides.entries) {
    section[entry.key] = {'value': entry.value, 'source': 'test'};
  }
  return SimParams.fromJson(json);
}

/// A small town: homes on the left, jobs on the right, one road between them.
Simulation _town([SimParams? params]) {
  final w = WorldState.empty(width: 16, height: 16, budgetKEur: 1e9);
  final sim = Simulation(state: w, params: params ?? SimParams.defaults());
  for (var y = 0; y < 16; y++) {
    sim.apply(PlaceTile(8, y, TileType.road));
  }
  for (var y = 6; y < 10; y++) {
    sim.apply(PlaceTile(6, y, TileType.housingHigh));
    sim.apply(PlaceTile(10, y, TileType.commercial));
  }
  sim.apply(const AdvanceTick(24));
  return sim;
}

void main() {
  final cp = SimParams.defaults().commute;

  test('a stop is reachable from its surroundings and no further', () {
    final sim = Simulation.sandbox();
    sim.apply(const PlaceTile(8, 8, TileType.tramStop));
    final f = sim.fields;
    double at(int x, int y) => f.transitAccess[sim.state.index(x, y)];
    expect(at(8, 8), 1.0);
    expect(at(9, 8), greaterThan(0));
    expect(at(8, 8 + cp.transitWalkRadiusTiles), 0.0);
    // Falls off with distance rather than switching off at the edge.
    expect(at(9, 8), greaterThan(at(10, 8)));
  });

  // Car share at a home cell is what the shift actually changes. Total car-km
  // is a poor probe in this town: it has 400 jobs against a few dozen local
  // workers, so most of its traffic is in-commuters from outside, whom neither
  // a local stop nor a local route serves, and they dilute the effect to a
  // fraction of a percent.
  double homeCarShare(Simulation sim) =>
      sim.fields.carShare[sim.state.index(6, 8)];

  test('a tram stop takes cars off the road', () {
    final without = _town();
    final with_ = _town();
    // Beside the homes, so the trip has the stop at its origin end.
    with_.apply(const PlaceTile(5, 8, TileType.tramStop));
    with_.apply(const AdvanceTick(1));
    expect(homeCarShare(with_), lessThan(homeCarShare(without)));
    expect(
      with_.fields.totalCarKmPerDay,
      lessThan(without.fields.totalCarKmPerDay),
    );
  });

  test('a cycle path takes cars off short trips', () {
    final without = _town();
    final with_ = _town();
    for (var y = 6; y < 10; y++) {
      with_.apply(PlaceTile(7, y, TileType.cyclePath));
    }
    with_.apply(const AdvanceTick(1));
    expect(homeCarShare(with_), lessThan(homeCarShare(without)));
  });

  test('cycling does not serve a trip past its competitive distance', () {
    // Every trip on a 16-tile map is under 2.3 km, so the cutoff cannot be
    // reached by making the map bigger. Shrink it below the shortest trip
    // instead: a route in reach must then stop helping.
    final shortRange = _withCommute({'cycleCompetitiveKm': 0.05});

    double homeShareWithPath(SimParams params) {
      final sim = _town(params);
      for (var y = 6; y < 10; y++) {
        sim.apply(PlaceTile(7, y, TileType.cyclePath));
      }
      sim.apply(const AdvanceTick(1));
      // The route is in reach either way; only its usefulness changes.
      expect(sim.fields.cycleAccess[sim.state.index(6, 8)], greaterThan(0));
      return homeCarShare(sim);
    }

    final baseline = _town(shortRange);
    baseline.apply(const AdvanceTick(1));
    final unshifted = homeCarShare(baseline);

    expect(
      homeShareWithPath(shortRange),
      closeTo(unshifted, 1e-9),
      reason: 'out of cycling range, a route in reach must change nothing',
    );
    expect(
      homeShareWithPath(SimParams.defaults()),
      lessThan(unshifted),
      reason: 'within range, the same route must move trips off the car',
    );
  });

  test('the shift never removes every car', () {
    final sim = _town();
    // Stops and routes over the whole neighbourhood.
    for (var y = 5; y < 11; y++) {
      sim.apply(PlaceTile(5, y, TileType.tramStop));
      sim.apply(PlaceTile(7, y, TileType.cyclePath));
      sim.apply(PlaceTile(11, y, TileType.tramStop));
    }
    sim.apply(const AdvanceTick(2));
    expect(sim.fields.totalCarKmPerDay, greaterThan(0));
    for (var i = 0; i < sim.state.cellCount; i++) {
      if (sim.state.population[i] <= 0) continue;
      // No cell may fall below the floor times its unshifted share.
      expect(sim.fields.carShare[i], greaterThan(0));
    }
  });

  test('a map with no stops and no routes is unchanged', () {
    final sim = _town();
    for (var i = 0; i < sim.state.cellCount; i++) {
      expect(sim.fields.transitAccess[i], 0);
      expect(sim.fields.cycleAccess[i], 0);
    }
  });
}
