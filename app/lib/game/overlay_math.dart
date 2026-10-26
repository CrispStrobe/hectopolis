// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:stadtbau_sim/stadtbau_sim.dart';

import 'game_types.dart';

// Pure functions from simulation state to overlay values, shared by the
// placement preview, the build impact card and the map colouring. Nothing
// here holds state, so it is tested without a controller or a widget tree.

/// Score change of every indicator from [before] to [after].
Map<Indicator, double> indicatorDeltas(Simulation before, Simulation after) => {
  for (final indicator in Indicator.values)
    indicator:
        after.indicators.score(indicator) - before.indicators.score(indicator),
};

/// The overlay that best shows what placing (or removing) [tile] does to its
/// surroundings.
MapOverlay previewOverlayFor(TileType tile) => switch (tile) {
  TileType.forest || TileType.meadow => MapOverlay.habitat,
  TileType.water || TileType.park || TileType.wetland => MapOverlay.green,
  TileType.cyclePath => MapOverlay.green,
  TileType.cropland => MapOverlay.heat,
  TileType.housingLow || TileType.housingHigh => MapOverlay.attractiveness,
  TileType.commercial || TileType.mixedUse => MapOverlay.retail,
  TileType.school => MapOverlay.jobs,
  // Dark modules are the one thing a solar field does to its surroundings
  // that the map can show; the CO2 it displaces has no overlay.
  TileType.solarField => MapOverlay.heat,
  TileType.industry => MapOverlay.air,
  TileType.road || TileType.tramStop => MapOverlay.noise,
};

/// Smallest field change, in the field's own unit, that marks a cell as
/// affected.
double previewThreshold(MapOverlay overlay) => switch (overlay) {
  MapOverlay.noise => 0.15,
  MapOverlay.air || MapOverlay.traffic => 0.1,
  _ => 0.005,
};

double fieldDifference(
  MapOverlay overlay,
  Simulation before,
  Simulation after,
  int i,
) {
  final a = before.fields;
  final b = after.fields;
  return switch (overlay) {
    MapOverlay.noise => (b.noiseDb[i] - a.noiseDb[i]).abs(),
    MapOverlay.air => (b.airIndex[i] - a.airIndex[i]).abs(),
    MapOverlay.heat => (b.heatDeltaC[i] - a.heatDeltaC[i]).abs(),
    MapOverlay.green => (b.greenAccess[i] - a.greenAccess[i]).abs(),
    MapOverlay.retail => (b.retailAccess[i] - a.retailAccess[i]).abs(),
    MapOverlay.jobs => (b.jobAccess[i] - a.jobAccess[i]).abs(),
    MapOverlay.habitat => (b.habitatQuality[i] - a.habitatQuality[i]).abs(),
    MapOverlay.traffic => (b.traffic[i] - a.traffic[i]).abs(),
    MapOverlay.attractiveness =>
      (b.attractiveness[i] - a.attractiveness[i]).abs(),
    MapOverlay.none => 0,
  };
}

/// [cell] plus every cell whose [overlay] field moved by more than
/// [previewThreshold] between [before] and [after].
Set<int> affectedCells(
  MapOverlay overlay,
  Simulation before,
  Simulation after,
  int cell,
) {
  final threshold = previewThreshold(overlay);
  return {
    cell,
    for (var i = 0; i < before.state.cellCount; i++)
      if (fieldDifference(overlay, before, after, i) > threshold) i,
  };
}

/// Value of [overlay] at [cell], normalised to 0–1 for colouring.
double normalOverlayValue(MapOverlay overlay, Simulation source, int cell) {
  final f = source.fields;
  switch (overlay) {
    case MapOverlay.none:
      return 0;
    case MapOverlay.noise:
      return ((f.noiseDb[cell] - 35) / 40).clamp(0, 1);
    case MapOverlay.air:
      return (1 - f.airIndex[cell] / 100).clamp(0, 1);
    case MapOverlay.heat:
      return f.uhiMaxNowC <= 0
          ? 0.0
          : (f.heatDeltaC[cell] / f.uhiMaxNowC).clamp(0.0, 1.0);
    case MapOverlay.green:
      return f.greenAccess[cell];
    case MapOverlay.retail:
      return f.retailAccess[cell];
    case MapOverlay.jobs:
      return f.jobAccess[cell];
    case MapOverlay.habitat:
      return f.habitatQuality[cell];
    case MapOverlay.traffic:
      return (f.traffic[cell] / 20000).clamp(0, 1);
    case MapOverlay.attractiveness:
      return f.attractiveness[cell];
  }
}

