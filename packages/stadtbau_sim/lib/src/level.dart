// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'generated/default_levels.dart';
import 'generated/default_params.dart';
import 'indicators.dart';
import 'params.dart';
import 'simulation.dart';
import 'tile_type.dart';
import 'world.dart';

/// ASCII legend used by level maps (one character per cell).
const Map<String, TileType> levelMapLegend = {
  '.': TileType.meadow,
  'c': TileType.cropland,
  'f': TileType.forest,
  'w': TileType.water,
  'p': TileType.park,
  'h': TileType.housingLow,
  'H': TileType.housingHigh,
  'C': TileType.commercial,
  'I': TileType.industry,
  'r': TileType.road,
};

/// A goal on an indicator score (0–100) or a raw metric.
class LevelGoal {
  const LevelGoal({this.indicator, this.metric, required this.min});

  final Indicator? indicator;

  /// Raw metric name: `population`, `jobs`, `budgetKEur`.
  final String? metric;
  final double min;

  double current(IndicatorSnapshot s) {
    if (indicator != null) return s.score(indicator!);
    return switch (metric) {
      'population' => s.population,
      'jobs' => s.jobsCapacity,
      'budgetKEur' => s.budgetKEur,
      _ => 0,
    };
  }

  bool met(IndicatorSnapshot s) => current(s) >= min;

