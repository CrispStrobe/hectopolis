// SPDX-License-Identifier: AGPL-3.0-or-later
// Every built-in level must be solvable with three stars by a reasonable,
// hand-written plan within its time limit. If a model change breaks one of
// these, either the model or the level needs attention.
//
// The plans themselves live in `tool/level_plans.dart`, because
// `tool/learning_audit.dart` replays them too: a beat or a challenge a random
// player misses may just be hard, but one the worked solution misses is dead
// content.
import 'package:stadtbau_sim/stadtbau_sim.dart';
import 'package:test/test.dart';

import '../tool/level_plans.dart';

LevelProgress _play(String id, List<Move> moves, {int? months}) {
  final level = Level.byId(id)!;
  final sim = level.start();
  for (final (x, y, t) in moves) {
    final r = sim.apply(PlaceTile(x, y, t));
    expect(r.ok, isTrue, reason: '$id: place ${t.id} at ($x,$y): ${r.error}');
  }
  final limit = months ?? level.turnLimitMonths!;
  var best = level.evaluate(sim.indicators);
  for (var m = 0; m < limit; m++) {
    sim.apply(const AdvanceTick());
    final p = level.evaluate(sim.indicators);
    if (p.metCount > best.metCount) best = p;
    if (p.allMet) return p;
  }
  final ind = sim.indicators;
  final report = [
    for (var i = 0; i < level.goals.length; i++)
      '${level.goals[i].indicator?.name ?? level.goals[i].metric} '
          '${level.goals[i].current(ind).toStringAsFixed(0)}/${level.goals[i].min.toStringAsFixed(0)}'
  ].join(', ');
  fail('$id not solved within $limit months: $report (budget ${sim.state.budgetKEur.toStringAsFixed(0)})');
}

void main() {
  for (final id in plannedLevelIds) {
    test(id, () {
      final plan = planFor(id);
      expect(plan, isNotNull, reason: 'no plan for $id');
      expect(_play(id, plan!).stars, 3);
    });
  }

  test('every built-in level has a worked plan', () {
    for (final level in Level.builtIn()) {
      expect(
        plannedLevelIds,
        contains(level.id),
        reason:
            'level "${level.id}" ships without a plan, so nothing proves it '
            'is winnable',
      );
    }
  });
}
