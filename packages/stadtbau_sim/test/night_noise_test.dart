// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:stadtbau_sim/stadtbau_sim.dart';
import 'package:test/test.dart';

void main() {
  final params = SimParams.defaults();

  test('night is quieter than day wherever anything is heard', () {
    final sim = Simulation.sandbox();
    for (var y = 0; y < 16; y++) {
      sim.apply(PlaceTile(8, y, TileType.road));
    }
    sim.apply(const AdvanceTick(3));
    final f = sim.fields;
    var compared = 0;
    for (var i = 0; i < sim.state.cellCount; i++) {
      // Cells that only ever hear the background sit at the background in
      // both, so they say nothing about the night reduction.
      if (f.noiseDb[i] <= params.noise.backgroundDb + 0.01) continue;
      expect(f.noiseNightDb[i], lessThan(f.noiseDb[i]), reason: 'cell $i');
      expect(
        f.noiseNightDb[i],
        greaterThanOrEqualTo(params.noise.backgroundDb - 1e-9),
        reason: 'night must not fall below the rural background',
      );
      compared++;
    }
    expect(compared, greaterThan(20));
  });

  test('a road drops by its own night reduction', () {
    final sim = Simulation.sandbox();
    for (var y = 0; y < 16; y++) {
      sim.apply(PlaceTile(8, y, TileType.road));
    }
    sim.apply(const AdvanceTick(3));
    // On the road itself the road dominates, so the gap between day and night
    // should be close to the parameter -- not exactly it, because the rural
    // background is summed in on both.
    final onRoad = sim.state.index(8, 8);
    final gap =
        sim.fields.noiseDb[onRoad] - sim.fields.noiseNightDb[onRoad];
    expect(
      gap,
      closeTo(params.tile(TileType.road).noiseNightReductionDb.value, 0.5),
    );
  });

  test('the night guideline share counts residents, not cells', () {
    final sim = Simulation.sandbox();
    for (var y = 0; y < 16; y++) {
      sim.apply(PlaceTile(8, y, TileType.road));
    }
    // One home hard against the road, one far away.
    sim.apply(const PlaceTile(9, 8, TileType.housingHigh));
    sim.apply(const PlaceTile(0, 0, TileType.housingHigh));
    sim.apply(const AdvanceTick(24));
    final ind = sim.indicators;
    expect(ind.meanNightNoiseDb, greaterThan(params.noise.backgroundDb));
    expect(ind.meanNightNoiseDb, lessThan(ind.meanNoiseDb));
    expect(ind.shareAboveNightGuideline, inInclusiveRange(0, 1));
    expect(
      ind.shareAboveNightGuideline,
      greaterThanOrEqualTo(ind.shareAboveNightHighRisk),
      reason: 'the 55 dB group is a subset of the 45 dB group',
    );
  });

  test('a quiet map exceeds no guideline', () {
    final sim = Simulation.sandbox();
    sim.apply(const PlaceTile(4, 4, TileType.housingLow));
    sim.apply(const AdvanceTick(12));
    expect(sim.indicators.shareAboveNightGuideline, 0);
    expect(sim.indicators.shareAboveNightHighRisk, 0);
  });
}