/// The normalised value at which [overlay] crosses its guideline (55 dB
/// noise, 2 °C heat island, half access), or null when it has none.
double? overlayThresholdFor(MapOverlay overlay, Simulation sim) =>
    switch (overlay) {
      MapOverlay.noise => (55 - 35) / 40,
      MapOverlay.heat =>
        sim.fields.uhiMaxNowC <= 0 ? null : 2 / sim.fields.uhiMaxNowC,
      MapOverlay.green ||
      MapOverlay.retail ||
      MapOverlay.jobs ||
      MapOverlay.habitat ||
      MapOverlay.attractiveness => 0.5,
      MapOverlay.traffic => 0.5,
      MapOverlay.none || MapOverlay.air => null,
    };

/// Whether high overlay values are "bad" (drawn warm) or "good" (drawn cool).
bool overlayHighIsBadFor(MapOverlay value) => switch (value) {
  MapOverlay.noise || MapOverlay.heat || MapOverlay.traffic => true,
  _ => false,
};

/// Whether a [type] tile moves the [overlay] value of the cells around it.
///
/// Read off the parameters each field is computed from, not listed by hand:
/// a hand-written list here once disagreed with a second one in the map
/// painter on half the overlays, and both had missed the tiles added since.
/// `game_controller_test.dart` checks this against what the model does when
/// a tile is placed.
bool isCausalSource(MapOverlay overlay, TileType type, Simulation sim) {
  final p = sim.params;
  final tile = p.tile(type);
  bool noise(TileParams t) => t.noiseEmissionDb.value > 0;
  bool air(TileParams t) => t.airEmission.value > 0;
  // Green access is the best green weight in reach; meadow is the ground
  // everything starts on, so only greener land lifts it.
  bool green(TileParams t) =>
      t.greenWeight.value > p.tile(TileType.terrain).greenWeight.value;
  bool retail(TileParams t) => t.retailFloorM2.value > 0;
  // Built land with jobs. A farm or a park has a job or two per hectare too,
  // which the model counts, but a line from a home to the nearest field
  // would not say where the jobs are.
  bool jobs(TileParams t) => t.category.isBuilt && t.jobsPerHa.value > 0;
  // A neighbour can only cool a cell, never heat it: heat.dart takes the
  // larger of a cell's own cooling capacity and that of the green patches
  // around it. Next to a built-up block all green land cools; marked is the
  // land that cools better than the meadow the map starts as, which is what
  // a player can change.
  bool heat(TileParams t) {
    final hp = p.heat;
    final growth = p.seasons.growthAt(sim.state.tick);
    double capacity(TileParams x) =>
        hp.shadeWeight * x.shade.value +
        hp.albedoWeight * x.albedo.value +
        hp.etiWeight * x.eti.value * growth;
    return t.category.isGreen &&
        capacity(t) > capacity(p.tile(TileType.terrain));
  }

  return switch (overlay) {
    MapOverlay.noise => noise(tile),
    MapOverlay.air => air(tile),
    MapOverlay.heat => heat(tile),
    MapOverlay.green => green(tile),
    MapOverlay.retail => retail(tile),
    MapOverlay.jobs => jobs(tile),
    MapOverlay.habitat => p.habitat.threats.containsKey(type),
    // Commuters start at homes and end at workplaces; the road only carries
    // them.
    MapOverlay.traffic => tile.residentsPerHa.value > 0 || jobs(tile),
    // Attractiveness is a weighted sum of the other readings (stocks.dart).
    MapOverlay.attractiveness =>
      noise(tile) ||
          air(tile) ||
          green(tile) ||
          retail(tile) ||
          jobs(tile) ||
          heat(tile),
    MapOverlay.none => false,
  };
}

/// The overlay the goal hint opens first, so the player sees the problem on
/// the map before being handed a tile.
MapOverlay guidanceOverlay(GoalGuidance guidance) {
  return switch (guidance.indicator) {
    Indicator.biodiversity => MapOverlay.habitat,
    Indicator.air => MapOverlay.air,
    Indicator.noise => MapOverlay.noise,
    Indicator.housing => MapOverlay.attractiveness,
    Indicator.flood => MapOverlay.heat,
    Indicator.economy || Indicator.budget => MapOverlay.jobs,
    Indicator.shopping => MapOverlay.retail,
    Indicator.recreation => MapOverlay.green,
    Indicator.commuting => MapOverlay.traffic,
    Indicator.climate => MapOverlay.heat,
    null => switch (guidance.metric) {
      'population' => MapOverlay.attractiveness,
      'jobs' || 'budgetKEur' => MapOverlay.jobs,
      _ => MapOverlay.none,
    },
  };
}
