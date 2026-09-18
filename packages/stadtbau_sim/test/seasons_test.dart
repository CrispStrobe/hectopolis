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

  /// A dense quarter of apartment blocks with roads, optionally with a park
  /// in the middle, run to [tick].
  Simulation quarter(SimParams params, {required bool withPark, required int tick}) {
    final w = WorldState.empty(width: 16, height: 16, budgetKEur: 1e9);
    for (var i = 0; i < w.cellCount; i++) {
      w.tiles[i] = TileType.housingHigh;
    }
    for (var k = 0; k < 16; k++) {
      w.tiles[w.index(k, 5)] = TileType.road;
      w.tiles[w.index(k, 10)] = TileType.road;
      w.tiles[w.index(5, k)] = TileType.road;
      w.tiles[w.index(10, k)] = TileType.road;
    }
    if (withPark) {
      for (var y = 6; y < 10; y++) {
        for (var x = 6; x < 10; x++) {
          w.tiles[w.index(x, y)] = TileType.park;
        }
      }
    }
    w.populateExisting(params);
    final sim = Simulation(state: w, params: params);
    sim.apply(AdvanceTick(tick));
    return sim;
  }

  test('the heat ceiling reported with the field is the month that made it', () {
    for (final tick in [60, 63, 66, 69]) {
      final sim = quarter(params, withPark: true, tick: tick);
      expect(
        sim.fields.uhiMaxNowC,
        closeTo(params.heat.uhiMaxC * params.seasons.heatAt(sim.state.tick), 1e-12),
        reason: 'tick $tick',
      );
    }
  });

  test('a summer score still tells a park from no park', () {
    // Scores divide ΔT by the month's ceiling, not by the annual uhiMaxC.
    // Dividing by the annual figure clamped every July score to zero: a
    // dense quarter reaches 4.1 K against a 3.0 K parameter, so sixteen
    // hectares of park moved the climate score by nothing at all.
    for (final month in [0, 6]) {
      final bare = quarter(params, withPark: false, tick: 60 + month).indicators;
      final green = quarter(params, withPark: true, tick: 60 + month).indicators;
      expect(green.meanHeatDeltaC, lessThan(bare.meanHeatDeltaC), reason: 'month $month');
      for (final indicator in [Indicator.climate, Indicator.recreation]) {
        expect(
          green.scores[indicator]!,
          greaterThan(bare.scores[indicator]! + 0.5),
          reason: '$indicator in month $month',
        );
      }
    }
  });

  test('July heat costs a score without pinning it to zero', () {
    final january = quarter(params, withPark: false, tick: 60).indicators;
    final july = quarter(params, withPark: false, tick: 66).indicators;
    // Summer is worse: the open-country reference cools harder in the growing
    // season, so the built quarter falls further behind it.
    expect(july.scores[Indicator.climate]!, lessThan(january.scores[Indicator.climate]!));
    // But it has not bottomed out, which is what leaves room to improve it.
    expect(july.scores[Indicator.recreation]!, greaterThan(0.0));
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
