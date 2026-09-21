// SPDX-License-Identifier: AGPL-3.0-or-later
// A worked, three-star plan for every built-in level.
//
// These live in `tool/` rather than inside the test that asserts them because
// two things need them and both are dev-only: `test/level_solutions_test.dart`
// proves each level is winnable, and `tool/learning_audit.dart` replays the
// same plans to ask whether the teaching content a competent player meets is
// actually reachable. A beat or a challenge that a random player misses may
// just be hard; one the worked solution misses is dead content.
import 'package:stadtbau_sim/stadtbau_sim.dart';

typedef Move = (int x, int y, TileType tile);

void rect(List<Move> moves, int x0, int y0, int w, int h, TileType t) {
  for (var y = y0; y < y0 + h; y++) {
    for (var x = x0; x < x0 + w; x++) {
      moves.add((x, y, t));
    }
  }
}

/// Level ids that have a worked plan, in play order.
const plannedLevelIds = <String>[
  'village',
  'noise',
  'habitat',
  'budget',
  'quarter',
  'tuebingen',
];

/// Variants of the worked plan that exist to prove an optional medal can be
/// earned, keyed by the challenge id they earn.
///
/// They are derived from the plan rather than written out, so they cannot fall
/// out of step with it: each is the plan with something left out.
///
/// A constraint medal only means something if the constrained solution costs
/// something, and until 2026-09-21 neither of these did. Measured at the
/// moment the level is actually won — which is where the game banks medals,
/// not the end of the term — the noise plan without its side road solved three
/// months later but scored 100 for quiet instead of 88 and saved 1 200 k€,
/// and the habitat plan without its ponds was identical in every respect and
/// 400 k€ cheaper. The first costs time, so it stays a ban. The second cost
/// nothing, so it is now a reserve target priced above what the plan leaves.
Map<String, List<Move>> medalPlansFor(String levelId) {
  final plan = planFor(levelId);
  if (plan == null) return const {};
  return switch (levelId) {
    'noise' => {
      'noise_no_roads': [
        for (final move in plan)
          if (move.$3 != TileType.road) move,
      ],
    },
    'habitat' => {
      // Both the ponds and the parks, because that is what the medal is
      // priced at: dropping either alone leaves 1 266 or 1 806 k€ against a
      // 2 000 k€ target, and dropping both leaves 2 214.
      'habitat_lean': [
        for (final move in plan)
          if (move.$3 != TileType.water && move.$3 != TileType.park) move,
      ],
    },
    _ => const {},
  };
}

/// The plan for [levelId], or null if none is written.
List<Move>? planFor(String levelId) => switch (levelId) {
  'village' => () {
    final m = <Move>[];
    rect(m, 0, 7, 5, 2, TileType.housingLow); // 10 south of the road
    rect(m, 7, 3, 5, 1, TileType.housingLow); // 5 north
    m.add((7, 2, TileType.housingLow));
    m.add((6, 6, TileType.commercial));
    m.add((5, 4, TileType.commercial));
    m.add((2, 6, TileType.park));
    m.add((9, 4, TileType.park));
    rect(m, 0, 0, 4, 2, TileType.forest); // 8 forest joining the existing wood
    return m;
  }(),
  'noise' => () {
    final m = <Move>[];
    rect(m, 8, 6, 1, 4, TileType.road); // side road south from the through road
    rect(m, 9, 6, 6, 2, TileType.forest); // 12-tile screen between road and homes
    rect(m, 6, 6, 2, 1, TileType.forest); // 2 more west of the side road
    rect(m, 9, 8, 4, 2, TileType.housingHigh); // 8 apartment blocks behind the screen
    rect(m, 9, 10, 4, 2, TileType.housingLow); // 8 detached homes further south
    m.add((9, 12, TileType.commercial));
    rect(m, 13, 8, 1, 3, TileType.park);
    return m;
  }(),
  'habitat' => () {
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
    return m;
  }(),
  'budget' => () {
    final m = <Move>[];
    // Tear down the oversized middle road and the parks nobody uses, then add
    // homes and workplaces along the remaining border roads.
    rect(m, 2, 7, 12, 1, TileType.meadow);
    for (final (x, y) in [(6, 2), (12, 2), (8, 6), (8, 8), (6, 13), (11, 13)]) {
      m.add((x, y, TileType.meadow));
    }
    rect(m, 3, 2, 3, 1, TileType.housingHigh);
    m.add((3, 8, TileType.housingHigh));
    rect(m, 9, 3, 2, 1, TileType.housingLow);
    rect(m, 12, 5, 2, 1, TileType.commercial);
    m.add((12, 11, TileType.commercial));
    return m;
  }(),
  'quarter' => () {
    final m = <Move>[];
    rect(m, 1, 7, 14, 1, TileType.road); // east-west spine from the access road
    rect(m, 7, 1, 1, 6, TileType.road); // north branch
    rect(m, 2, 3, 4, 2, TileType.housingHigh);
    rect(m, 9, 3, 4, 2, TileType.housingHigh);
    rect(m, 2, 10, 4, 2, TileType.housingLow);
    rect(m, 9, 10, 4, 2, TileType.housingLow);
    rect(m, 8, 5, 4, 1, TileType.commercial);
    rect(m, 3, 5, 4, 1, TileType.commercial);
    rect(m, 2, 9, 4, 1, TileType.park);
    rect(m, 9, 9, 2, 1, TileType.park);
    rect(m, 13, 0, 3, 16, TileType.forest);
    rect(m, 0, 0, 13, 2, TileType.forest);
    return m;
  }(),
  // The generated level (T-303): a town that already exists, where the plan
  // is what to take away rather than what to add. The lever is not the
  // biotope value of what is planted but the habitat threat of what is
  // removed -- replacing the industrial estate and the sealed cells next to
  // homes beats growing one large connected wood, which scores far better on
  // biodiversity alone (49 against 39) and then fails recreation.
  'tuebingen' => () {
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
    return m;
  }(),
  _ => null,
};
