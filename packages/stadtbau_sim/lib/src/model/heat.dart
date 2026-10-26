// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:math' as math;
import 'dart:typed_data';

import '../fields.dart';
import '../geometry.dart';
import '../params.dart';
import '../tile_type.dart';
import '../world.dart';

/// Urban heat (docs/model/heat.md), after the InVEST Urban Cooling model.
///
/// Cooling capacity CC = 0.6·shade + 0.2·albedo + 0.2·ETI per land cover.
/// Green patches of at least 2 ha cool cells within the cooling distance;
/// the heat mitigation index is max(own CC, distance-weighted green CC).
/// InVEST writes T = T_rural + UHI_max · (1 − HM); because the rural
/// reference itself has HM ≈ 0.2–0.3, the game rescales so that the base
/// terrain (meadow) sits at ΔT = 0 and the least cooling land cover at
/// ΔT = UHI_max: ΔT = UHI_max · clamp((CC_ref − HM) / (CC_ref − CC_min)).
void computeHeat(WorldState w, SimParams p, Fields f) {
  final n = w.cellCount;
  final width = w.width;
  final hp = p.heat;

  // Seasons act on the two terms that are actually seasonal: vegetation
  // transpires in the growing season and barely at all in winter, and the
  // heat island itself is a summer phenomenon. Shade and albedo are properties
  // of the surface and stay put. (docs/model/seasons.md)
  final growth = p.seasons.growthAt(w.tick);
  final uhiMax = p.heat.uhiMaxC * p.seasons.heatAt(w.tick);
  f.uhiMaxNowC = uhiMax;

  double capacity(TileParams tp) =>
      hp.shadeWeight * tp.shade.value +
      hp.albedoWeight * tp.albedo.value +
      hp.etiWeight * tp.eti.value * growth;

  final ccRef = capacity(p.tile(TileType.terrain));
  var ccMin = ccRef;
  for (final t in TileType.values) {
    ccMin = math.min(ccMin, capacity(p.tile(t)));
  }
  final span = math.max(1e-6, ccRef - ccMin);

  final cc = f.coolingCapacity;
  for (var i = 0; i < n; i++) {
    cc[i] = capacity(p.tile(w.tiles[i]));
  }
  final cools = _coolsNeighbours(w, p);

  final offsets = Offsets.radius(hp.coolingDistanceTiles);
  for (var i = 0; i < n; i++) {
    final x = i % width;
    final y = i ~/ width;
    var hm = cc[i];
    for (var k = 0; k < offsets.length; k++) {
      final nx = x + offsets.dx[k];
      final ny = y + offsets.dy[k];
      if (!w.inBounds(nx, ny)) continue;
      final j = ny * width + nx;
      if (cools[j] == 0) continue;
      final weight = 1 - offsets.dist[k] / (hp.coolingDistanceTiles + 1);
      hm = math.max(hm, cc[j] * weight);
    }
    f.heatDeltaC[i] = uhiMax * clamp01((ccRef - hm) / span);
  }
}

/// 1 for every cell that cools its neighbours: green, and part of a connected
/// green patch (8-neighbourhood) of at least `greenPatchMinHa`.
Uint8List _coolsNeighbours(WorldState w, SimParams p) {
  final n = w.cellCount;
  final width = w.width;
  final isGreen = Uint8List(n);
  for (var i = 0; i < n; i++) {
    isGreen[i] = p.tile(w.tiles[i]).category.isGreen ? 1 : 0;
  }
  final ds = DisjointSet(n);
  for (var i = 0; i < n; i++) {
    if (isGreen[i] == 0) continue;
    final x = i % width;
    final y = i ~/ width;
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        if (dx == 0 && dy == 0) continue;
        final nx = x + dx;
        final ny = y + dy;
        if (!w.inBounds(nx, ny)) continue;
        final j = ny * width + nx;
        if (isGreen[j] == 1) ds.union(i, j);
      }
    }
  }
  final patchSize = Int32List(n);
  for (var i = 0; i < n; i++) {
    if (isGreen[i] == 1) patchSize[ds.find(i)]++;
  }
  final cools = Uint8List(n);
  for (var i = 0; i < n; i++) {
    if (isGreen[i] == 1 && patchSize[ds.find(i)] >= p.heat.greenPatchMinHa) {
      cools[i] = 1;
    }
  }
  return cools;
}

/// The cooling each green cell in reach offers [cell]: its cooling capacity
/// times the distance weight, as [computeHeat] uses them. The cell's heat
/// comes from the largest of these and its own capacity, so the strongest
/// source is the one that sets it.
Map<int, double> coolingSources(WorldState w, SimParams p, Fields f, int cell) {
  final hp = p.heat;
  final cools = _coolsNeighbours(w, p);
  final offsets = Offsets.radius(hp.coolingDistanceTiles);
  final x = cell % w.width;
  final y = cell ~/ w.width;
  final out = <int, double>{};
  for (var k = 0; k < offsets.length; k++) {
    final nx = x + offsets.dx[k];
    final ny = y + offsets.dy[k];
    if (!w.inBounds(nx, ny)) continue;
    final j = ny * w.width + nx;
    if (cools[j] == 0) continue;
    final weight = 1 - offsets.dist[k] / (hp.coolingDistanceTiles + 1);
    out[j] = f.coolingCapacity[j] * weight;
  }
  return out;
}
