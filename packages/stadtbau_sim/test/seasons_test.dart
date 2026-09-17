// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:stadtbau_sim/src/generated/default_params.dart';
import 'package:stadtbau_sim/stadtbau_sim.dart';
import 'package:test/test.dart';

SimParams _withAmplitude(double amplitude) {
  final json = jsonDecode(defaultParamsJson) as Map<String, dynamic>;
  (json['seasons'] as Map<String, dynamic>)['amplitude'] = {
    'value': amplitude,
    'source': 'test',
  };
  return SimParams.fromJson(json);
}

/// Heat on a sealed cell after [months], with a hot neighbourhood around it.
double _heatAfter(SimParams params, int months) {
  final w = WorldState.empty(width: 9, height: 9, budgetKEur: 1e9);
  final sim = Simulation(state: w, params: params);
  for (var x = 2; x < 7; x++) {
    for (var y = 2; y < 7; y++) {
      sim.apply(PlaceTile(x, y, TileType.industry));
    }
  }
  if (months > 0) sim.apply(AdvanceTick(months));
  return sim.fields.heatDeltaC[sim.state.index(4, 4)];
}

void main() {
  final params = SimParams.defaults();

  test('both factor series average exactly one over the year', () {
    for (final monthly in [params.seasons.growth, params.seasons.heat]) {
      expect(monthly.length, 12);
      final mean = monthly.reduce((a, b) => a + b) / monthly.length;
      // The sources claim an annual mean of 1.0, so the numbers must hold to
      // it: a season redistributes within a year, it does not add warmth.
      expect(mean, closeTo(1.0, 1e-9));
    }
  });

  test('the cycle repeats every twelve months and starts in January', () {
    expect(params.seasons.growthAt(0), params.seasons.growth.first);
    expect(params.seasons.growthAt(12), params.seasons.growthAt(0));
    expect(params.seasons.growthAt(18), params.seasons.growthAt(6));
    expect(params.seasons.heatAt(25), params.seasons.heatAt(1));
  });

  test('summer is hotter than winter on the same city', () {
    // Tick 0 is January; +6 is July.
    final january = _heatAfter(params, 12);
    final july = _heatAfter(params, 18);
    expect(july, greaterThan(january));
  });

  test('amplitude zero reproduces the season-free model', () {
    final off = _withAmplitude(0);
    expect(off.seasons.active, isFalse);
    for (var tick = 0; tick < 24; tick++) {
      expect(off.seasons.growthAt(tick), 1.0);
      expect(off.seasons.heatAt(tick), 1.0);
    }
    // And the field it feeds stops moving with the month.
    expect(_heatAfter(off, 12), closeTo(_heatAfter(off, 18), 1e-12));
  });

  test('amplitude flattens towards the mean, not towards zero', () {
    final half = _withAmplitude(0.5);
    for (final tick in [0, 3, 6, 9]) {
      final full = params.seasons.growthAt(tick);
      final damped = half.seasons.growthAt(tick);
      expect(damped, closeTo(1 + (full - 1) * 0.5, 1e-9));
      // Half amplitude sits between the full swing and no season at all.
      expect((damped - 1).abs(), lessThan((full - 1).abs() + 1e-9));
    }
  });
}
