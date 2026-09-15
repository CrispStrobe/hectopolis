// SPDX-License-Identifier: AGPL-3.0-or-later
// Measures a full tick and a placement forecast on a dense 24×24 map
// (task T-115).
// Usage: dart run benchmark/tick_benchmark.dart
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
  sim.apply(const AdvanceTick(3)); // warm-up
  const n = 20;
  final sw = Stopwatch()..start();
  sim.apply(const AdvanceTick(n));
  sw.stop();
  print('24x24 dense map: ${(sw.elapsedMicroseconds / n / 1000).toStringAsFixed(1)} ms per tick '
      '(${sim.indicators.population.round()} residents, ${sim.fields.jobsCapacity.round()} jobs)');

  // What the UI does on hover when placement forecasts are on: snapshot the
  // simulation and place the tile on the snapshot.
  for (var i = 0; i < 3; i++) {
    sim.copy().apply(const PlaceTile(13, 7, TileType.park));
  }
  const m = 10;
  final forecast = Stopwatch()..start();
  for (var i = 0; i < m; i++) {
    sim.copy().apply(const PlaceTile(13, 7, TileType.park));
  }
  forecast.stop();
  print('24x24 placement forecast: '
      '${(forecast.elapsedMicroseconds / m / 1000).toStringAsFixed(1)} ms');
}
