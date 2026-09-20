// SPDX-License-Identifier: AGPL-3.0-or-later
// Calibration harness (task T-114): builds archetype maps, runs them for a
// few years and prints indicators and key raw values. Compare the output with
// the plausibility ranges in docs/model/calibration.md. Adjust coefficients
// only in data/params/tiles.json.
//
// Usage: dart run tool/calibrate.dart [--json]   (from packages/stadtbau_sim)
import 'dart:convert';

import 'package:stadtbau_sim/stadtbau_sim.dart';

typedef Builder = void Function(WorldState w);

/// The archetypes. Each is a 16×16 map; residents of pre-built housing start
/// at 90 % occupancy so that steady-state values are reached quickly.
final archetypes = <String, Builder>{
  'forest': (w) => _fill(w, TileType.forest),
  'meadow': (w) => _fill(w, TileType.meadow),
  'cropland': (w) => _fill(w, TileType.cropland),
  'village': (w) {
    _fill(w, TileType.cropland);
    _rect(w, 4, 4, 8, 8, TileType.meadow);
    _line(w, 0, 8, 15, 8, TileType.road);
    _rect(w, 5, 6, 6, 2, TileType.housingLow);
    _rect(w, 5, 9, 6, 2, TileType.housingLow);
    _rect(w, 11, 7, 1, 1, TileType.commercial);
    _rect(w, 4, 7, 1, 1, TileType.park);
    _rect(w, 12, 9, 2, 2, TileType.forest);
  },
  'suburb': (w) {
    _fill(w, TileType.meadow);
    _line(w, 0, 8, 15, 8, TileType.road);
    _line(w, 8, 0, 8, 15, TileType.road);
    _rect(w, 1, 1, 7, 7, TileType.housingLow);
    _rect(w, 9, 1, 6, 7, TileType.housingLow);
    _rect(w, 1, 9, 7, 6, TileType.housingLow);
    _rect(w, 9, 9, 3, 3, TileType.commercial);
    _rect(w, 12, 12, 3, 3, TileType.park);
  },
  'dense_quarter': (w) {
    _fill(w, TileType.housingHigh);
    _line(w, 0, 5, 15, 5, TileType.road);
    _line(w, 0, 10, 15, 10, TileType.road);
    _line(w, 5, 0, 5, 15, TileType.road);
    _line(w, 10, 0, 10, 15, TileType.road);
    _rect(w, 6, 6, 4, 4, TileType.park);
    _rect(w, 11, 11, 4, 4, TileType.commercial);
    _rect(w, 0, 0, 5, 5, TileType.commercial);
  },
  'industrial_park': (w) {
    _fill(w, TileType.meadow);
    _line(w, 0, 8, 15, 8, TileType.road);
    _rect(w, 2, 2, 12, 5, TileType.industry);
    _rect(w, 2, 10, 5, 4, TileType.housingLow);
    _rect(w, 9, 10, 5, 4, TileType.forest);
  },
  'mixed_town': (w) {
    _fill(w, TileType.meadow);
    _line(w, 0, 8, 15, 8, TileType.road);
    _line(w, 8, 0, 8, 15, TileType.road);
    _rect(w, 0, 0, 8, 8, TileType.forest);
    _rect(w, 9, 0, 7, 3, TileType.industry);
    _rect(w, 9, 4, 7, 4, TileType.housingHigh);
    _rect(w, 0, 9, 8, 7, TileType.housingLow);
    _rect(w, 9, 9, 3, 3, TileType.commercial);
    _rect(w, 12, 9, 4, 3, TileType.park);
    _rect(w, 9, 12, 7, 4, TileType.cropland);
    _rect(w, 3, 3, 2, 2, TileType.water);
  },
};

