// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:stadtbau_sim/stadtbau_sim.dart';
import 'package:test/test.dart';

void main() {
  test('built-in levels parse, start and evaluate', () {
    final levels = Level.builtIn();
    expect(levels.length, greaterThanOrEqualTo(5));
    for (final l in levels) {
      final sim = l.start();
      expect(sim.state.cellCount, l.width * l.height, reason: l.id);
      expect(l.goals, isNotEmpty, reason: l.id);
      final progress = l.evaluate(sim.indicators);
      expect(progress.goalsMet.length, l.goals.length);
      for (final t in l.tiles.keys) {
        expect(sim.tileBudget.allowed(t), isTrue, reason: '${l.id} ${t.id}');
      }
    }
  });

  test('param overrides change the level simulation', () {
    final noise = Level.byId('noise')!;
    expect(noise.params().noise.baselineThroughTraffic, 14000);
    expect(SimParams.defaults().noise.baselineThroughTraffic, 2000);
  });

  test('missions opt into age-appropriate learning tools', () {
    final village = Level.byId('village')!.learning!;
    expect(village.tier, MissionTier.starter);
    expect(village.concepts, contains('access'));
    expect(village.has(MissionFeature.prediction), isTrue);
    expect(village.has(MissionFeature.causalView), isFalse);

    final noise = Level.byId('noise')!.learning!;
    expect(noise.predictionId, 'noise_homes');
    expect(noise.has(MissionFeature.experiment), isTrue);

    final quarter = Level.byId('quarter')!.learning!;
    expect(quarter.tier, MissionTier.explorer);
    expect(quarter.has(MissionFeature.challenges), isTrue);
  });

  test('tile budget is reconstructed from a saved state', () {
    final village = Level.byId('village')!;
    final sim = village.start();
    expect(sim.apply(const PlaceTile(0, 0, TileType.housingLow)).ok, isTrue);
    expect(sim.apply(const PlaceTile(1, 0, TileType.housingLow)).ok, isTrue);
    final resumed = village.resume(sim.state.copy());
    expect(resumed.tileBudget.remaining(TileType.housingLow), 14);
    expect(resumed.tileBudget.remaining(TileType.meadow), isNull);
  });

  test('stars follow the share of goals met', () {
    expect(
      const LevelProgress(goalsMet: [true, true, true], monthsLeft: 3).stars,
      3,
    );
    expect(
      const LevelProgress(goalsMet: [true, true, false], monthsLeft: 0).stars,
      2,
    );
    expect(
      const LevelProgress(goalsMet: [true, false, false], monthsLeft: 0).stars,
      1,
    );
    expect(
      const LevelProgress(goalsMet: [false, false, false], monthsLeft: 0).stars,
      0,
    );
  });
}
