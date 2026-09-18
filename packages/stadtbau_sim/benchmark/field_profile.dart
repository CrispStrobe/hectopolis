// SPDX-License-Identifier: AGPL-3.0-or-later
// Where a tick's time goes, stage by stage, on a dense 24x24 map (task T-115).
//
//   dart run benchmark/field_profile.dart
//
// tick_benchmark.dart gives the total; this says which field to look at if the
// total is too big. It reports the *minimum* over many batches, because the
// machine this project is developed on runs at load 10 and a mean is mostly
// other people's work.
import 'package:stadtbau_sim/src/model/access.dart';
import 'package:stadtbau_sim/src/model/air.dart' as air_model;
import 'package:stadtbau_sim/src/model/commute.dart';
import 'package:stadtbau_sim/src/model/habitat.dart';
import 'package:stadtbau_sim/src/model/heat.dart';
import 'package:stadtbau_sim/src/model/noise.dart' as noise_model;
import 'package:stadtbau_sim/src/model/stocks.dart';
import 'package:stadtbau_sim/src/model/water.dart';
import 'package:stadtbau_sim/stadtbau_sim.dart';

void main() {
  final params = SimParams.defaults();
  final w = WorldState.empty(width: 24, height: 24, budgetKEur: 1e6);
  for (var y = 0; y < 24; y++) {
    for (var x = 0; x < 24; x++) {
      final i = w.index(x, y);
      if (x % 6 == 0 || y % 6 == 0) {
        w.tiles[i] = TileType.road;
      } else if (x < 12) {
        w.tiles[i] = y < 12 ? TileType.housingHigh : TileType.housingLow;
      } else {
        w.tiles[i] = y < 12 ? TileType.commercial : TileType.industry;
      }
    }
  }
  w.populateExisting(params);
  final sim = Simulation(state: w, params: params);
  sim.apply(const AdvanceTick(3));
  final f = sim.fields;
  final s = sim.state;

  final stages = <String, void Function()>{
    'commute': () => computeCommute(s, params, f),
    'noise': () => noise_model.computeNoise(s, params, f),
    'air': () => air_model.computeAir(s, params, f),
    'heat': () => computeHeat(s, params, f),
    'access': () => computeAccess(s, params, f),
    'habitat': () => computeHabitat(s, params, f),
    'water': () => computeWater(s, params, f),
    'attractiveness': () => computeAttractiveness(s, params, f),
    'indicators': () => computeIndicators(s, params, f, budgetDeltaKEur: 0, co2TonsPerYear: 0),
  };
  // Minimum over many batches: this box runs at load 10+, so the mean is
  // mostly other people's work. The minimum is the closest thing to the cost
  // of the code itself.
  const n = 20;
  const batches = 25;
  var total = 0.0;
  for (final e in stages.entries) {
    for (var i = 0; i < 20; i++) {
      e.value();
    }
    var best = double.infinity;
    for (var b = 0; b < batches; b++) {
      final sw = Stopwatch()..start();
      for (var i = 0; i < n; i++) {
        e.value();
      }
      sw.stop();
      final ms = sw.elapsedMicroseconds / n / 1000;
      if (ms < best) best = ms;
    }
    total += best;
    print('${e.key.padRight(16)} ${best.toStringAsFixed(3)} ms');
  }
  print('${"sum".padRight(16)} ${total.toStringAsFixed(2)} ms');
}
