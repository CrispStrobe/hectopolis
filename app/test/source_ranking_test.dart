// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:stadtbau/game/game_controller.dart';
import 'package:stadtbau/game/overlay_math.dart';
import 'package:stadtbau/game/source_ranking.dart';
import 'package:stadtbau_sim/stadtbau_sim.dart';

// The source lines are ranked by how much each source moves the selected
// cell, not by distance. The case that motivated it: a block of flats whose
// nearest job sources are the houses next door, while nearly all of its job
// access comes from an industrial estate further off.

/// Industry in the top-left corner, flats at (5..7, 7), houses at (10..11, 9).
Simulation _town() {
  final sim = Simulation.sandbox(width: 16, height: 16);
  for (var y = 0; y < 4; y++) {
    for (var x = 0; x < 4; x++) {
      sim.apply(PlaceTile(x, y, TileType.industry));
    }
  }
  for (final x in [5, 6, 7]) {
    sim.apply(PlaceTile(x, 7, TileType.housingHigh));
  }
  for (final x in [10, 11]) {
    sim.apply(PlaceTile(x, 9, TileType.housingLow));
  }
  return sim;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('removing a tile is a counterfactual, not a move', () {
    final sim = _town();
    final budget = sim.state.budgetKEur;
    final cell = sim.state.index(0, 0);
    final without = withoutTile(sim, cell);
    expect(without.state.tiles[cell], TileType.meadow);
    expect(sim.state.tiles[cell], TileType.industry);
    expect(without.state.budgetKEur, budget);
  });

  test('job access is traced to the industry, not the houses next door', () {
    // Job access at the flats is capped at 1.0, so removing any one tile
    // changes nothing there; tracing the field before its cap still finds
    // the estate.
    final c = GameController(size: 16);
    addTearDown(c.dispose);
    c.sim = _town();
    final flats = c.sim.state.index(6, 7);
    expect(c.sim.fields.jobAccess[flats], 1.0);
    c.setOverlay(MapOverlay.jobs);
    c.select(flats);
    final shown = c.selectedCausalSourceCells;
    expect(shown, hasLength(shownSourceCount));
    expect(shown.first ~/ 16, lessThan(4), reason: 'an industry row');
    expect(shown.first % 16, lessThan(4), reason: 'an industry column');
  });

  test('a capped reading still names its sources', () {
    final c = GameController(size: 16);
    addTearDown(c.dispose);
    c.sim = _town();
    c.setOverlay(MapOverlay.jobs);
    c.select(c.sim.state.index(6, 7));
    // Synchronous: no ranking runs in the background for a traced field.
    expect(c.selectedCausalSourceCells, isNotEmpty);
    expect(
      identical(c.selectedCausalSourceCells, c.selectedCausalSourceCells),
      isTrue,
      reason: 'cached for the frame',
    );
  });

  test('weighed sources come out strongest first', () {
    final sim = _town();
    final receiver = sim.state.index(6, 7);
    final candidates = [
      for (var i = 0; i < sim.state.cellCount; i++)
        if (i != receiver &&
            isCausalSource(MapOverlay.attractiveness, sim.state.tiles[i], sim))
          i,
    ].take(sourceCandidateCount).toList();
    final ranking = SourceRanking(
      sim: sim,
      overlay: MapOverlay.attractiveness,
      receiver: receiver,
      candidates: candidates,
      revision: 0,
    );
    // Until it is weighed, the nearest are shown in the order given.
    expect(ranking.shown, candidates.take(shownSourceCount));
    while (ranking.step()) {}
    double effect(int cell) => fieldDifference(
      MapOverlay.attractiveness,
      sim,
      withoutTile(sim, cell),
      receiver,
    );
    final effects = ranking.shown.map(effect).toList();
    for (var k = 1; k < effects.length; k++) {
      expect(effects[k - 1], greaterThanOrEqualTo(effects[k]));
    }
    final rest = candidates.where((c) => !ranking.shown.contains(c));
    for (final c in rest) {
      expect(effect(c), lessThanOrEqualTo(effects.last));
    }
  });

  test('traffic is weighed in the background and then redrawn', () async {
    final c = GameController(size: 16);
    addTearDown(c.dispose);
    c.sim = _town()..apply(const AdvanceTick(6));
    c.setOverlay(MapOverlay.traffic);
    c.select(c.sim.state.index(6, 7));
    var redraws = 0;
    c.addListener(() => redraws++);
    c.selectedCausalSourceCells;
    for (var i = 0; i < 100 && redraws == 0; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(redraws, 1);
  });

  test('a new selection drops the weighing in progress', () async {
    final c = GameController(size: 16);
    addTearDown(c.dispose);
    c.sim = _town();
    c.setOverlay(MapOverlay.attractiveness);
    c.select(c.sim.state.index(6, 7));
    c.selectedCausalSourceCells;
    c.select(c.sim.state.index(10, 9));
    c.selectedCausalSourceCells;
    var redraws = 0;
    c.addListener(() => redraws++);
    for (var i = 0; i < 100 && redraws == 0; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    // Only the weighing for the current selection reports back.
    expect(redraws, 1);
  });
}
