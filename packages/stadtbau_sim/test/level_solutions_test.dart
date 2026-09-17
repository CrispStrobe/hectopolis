// SPDX-License-Identifier: AGPL-3.0-or-later
// Every built-in level must be solvable with three stars by a reasonable,
// hand-written plan within its time limit. If a model change breaks one of
// these, either the model or the level needs attention.
import 'package:stadtbau_sim/stadtbau_sim.dart';
import 'package:test/test.dart';

typedef Move = (int x, int y, TileType tile);

void _rect(List<Move> moves, int x0, int y0, int w, int h, TileType t) {
  for (var y = y0; y < y0 + h; y++) {
    for (var x = x0; x < x0 + w; x++) {
      moves.add((x, y, t));
    }
  }
}

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
  test('village', () {
    final m = <Move>[];
    _rect(m, 0, 7, 5, 2, TileType.housingLow); // 10 south of the road
    _rect(m, 7, 3, 5, 1, TileType.housingLow); // 5 north
    m.add((7, 2, TileType.housingLow));
    m.add((6, 6, TileType.commercial));
    m.add((5, 4, TileType.commercial));
    m.add((2, 6, TileType.park));
    m.add((9, 4, TileType.park));
    _rect(m, 0, 0, 4, 2, TileType.forest); // 8 forest joining the existing wood
    expect(_play('village', m).stars, 3);
  });

  test('noise', () {
    final m = <Move>[];
    _rect(m, 8, 6, 1, 4, TileType.road); // side road south from the through road
    _rect(m, 9, 6, 6, 2, TileType.forest); // 12-tile screen between road and homes
    _rect(m, 6, 6, 2, 1, TileType.forest); // 2 more west of the side road
    _rect(m, 9, 8, 4, 2, TileType.housingHigh); // 8 apartment blocks behind the screen
    _rect(m, 9, 10, 4, 2, TileType.housingLow); // 8 detached homes further south
    m.add((9, 12, TileType.commercial));
    _rect(m, 13, 8, 1, 3, TileType.park);
    expect(_play('noise', m).stars, 3);
  });

  test('habitat', () {
    final m = <Move>[];
    // Diagonal forest corridor from the north-west wood to the south-east wood.
    for (var i = 4; i <= 11; i++) {
      m.add((i, i, TileType.forest));
    }
    // Turn every remaining field into extensive meadow.
    final level = Level.byId('habitat')!;
    for (var y = 0; y < level.height; y++) {
      for (var x = 0; x < level.width; x++) {
        if (level.map[y * level.width + x] == TileType.cropland && !(x == y && x >= 4 && x <= 11)) {
          m.add((x, y, TileType.meadow));
        }
      }
    }
    m.add((1, 8, TileType.park));
    m.add((6, 8, TileType.park));
    m.add((0, 9, TileType.water));
    m.add((7, 9, TileType.water));
    expect(_play('habitat', m).stars, 3);
  });

  test('budget', () {
    final m = <Move>[];
    // Tear down the oversized middle road and the parks nobody uses, then add
    // homes and workplaces along the remaining border roads.
    _rect(m, 2, 7, 12, 1, TileType.meadow);
    for (final (x, y) in [(6, 2), (12, 2), (8, 6), (8, 8), (6, 13), (11, 13)]) {
      m.add((x, y, TileType.meadow));
    }
    _rect(m, 3, 2, 3, 1, TileType.housingHigh);
    m.add((3, 8, TileType.housingHigh));
    _rect(m, 9, 3, 2, 1, TileType.housingLow);
    _rect(m, 12, 5, 2, 1, TileType.commercial);
    m.add((12, 11, TileType.commercial));
    expect(_play('budget', m).stars, 3);
  });

  test('quarter', () {
    final m = <Move>[];
    _rect(m, 1, 7, 14, 1, TileType.road); // east-west spine from the access road
    _rect(m, 7, 1, 1, 6, TileType.road); // north branch
    _rect(m, 2, 3, 4, 2, TileType.housingHigh);
    _rect(m, 9, 3, 4, 2, TileType.housingHigh);
    _rect(m, 2, 10, 4, 2, TileType.housingLow);
    _rect(m, 9, 10, 4, 2, TileType.housingLow);
    _rect(m, 8, 5, 4, 1, TileType.commercial);
    _rect(m, 3, 5, 4, 1, TileType.commercial);
    _rect(m, 2, 9, 4, 1, TileType.park);
    _rect(m, 9, 9, 2, 1, TileType.park);
    _rect(m, 13, 0, 3, 16, TileType.forest);
    _rect(m, 0, 0, 13, 2, TileType.forest);
    expect(_play('quarter', m).stars, 3);
  });

  // The generated level (T-303): a town that already exists, where the plan
  // is what to take away rather than what to add. The lever is not the
  // biotope value of what is planted but the habitat threat of what is
  // removed -- replacing the industrial estate and the sealed cells next to
  // homes beats growing one large connected wood, which scores far better on
  // biodiversity alone (49 against 39) and then fails recreation.
  test('tuebingen', () {
    final level = Level.byId('tuebingen')!;
    final m = <Move>[];
    var forest = 40, park = 40, wetland = 15, tram = 6, cycle = 30;
    final w = level.width;
    TileType at(int x, int y) => level.map[y * w + x];
    bool beside(int x, int y, TileType t) => [
          if (x > 0) at(x - 1, y),
          if (x < w - 1) at(x + 1, y),
          if (y > 0) at(x, y - 1),
          if (y < level.height - 1) at(x, y + 1),
        ].contains(t);

    for (var y = 0; y < level.height; y++) {
      for (var x = 0; x < w; x++) {
        final t = at(x, y);
        if (t == TileType.water) continue;
        if (wetland > 0 &&
            beside(x, y, TileType.water) &&
            (t == TileType.road || t == TileType.industry ||
                t == TileType.meadow || t == TileType.cropland)) {
          m.add((x, y, TileType.wetland));
          wetland--;
        }
      }
    }
    for (final (source, planted) in [
      (TileType.industry, TileType.forest),
      (TileType.commercial, TileType.park),
      (TileType.cropland, TileType.forest),
      (TileType.meadow, TileType.forest),
    ]) {
      for (var y = 0; y < level.height; y++) {
        for (var x = 0; x < w; x++) {
          if (at(x, y) != source) continue;
          if (m.any((mv) => mv.$1 == x && mv.$2 == y)) continue;
          if (planted == TileType.forest && forest > 0) {
            m.add((x, y, TileType.forest));
            forest--;
          } else if (planted == TileType.park && park > 0) {
            m.add((x, y, TileType.park));
            park--;
          }
        }
      }
    }
    for (var y = 0; y < level.height; y += 3) {
      for (var x = 0; x < w; x++) {
        if (at(x, y) != TileType.road) continue;
        if (m.any((mv) => mv.$1 == x && mv.$2 == y)) continue;
        if (tram > 0) {
          m.add((x, y, TileType.tramStop));
          tram--;
        } else if (cycle > 0) {
          m.add((x, y, TileType.cyclePath));
          cycle--;
        }
      }
    }
    expect(_play('tuebingen', m).stars, 3);
  });
}
