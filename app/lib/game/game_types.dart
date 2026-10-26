// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:stadtbau_sim/stadtbau_sim.dart';

/// Colour overlays the player can toggle on the map.
enum MapOverlay {
  none,
  noise,
  air,
  heat,
  green,
  retail,
  jobs,
  habitat,
  traffic,
  attractiveness,
}

/// Read-only result of applying a prospective tile placement to a copy of the
/// current simulation. The renderer uses this for the ghost tile, affected
/// cells and score deltas; the authoritative simulation is never mutated.
class PlacementPreview {
  const PlacementPreview({
    required this.cell,
    required this.tile,
    required this.costKEur,
    required this.error,
    required this.indicatorDeltas,
    required this.affectedCells,
    required this.affectedOverlay,
  });

  final int cell;
  final TileType tile;
  final double? costKEur;
  final CommandError? error;
  final Map<Indicator, double> indicatorDeltas;
  final Set<int> affectedCells;
  final MapOverlay affectedOverlay;

  bool get isValid => error == null;
}

class BuildImpact {
  const BuildImpact({
    required this.cell,
    required this.tile,
    required this.removed,
    required this.costKEur,
    required this.indicatorDeltas,
    required this.affectedCells,
    required this.affectedOverlay,
    required this.createdAtMs,
  });

  final int cell;
  final TileType tile;
  final bool removed;
  final double costKEur;
  final Map<Indicator, double> indicatorDeltas;
  final Set<int> affectedCells;
  final MapOverlay affectedOverlay;
  final int createdAtMs;
}

class IndicatorHistorySample {
  const IndicatorHistorySample({required this.tick, required this.scores});

  final int tick;
  final Map<Indicator, double> scores;
}

class GoalGuidance {
  const GoalGuidance({
    required this.indicator,
    required this.metric,
    required this.tile,
  });

  final Indicator? indicator;
  final String? metric;
  final TileType? tile;
}
