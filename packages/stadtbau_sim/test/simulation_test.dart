// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';
import 'dart:math' as math;

import 'package:stadtbau_sim/stadtbau_sim.dart';
import 'package:test/test.dart';

void main() {
  final params = SimParams.defaults();

  group('params', () {
    test('every tile type has parameters with sources', () {
      for (final t in TileType.values) {
        final tp = params.tile(t);
        expect(tp.biotopeValue.value, inInclusiveRange(0, 24), reason: t.id);
        expect(tp.biotopeValue.source, isNotEmpty, reason: t.id);
        expect(tp.sealing.value, inInclusiveRange(0, 1), reason: t.id);
      }
    });

    test('mode share bins are ordered and sum to one', () {
      var last = 0.0;
      for (final b in params.commute.modeShareBins) {
        expect(b.maxKm, greaterThan(last));
        expect(b.walk + b.bike + b.car, closeTo(1, 1e-9));
        last = b.maxKm;
      }
    });
  });

  group('world', () {
    test('json round trip preserves state and hash', () {
      final sim = Simulation.sandbox();
      sim.apply(const PlaceTile(3, 3, TileType.housingHigh));
      sim.apply(const PlaceTile(4, 3, TileType.road));
      sim.apply(const AdvanceTick(3));
      final json = jsonEncode(sim.state.toJson());
      final restored = WorldState.fromJson(
        jsonDecode(json) as Map<String, dynamic>,
      );
      expect(restored.hash(), sim.state.hash());
      expect(restored.tick, 3);
      expect(restored.tileAt(3, 3), TileType.housingHigh);
    });

    test('rng is deterministic and 32-bit safe', () {
      final a = Rng(42);
      final b = Rng(42);
      for (var i = 0; i < 100; i++) {
        final v = a.nextUint32();
        expect(v, b.nextUint32());
        expect(v, inInclusiveRange(0, 0xFFFFFFFF));
      }
    });
  });

  group('noise', () {
    test('road noise decays with distance and forest attenuates', () {
      final sim = Simulation.sandbox();
      for (var y = 0; y < 16; y++) {
        sim.apply(PlaceTile(0, y, TileType.road));
      }
      final f = sim.fields;
      final near = f.noiseDb[sim.state.index(1, 8)];
      final far = f.noiseDb[sim.state.index(6, 8)];
      expect(near, greaterThan(far));
      expect(near, greaterThan(45));
      expect(far, lessThan(near - 5));

      final open = f.noiseDb[sim.state.index(3, 8)];
      for (var y = 0; y < 16; y++) {
        sim.apply(PlaceTile(1, y, TileType.forest));
        sim.apply(PlaceTile(2, y, TileType.forest));
      }
      final shielded = sim.fields.noiseDb[sim.state.index(3, 8)];
      expect(shielded, lessThan(open - 2));
    });

    test('industry next to housing exceeds the WA daytime limit', () {
      final sim = Simulation.sandbox();
      sim.apply(const PlaceTile(5, 5, TileType.industry));
      sim.apply(const PlaceTile(6, 5, TileType.housingLow));
      final level = sim.fields.noiseDb[sim.state.index(6, 5)];
      expect(level, greaterThan(params.noise.limitDayDb));
    });
  });

  group('explain', () {
    test('noise and air breakdowns are consistent with the fields', () {
      final sim = Simulation.sandbox();
      for (var y = 0; y < 16; y++) {
        sim.apply(PlaceTile(4, y, TileType.road));
      }
      sim.apply(const PlaceTile(8, 8, TileType.industry));
      final noise = sim.explainNoise(6, 8);
      expect(noise.first.type, anyOf(TileType.road, TileType.industry));
      var energy = math.pow(10, params.noise.backgroundDb / 10).toDouble();
      for (final c in noise) {
        energy += math.pow(10, c.value / 10);
      }
      expect(
        10 * math.log(energy) / math.ln10,
        closeTo(sim.fields.noiseDb[sim.state.index(6, 8)], 0.01),
      );
      final air = sim.explainAir(6, 8);
      var sum = 0.0;
      for (final c in air) {
        sum += c.value;
      }
      expect(
        sum,
        closeTo(sim.fields.airConcentration[sim.state.index(6, 8)], 1e-9),
      );
    });
  });

  group('indicators', () {
    test('all-forest map is rich in biodiversity and has no housing', () {
      final sim = Simulation.sandbox();
      for (var y = 0; y < 16; y++) {
        for (var x = 0; x < 16; x++) {
          sim.state.tiles[sim.state.index(x, y)] = TileType.forest;
          sim.state.tileAge[sim.state.index(x, y)] = 600;
        }
      }
      sim.recompute();
      expect(sim.indicators.score(Indicator.biodiversity), greaterThan(80));
      expect(sim.indicators.score(Indicator.housing), 0);
      expect(sim.indicators.score(Indicator.air), greaterThan(95));
    });

    test('fragmenting a forest with roads lowers biodiversity', () {
      final sim = Simulation.sandbox();
      for (var i = 0; i < sim.state.cellCount; i++) {
        sim.state.tiles[i] = TileType.forest;
        sim.state.tileAge[i] = 600;
      }
      sim.recompute();
      final before = sim.indicators.score(Indicator.biodiversity);
      for (var x = 0; x < 16; x++) {
        sim.state.tiles[sim.state.index(x, 8)] = TileType.road;
      }
      for (var y = 0; y < 16; y++) {
        sim.state.tiles[sim.state.index(8, y)] = TileType.road;
      }
      sim.recompute();
      expect(
        sim.indicators.score(Indicator.biodiversity),
        lessThan(before - 10),
      );
    });

    test('a mixed quarter fills with residents and earns money', () {
      final sim = Simulation(
        state: WorldState.empty(width: 16, height: 16, budgetKEur: 100000),
      );
      for (var x = 2; x < 14; x++) {
        sim.apply(PlaceTile(x, 8, TileType.road));
      }
      for (var x = 3; x < 13; x++) {
        sim.apply(PlaceTile(x, 7, TileType.housingHigh));
        sim.apply(PlaceTile(x, 9, TileType.housingLow));
      }
      sim.apply(const PlaceTile(13, 7, TileType.commercial));
      sim.apply(const PlaceTile(13, 9, TileType.commercial));
      sim.apply(const PlaceTile(2, 7, TileType.park));
      sim.apply(const PlaceTile(2, 9, TileType.industry));
      final budgetAfterBuild = sim.state.budgetKEur;
      sim.apply(const AdvanceTick(36));
      final ind = sim.indicators;
      expect(ind.population, greaterThan(1000));
      expect(ind.score(Indicator.shopping), greaterThan(50));
      expect(ind.score(Indicator.recreation), greaterThan(30));
      expect(sim.state.budgetKEur, greaterThan(budgetAfterBuild));
      expect(ind.meanCommuteKm, lessThan(10));
    });
  });

  group('commands', () {
    test('budget and tile limits are enforced', () {
      final sim = Simulation(
        state: WorldState.empty(width: 8, height: 8, budgetKEur: 350),
        tileBudget: TileBudget({TileType.road: 1, TileType.park: null}),
      );
      expect(
        sim.apply(const PlaceTile(0, 0, TileType.industry)).error,
        CommandError.tileNotAllowed,
      );
      expect(
        sim.apply(const PlaceTile(0, 0, TileType.park)).error,
        CommandError.insufficientBudget,
      );
      expect(sim.apply(const PlaceTile(0, 0, TileType.road)).ok, isTrue);
      expect(
        sim.apply(const PlaceTile(1, 0, TileType.road)).error,
        CommandError.tileExhausted,
      );
      expect(sim.apply(const RemoveTile(0, 0)).ok, isTrue);
      expect(sim.tileBudget.remaining(TileType.road), 1);
      expect(
        sim.apply(const PlaceTile(9, 9, TileType.park)).error,
        CommandError.outOfBounds,
      );
    });

    test('replaying the command log reproduces the state hash', () {
      final initial = WorldState.empty(
        width: 12,
        height: 12,
        budgetKEur: 8000,
        seed: 7,
      );
      final sim = Simulation(state: initial.copy());
      sim.apply(const PlaceTile(1, 1, TileType.road));
      sim.apply(const PlaceTile(2, 1, TileType.housingHigh));
      sim.apply(const AdvanceTick(5));
      sim.apply(const PlaceTile(3, 1, TileType.commercial));
      sim.apply(const AdvanceTick(7));
      sim.apply(const RemoveTile(1, 1));
      sim.apply(const AdvanceTick(2));
      final replayed = Simulation.replay(initial, sim.log);
      expect(replayed.state.hash(), sim.state.hash());
      expect(
        replayed.indicators.population,
        closeTo(sim.indicators.population, 1e-9),
      );
    });
  });
}
