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

  test('every mission stages its teaching beats', () {
    // A mission may carry concepts without beats: `tuebingen` opts into the
    // learning notebook, the causal view and the debrief, which reuse copy
    // that already exists, while its authored beats are still to be written.
    // Declaring beat ids before their copy exists would be worse than having
    // none — the ICU select would silently render the generic wording, which
    // is what tool/learning_audit.dart exists to catch.
    for (final level in Level.builtIn()) {
      final learning = level.learning;
      if (learning == null) continue;
      expect(learning.concepts, isNotEmpty, reason: '${level.id} concepts');
      final ids = {for (final b in learning.beats) b.id};
      expect(ids.length, learning.beats.length, reason: '${level.id} duplicate');
      // A beat with no trigger at all would fire before the player has done
      // anything, which is what the briefing is for.
      for (final beat in learning.beats) {
        expect(
          beat.afterMonths != null ||
              beat.afterTilesPlaced != null ||
              beat.afterGoalsMet != null ||
              beat.whenIndicatorBelow.isNotEmpty,
          isTrue,
          reason: '${level.id}/${beat.id} has no trigger',
        );
      }
    }
  });

  test('beats wait for the player to get far enough', () {
    final level = Level.byId('village')!;
    final sim = level.start();
    final beat = MissionBeat(id: 'x', afterTilesPlaced: 2, afterMonths: 3);
    LevelProgress progress() => level.evaluate(sim.indicators);
    expect(beat.isReached(level, sim, progress()), isFalse);

    // Placing tiles alone is not enough while the month trigger is unmet.
    var placed = 0;
    for (var i = 0; placed < 2 && i < level.map.length; i++) {
      if (level.map[i] == TileType.terrain || level.map[i] == TileType.meadow) {
        final r = sim.apply(
          PlaceTile(i % level.width, i ~/ level.width, TileType.housingLow),
        );
        if (r.ok) placed++;
      }
    }
    expect(placed, 2);
    expect(beat.isReached(level, sim, progress()), isFalse);

    sim.apply(const AdvanceTick(3));
    expect(beat.isReached(level, sim, progress()), isTrue);
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
    expect(noise.challenges.first.maxNewTiles[TileType.road], 0);
    expect(noise.challenges.last.maxMonths, 48);

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

  group('T-303 generated levels', () {
    test('every tile type has a legend character', () {
      // A tile with no character is a tile no level can ever contain, and
      // nothing else in the codebase notices: the six added by T-502 were
      // unreachable from a level file until T-303 needed them. TileType.index
      // order is irrelevant here, only coverage.
      expect(levelMapLegendIsComplete, isTrue,
          reason: 'missing: '
              '${TileType.values.where((t) => !levelMapChar.containsKey(t)).map((t) => t.id).join(", ")}');
      expect(levelMapChar.length, TileType.values.length);
    });

    test('a level built from open data carries its source notice', () {
      // CC BY 4.0 obliges us to name the source and to say the data was
      // changed. If the field is dropped the level still loads and the
      // obligation is silently broken, so it is asserted.
      final generated = Level.builtIn()
          .where((l) => l.attribution != null)
          .toList();
      expect(generated, isNotEmpty,
          reason: 'the tuebingen level should carry an attribution');
      for (final l in generated) {
        expect(l.attribution, contains('BKG'));
        expect(l.attribution, contains('CC BY 4.0'));
        expect(l.attribution!.toLowerCase(), contains('sampled'),
            reason: 'the notice must say the data was modified');
      }
    });

    test('a level without external data needs no notice', () {
      expect(Level.byId('village')!.attribution, isNull);
    });
  });
}
