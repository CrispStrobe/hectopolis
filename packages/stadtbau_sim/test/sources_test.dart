// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:math' as math;

import 'package:stadtbau_sim/stadtbau_sim.dart';
import 'package:test/test.dart';

// Simulation.sources must be the field taken apart, not a second model of
// it: on every cell of every shipped level, putting the sources back together
// with the field's own formula has to give the stored value.

void main() {
  final worlds = [
    for (final level in Level.builtIn())
      (level.id, level.start()..apply(const AdvanceTick(24))),
    // A summer month too, when the heat island and the cooling are largest.
    for (final level in Level.builtIn())
      ('${level.id}@july', level.start()..apply(const AdvanceTick(30))),
  ];

  void everyCell(
    void Function(String id, Simulation sim, int x, int y, int i) check,
  ) {
    for (final (id, sim) in worlds) {
      for (var y = 0; y < sim.state.height; y++) {
        for (var x = 0; x < sim.state.width; x++) {
          check(id, sim, x, y, sim.state.index(x, y));
        }
      }
    }
  }

  double sum(Map<int, double> m) => m.values.fold(0.0, (a, b) => a + b);
  double best(Map<int, double> m) => m.values.fold(0.0, math.max);

  test('jobs: the capped sum over job cells is the job access', () {
    everyCell((id, sim, x, y, i) {
      final ref = sim.params.access.jobReferenceJobs;
      final rebuilt = (sum(sim.sources(SourceField.jobs, x, y)) / ref).clamp(
        0.0,
        1.0,
      );
      expect(
        rebuilt,
        closeTo(sim.fields.jobAccess[i], 1e-9),
        reason: '$id ($x, $y)',
      );
    });
  });

  test('retail: the capped Huff sum is the retail access', () {
    everyCell((id, sim, x, y, i) {
      final ref = sim.params.access.retailReferenceSupply;
      final rebuilt = (sum(sim.sources(SourceField.retail, x, y)) / ref).clamp(
        0.0,
        1.0,
      );
      expect(
        rebuilt,
        closeTo(sim.fields.retailAccess[i], 1e-9),
        reason: '$id ($x, $y)',
      );
    });
  });

  test('green: the best source plus the variety bonus is the green access', () {
    everyCell((id, sim, x, y, i) {
      final ap = sim.params.access;
      final sources = sim.sources(SourceField.green, x, y);
      final others = sources.keys.where((s) => s != i).length;
      final bonus = others >= ap.greenVarietyMinTiles
          ? ap.greenVarietyBonus
          : 0.0;
      final rebuilt = (best(sources) + bonus).clamp(0.0, 1.0);
      expect(
        rebuilt,
        closeTo(sim.fields.greenAccess[i], 1e-9),
        reason: '$id ($x, $y)',
      );
    });
  });

  test('habitat: the capped threat sum is the degradation', () {
    everyCell((id, sim, x, y, i) {
      final sources = sim.sources(SourceField.habitat, x, y);
      if (sim.fields.habitatQuality[i] <= 0 && sources.isEmpty) return;
      final rebuilt = (sum(sources) / 4).clamp(0.0, 1.0);
      expect(
        rebuilt,
        closeTo(sim.fields.habitatThreat[i], 1e-9),
        reason: '$id ($x, $y)',
      );
    });
  });

  test('heat: the strongest cooling in reach sets the heat island', () {
    everyCell((id, sim, x, y, i) {
      final p = sim.params;
      final hp = p.heat;
      final growth = p.seasons.growthAt(sim.state.tick);
      double capacity(TileParams t) =>
          hp.shadeWeight * t.shade.value +
          hp.albedoWeight * t.albedo.value +
          hp.etiWeight * t.eti.value * growth;
      final ccRef = capacity(p.tile(TileType.terrain));
      final ccMin = TileType.values
          .map((t) => capacity(p.tile(t)))
          .fold(ccRef, math.min);
      final span = math.max(1e-6, ccRef - ccMin);
      final hm = math.max(
        sim.fields.coolingCapacity[i],
        best(sim.sources(SourceField.heat, x, y)),
      );
      final rebuilt =
          sim.fields.uhiMaxNowC * ((ccRef - hm) / span).clamp(0.0, 1.0);
      expect(
        rebuilt,
        closeTo(sim.fields.heatDeltaC[i], 1e-9),
        reason: '$id ($x, $y)',
      );
    });
  });

  test('noise: the energetic sum over the background is the level', () {
    var worst = 0.0;
    everyCell((id, sim, x, y, i) {
      final background = math
          .pow(10, sim.params.noise.backgroundDb / 10)
          .toDouble();
      final rebuilt =
          10 *
          math.log(background + sum(sim.sources(SourceField.noise, x, y))) /
          math.ln10;
      worst = math.max(worst, (rebuilt - sim.fields.noiseDb[i]).abs());
    });
    // computeNoise prunes a pair by its unscreened level and the breakdown by
    // its screened one, so a few faint, heavily screened sources differ.
    expect(worst, lessThan(0.05));
  });

  test('air: a cell has sources exactly when it has pollution', () {
    everyCell((id, sim, x, y, i) {
      final sources = sim.sources(SourceField.air, x, y);
      expect(
        sources.isNotEmpty,
        sim.fields.airConcentration[i] > 0,
        reason: '$id ($x, $y)',
      );
    });
  });
}