void main(List<String> args) {
  final params = SimParams.defaults();
  final asJson = args.contains('--json');
  final results = <String, Map<String, dynamic>>{};

  for (final entry in archetypes.entries) {
    final w = WorldState.empty(width: 16, height: 16, budgetKEur: params.economy.startBudgetKEur);
    entry.value(w);
    w.populateExisting(params);
    final sim = Simulation(state: w, params: params);
    sim.apply(const AdvanceTick(60));
    final ind = sim.indicators;
    final f = sim.fields;

    // Everything above is read at tick 60, which is a January: 60 is a whole
    // number of years and tick 0 is January. That is fine for the quantities
    // that do not move with the month, and wrong for the ones that do. ΔT at
    // the January snapshot is 0.18 K for the dense quarter against the 1.6 K
    // this file used to record from the season-free model — not a regression,
    // a reading taken in the coldest month. So the seasonal quantities are
    // swept over the following twelve months and reported as an annual mean
    // and a summer peak, which is the shape the plausibility ranges are in:
    // an urban heat island is a summer statement.
    final probe = sim.copy();
    var heatSum = 0.0;
    var heatPeak = 0.0;
    var peakMonth = 0;
    final recreation = <double>[];
    final climate = <double>[];
    for (var m = 1; m <= 12; m++) {
      probe.apply(const AdvanceTick());
      final pi = probe.indicators;
      heatSum += pi.meanHeatDeltaC;
      if (pi.meanHeatDeltaC > heatPeak) {
        heatPeak = pi.meanHeatDeltaC;
        peakMonth = probe.state.tick % 12;
      }
      recreation.add(pi.scores[Indicator.recreation]!);
      climate.add(pi.scores[Indicator.climate]!);
    }
    double meanOf(List<double> v) => v.reduce((a, b) => a + b) / v.length;

    // Resident-weighted noise exposure and share above the WA limit.
    var pop = 0.0;
    var above = 0.0;
    var maxNoise = 0.0;
    for (var i = 0; i < w.cellCount; i++) {
      final p = w.population[i];
      if (p <= 0) continue;
      pop += p;
      if (f.noiseDb[i] > params.noise.limitDayDb) above += p;
      if (f.noiseDb[i] > maxNoise) maxNoise = f.noiseDb[i];
    }
    var maxTraffic = 0.0;
    for (final t in f.traffic) {
      if (t > maxTraffic) maxTraffic = t;
    }

    results[entry.key] = {
      'population': ind.population.round(),
      'capacity': ind.housingCapacity.round(),
      'jobs': ind.jobsCapacity.round(),
      'budgetDeltaKEurMonth': ind.budgetDeltaKEur.toStringAsFixed(0),
      'meanNoiseDb': ind.meanNoiseDb.toStringAsFixed(1),
      'maxResidentNoiseDb': maxNoise.toStringAsFixed(1),
      'shareAbove55': pop > 0 ? (above / pop).toStringAsFixed(2) : '-',
      'meanAirIndex': ind.meanAirIndex.toStringAsFixed(0),
      'meanCommuteKm': ind.meanCommuteKm.toStringAsFixed(1),
      'carShare': ind.carShare.toStringAsFixed(2),
      'maxTraffic': maxTraffic.round(),
      'co2TonsPerYear': ind.co2TonsPerYear.round(),
      'meanRunoffMm': ind.meanRunoffMm.toStringAsFixed(2),
      'floodRiskCells': ind.floodRiskCells,
      'meanHeatDeltaC': ind.meanHeatDeltaC.toStringAsFixed(2),
      'heatDeltaCYearMean': (heatSum / 12).toStringAsFixed(2),
      'heatDeltaCSummerPeak': '${heatPeak.toStringAsFixed(2)} (month $peakMonth)',
      'recreationYearMean': meanOf(recreation).toStringAsFixed(0),
      'recreationSpread': '${recreation.reduce((a, b) => a < b ? a : b).toStringAsFixed(0)}'
          '–${recreation.reduce((a, b) => a > b ? a : b).toStringAsFixed(0)}',
      'climateYearMean': meanOf(climate).toStringAsFixed(0),
      'climateSpread': '${climate.reduce((a, b) => a < b ? a : b).toStringAsFixed(0)}'
          '–${climate.reduce((a, b) => a > b ? a : b).toStringAsFixed(0)}',
      'habitatConnectivity': ind.habitatConnectivity.toStringAsFixed(2),
      'scores': {for (final e in ind.scores.entries) e.key.name: e.value.round()},
    };
  }

  if (asJson) {
    print(const JsonEncoder.withIndent('  ').convert(results));
    return;
  }
  for (final e in results.entries) {
    print('== ${e.key}');
    for (final kv in e.value.entries) {
      print('  ${kv.key}: ${kv.value}');
    }
  }
}

void _fill(WorldState w, TileType t) {
  for (var i = 0; i < w.cellCount; i++) {
    w.tiles[i] = t;
  }
}

void _rect(WorldState w, int x0, int y0, int width, int height, TileType t) {
  for (var y = y0; y < y0 + height; y++) {
    for (var x = x0; x < x0 + width; x++) {
      if (w.inBounds(x, y)) w.tiles[w.index(x, y)] = t;
    }
  }
}

void _line(WorldState w, int x0, int y0, int x1, int y1, TileType t) {
  final dx = (x1 - x0).sign;
  final dy = (y1 - y0).sign;
  var x = x0;
  var y = y0;
  while (true) {
    if (w.inBounds(x, y)) w.tiles[w.index(x, y)] = t;
    if (x == x1 && y == y1) break;
    x += dx;
    y += dy;
  }
}
