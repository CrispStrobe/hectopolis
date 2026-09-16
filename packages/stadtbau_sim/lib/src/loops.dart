// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:math' as math;

import 'fields.dart';
import 'geometry.dart';
import 'indicators.dart';
import 'params.dart';
import 'tile_type.dart';
import 'world.dart';

/// The feedback loops the model is built around (PLAN §4.6, docs/model/loops.md).
///
/// Each one already exists in the simulation; this names them so the game can
/// show which is currently doing the most to the town.
enum CausalLoop {
  /// People arrive, drive, and make the place they arrived at worse.
  crowding,

  /// Residents and jobs pay for the town, which pays for more of both.
  taxBase,

  /// Jobs with no homes near them are filled from outside, by car.
  inCommuting,

  /// Building cuts habitat into pieces that support less than their area.
  fragmentation,

  /// Nature placed today pays out over years, not months.
  regrowth,
}

/// Whether a loop amplifies a change or pushes back against it.
enum LoopPolarity { reinforcing, balancing }

/// How strongly one loop is acting right now.
class LoopActivity {
  const LoopActivity({
    required this.loop,
    required this.polarity,
    required this.strength,
    required this.nodes,
  });

  final CausalLoop loop;
  final LoopPolarity polarity;

  /// 0–1. Comparable between loops only as "which is loudest"; each is a
  /// different quantity, so the number is a reading, not a score.
  final double strength;

  /// The chain the loop runs through, as ids the app localises.
  final List<String> nodes;
}

/// Read every loop off the current state, strongest first.
///
/// Each strength is a quantity the model already computes, not a new formula
/// invented for the diagram — see docs/model/loops.md for what each one is and
/// why it stands for its loop.
List<LoopActivity> computeLoops(
  WorldState w,
  SimParams p,
  Fields f,
  IndicatorSnapshot indicators,
) {
  final activities = [
    LoopActivity(
      loop: CausalLoop.crowding,
      polarity: LoopPolarity.balancing,
      strength: _crowding(w, p, f),
      nodes: const ['population', 'traffic', 'pollution', 'attractiveness'],
    ),
    LoopActivity(
      loop: CausalLoop.taxBase,
      polarity: LoopPolarity.reinforcing,
      strength: _taxBase(f),
      nodes: const ['population', 'revenue', 'budget', 'building'],
    ),
    LoopActivity(
      loop: CausalLoop.inCommuting,
      polarity: LoopPolarity.balancing,
      strength: _inCommuting(f),
      nodes: const ['jobs', 'inCommuters', 'traffic', 'pollution'],
    ),
    LoopActivity(
      loop: CausalLoop.fragmentation,
      polarity: LoopPolarity.balancing,
      strength: _fragmentation(w, p, f),
      nodes: const ['building', 'fragmentation', 'habitatThreat', 'biodiversity'],
    ),
    LoopActivity(
      loop: CausalLoop.regrowth,
      polarity: LoopPolarity.reinforcing,
      strength: _regrowth(w, p),
      nodes: const ['nature', 'maturity', 'biodiversity'],
    ),
  ]..sort((a, b) => b.strength.compareTo(a.strength));
  return activities;
}

/// The share of residential attractiveness that noise and air are eating,
/// averaged over the people who live with it.
///
/// Attractiveness is a weighted sum (model/stocks.dart); this is the part of
/// that sum the two traffic-driven terms are failing to deliver, which is
/// exactly what closes the loop back onto population.
double _crowding(WorldState w, SimParams p, Fields f) {
  final aw = p.economy.attractiveness;
  final np = p.noise;
  var weighted = 0.0;
  var people = 0.0;
  for (var i = 0; i < w.cellCount; i++) {
    if (!p.tile(w.tiles[i]).isResidential) continue;
    final pop = math.max(w.population[i], 1e-9);
    final noiseScore = clamp01(
      (np.limitBadDb - f.noiseDb[i]) / (np.limitBadDb - np.limitDayDb),
    );
    final airScore = f.airIndex[i] / 100;
    final lost = (aw.noise * (1 - noiseScore) + aw.air * (1 - airScore)) / aw.sum;
    weighted += lost * pop;
    people += pop;
  }
  return people <= 0 ? 0 : clamp01(weighted / people);
}

/// How much of the town's monthly money comes from its own residents and jobs
/// rather than going straight back out as upkeep.
double _taxBase(Fields f) {
  final total = f.revenueKEur + f.maintenanceKEur;
  return total <= 0 ? 0 : clamp01(f.revenueKEur / total);
}

/// The share of local jobs filled by people commuting in from outside.
double _inCommuting(Fields f) =>
    f.jobsCapacity <= 0 ? 0 : clamp01(f.inCommuters / f.jobsCapacity);

/// Mean threat degradation across the cells that are habitat at all.
double _fragmentation(WorldState w, SimParams p, Fields f) {
  var sum = 0.0;
  var cells = 0;
  for (var i = 0; i < w.cellCount; i++) {
    if (p.tile(w.tiles[i]).biotopeValue.value <= 0) continue;
    sum += f.habitatThreat[i];
    cells++;
  }
  return cells == 0 ? 0 : clamp01(sum / cells);
}

/// How much of the nature on the map has not finished growing.
///
/// High right after planting and falling as the years pass, which is the delay
/// the loop is about: the biodiversity and cooling are owed, not yet paid.
///
/// This uses the maturity curve of model/habitat.dart, `biotopeStart`
/// included — a tile is worth part of its value the day it appears, and only
/// the remainder is outstanding. Ignoring that would report a fresh meadow as
/// owing everything, when the model already counts nearly half of it.
double _regrowth(WorldState w, SimParams p) {
  var owed = 0.0;
  var cells = 0;
  for (var i = 0; i < w.cellCount; i++) {
    final tp = p.tile(w.tiles[i]);
    if (tp.biotopeValue.value <= 0) continue;
    final start = tp.biotopeStart.value;
    final months = math.max(1.0, tp.recoveryMonths.value);
    final maturity = start + (1 - start) * clamp01(w.tileAge[i] / months);
    owed += 1 - maturity;
    cells++;
  }
  return cells == 0 ? 0 : clamp01(owed / cells);
}

/// Tile types that drive [loop], for pointing at the map.
List<TileType> loopSources(CausalLoop loop) => switch (loop) {
  CausalLoop.crowding => const [TileType.road, TileType.housingHigh],
  CausalLoop.taxBase => const [TileType.housingHigh, TileType.commercial],
  CausalLoop.inCommuting => const [TileType.commercial, TileType.industry],
  CausalLoop.fragmentation => const [TileType.road, TileType.industry],
  CausalLoop.regrowth => const [TileType.forest, TileType.park],
};