  static LevelGoal fromJson(Map<String, dynamic> json) {
    final ind = json['indicator'] as String?;
    return LevelGoal(
      indicator: ind == null ? null : Indicator.values.byName(ind),
      metric: json['metric'] as String?,
      min: (json['min'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    if (indicator != null) 'indicator': indicator!.name,
    if (metric != null) 'metric': metric,
    'min': min,
  };
}

/// How much scaffolding a mission expects from the player.
enum MissionTier { starter, guided, explorer }

/// Optional learning interactions enabled for one mission. Keeping these in
/// level data prevents every scenario from accumulating every teaching tool.
enum MissionFeature { prediction, causalView, experiment, debrief, challenges }

/// Educational design attached to a level. Text is localized by stable ids in
/// the app; the simulation package only owns structure and progression data.
class MissionLearning {
  const MissionLearning({
    required this.tier,
    required this.concepts,
    required this.features,
    this.predictionId,
    this.challengeIds = const [],
  });

  final MissionTier tier;
  final List<String> concepts;
  final Set<MissionFeature> features;
  final String? predictionId;
  final List<String> challengeIds;

  bool has(MissionFeature feature) => features.contains(feature);

  static MissionLearning fromJson(Map<String, dynamic> json) => MissionLearning(
    tier: MissionTier.values.byName(
      json['tier'] as String? ?? MissionTier.guided.name,
    ),
    concepts: (json['concepts'] as List<dynamic>? ?? const []).cast<String>(),
    features: {
      for (final id
          in (json['features'] as List<dynamic>? ?? const []).cast<String>())
        MissionFeature.values.byName(id),
    },
    predictionId: json['predictionId'] as String?,
    challengeIds: (json['challenges'] as List<dynamic>? ?? const [])
        .cast<String>(),
  );
}

/// A playable scenario: map, budget, allowed tiles, goals, time limit.
class Level {
  Level({
    required this.id,
    required this.width,
    required this.height,
    required this.budgetKEur,
    required this.map,
    required this.tiles,
    required this.goals,
    this.turnLimitMonths,
    this.populate = true,
    this.paramOverrides,
    this.learning,
  });

  final String id;
  final int width;
  final int height;
  final double budgetKEur;

  /// Row-major tile types of the initial map.
  final List<TileType> map;

  /// Allowed tile types with remaining counts (null = unlimited).
  final Map<TileType, int?> tiles;
  final List<LevelGoal> goals;

  /// Months until the level is evaluated; null = open-ended.
  final int? turnLimitMonths;

  /// Whether pre-built housing starts inhabited.
  final bool populate;

  /// JSON patch merged over `data/params/tiles.json` for this level.
  final Map<String, dynamic>? paramOverrides;

  /// Optional, mission-specific learning tools and concepts.
  final MissionLearning? learning;

  static Level fromJson(Map<String, dynamic> json) {
    final rows = (json['map'] as List<dynamic>).cast<String>();
    final height = rows.length;
    final width = rows.first.length;
    final map = <TileType>[];
    for (final row in rows) {
      if (row.length != width) {
        throw FormatException('level ${json['id']}: ragged map row');
      }
      for (final ch in row.split('')) {
        final t = levelMapLegend[ch];
        if (t == null) {
          throw FormatException('level ${json['id']}: unknown map char "$ch"');
        }
        map.add(t);
      }
    }
    final tilesJson = (json['tiles'] as Map<String, dynamic>);
    return Level(
      id: json['id'] as String,
      width: width,
      height: height,
      budgetKEur: (json['budgetKEur'] as num).toDouble(),
      map: map,
      tiles: {
        for (final e in tilesJson.entries)
          TileType.fromId(e.key): (e.value as num?)?.toInt(),
      },
      goals: [
        for (final g in (json['goals'] as List<dynamic>))
          LevelGoal.fromJson(g as Map<String, dynamic>),
      ],
      turnLimitMonths: (json['turnLimitMonths'] as num?)?.toInt(),
      populate: json['populate'] as bool? ?? true,
      paramOverrides: json['paramOverrides'] as Map<String, dynamic>?,
      learning: json['learning'] == null
          ? null
          : MissionLearning.fromJson(json['learning'] as Map<String, dynamic>),
    );
  }

  /// Parameters for this level: the defaults with [paramOverrides] merged in.
  SimParams params() {
    final overrides = paramOverrides;
    if (overrides == null) return SimParams.defaults();
    final base = jsonDecode(defaultParamsJson) as Map<String, dynamic>;
    _deepMerge(base, overrides);
    return SimParams.fromJson(base);
  }

  /// A fresh simulation for this level.
  Simulation start({int seed = 1}) {
    final p = params();
    final w = WorldState.empty(
      width: width,
      height: height,
      budgetKEur: budgetKEur,
      seed: seed,
    );
    for (var i = 0; i < map.length; i++) {
      w.tiles[i] = map[i];
    }
    if (populate) w.populateExisting(p);
    return Simulation(state: w, params: p, tileBudget: TileBudget(tiles));
  }

  /// A simulation for this level restored from a saved state.
  Simulation resume(WorldState state) =>
      Simulation(state: state, params: params(), tileBudget: budgetFor(state));

  /// Remaining tile counts given a state (placed tiles are subtracted).
  TileBudget budgetFor(WorldState state) {
    final remaining = Map<TileType, int?>.of(tiles);
    for (var i = 0; i < state.cellCount; i++) {
      final placed = state.tiles[i];
      if (placed == map[i]) continue;
      final r = remaining[placed];
      if (r != null) remaining[placed] = r - 1;
      final orig = remaining[map[i]];
      if (orig != null) remaining[map[i]] = orig + 1;
    }
    return TileBudget(remaining);
  }

  /// Progress against the goals.
  LevelProgress evaluate(IndicatorSnapshot s) {
    final met = [for (final g in goals) g.met(s)];
    final limit = turnLimitMonths;
    return LevelProgress(
      goalsMet: met,
      monthsLeft: limit == null ? null : (limit - s.tick).clamp(0, limit),
    );
  }

  static List<Level>? _builtIn;

  /// Levels shipped with the game (`data/levels/*.json`).
  static List<Level> builtIn() => _builtIn ??= [
    for (final j in defaultLevelsJson)
      fromJson(jsonDecode(j) as Map<String, dynamic>),
  ];

  static Level? byId(String id) {
    for (final l in builtIn()) {
      if (l.id == id) return l;
    }
    return null;
  }
}

class LevelProgress {
  const LevelProgress({required this.goalsMet, required this.monthsLeft});

  final List<bool> goalsMet;
  final int? monthsLeft;

  bool get allMet => goalsMet.every((m) => m);
  int get metCount => goalsMet.where((m) => m).length;
  bool get timeUp => monthsLeft == 0;

  /// 0–3 stars: all goals = 3, at least two thirds = 2, at least one third = 1.
  int get stars {
    if (goalsMet.isEmpty) return 0;
    final ratio = metCount / goalsMet.length;
    if (ratio >= 1) return 3;
    if (ratio >= 2 / 3) return 2;
    if (ratio >= 1 / 3) return 1;
    return 0;
  }
}

void _deepMerge(Map<String, dynamic> base, Map<String, dynamic> patch) {
  for (final e in patch.entries) {
    final b = base[e.key];
    final v = e.value;
    if (b is Map<String, dynamic> && v is Map<String, dynamic>) {
      _deepMerge(b, v);
    } else {
      base[e.key] = v;
    }
  }
}
