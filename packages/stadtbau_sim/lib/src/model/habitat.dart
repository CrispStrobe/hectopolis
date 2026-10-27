// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:math' as math;
import 'dart:typed_data';

import '../fields.dart';
import '../geometry.dart';
import '../params.dart';
import '../world.dart';

/// Habitat quality and biodiversity (docs/model/biodiversity.md).
///
/// Base habitat H = biotope value / 24 × maturity (tile age). Threats degrade
/// it following InVEST Habitat Quality: D = Σ w_r · (1 − d / d_max), and
/// Q = H · (1 − D^z / (D^z + k^z)). Patches are labelled with 8-neighbourhood
/// connectivity; the effective mesh size (Jaeger 2000) measures fragmentation.
/// Biodiversity = 100 · (A_eff / A)^z_sa · (0.5 + 0.5 · connectivity).
void computeHabitat(WorldState w, SimParams p, Fields f) {
  final n = w.cellCount;
  final width = w.width;
  final hp = p.habitat;

  // Base quality with maturation.
  final base = Float64List(n);
  for (var i = 0; i < n; i++) {
    final tp = p.tile(w.tiles[i]);
    f.habitatThreat[i] = 0;
    f.habitatQuality[i] = 0;
    if (!tp.isHabitat) continue;
    final start = tp.biotopeStart.value;
    final months = math.max(1.0, tp.recoveryMonths.value);
    final maturity = start + (1 - start) * clamp01(w.tileAge[i] / months);
    base[i] = tp.biotopeValue.value / 24.0 * maturity;
  }

  // Threat degradation.
  var maxRadius = 0;
  for (final t in hp.threats.values) {
    maxRadius = math.max(maxRadius, (t.maxDistanceM / p.cellSizeM).ceil());
  }
  final offsets = Offsets.radius(maxRadius);
  for (var s = 0; s < n; s++) {
    final threat = hp.threats[w.tiles[s]];
    if (threat == null) continue;
    final sx = s % width;
    final sy = s ~/ width;
    final maxTiles = threat.maxDistanceM / p.cellSizeM;
    for (var k = 0; k < offsets.length; k++) {
      final d = offsets.dist[k];
      if (d > maxTiles) continue;
      final rx = sx + offsets.dx[k];
      final ry = sy + offsets.dy[k];
      if (!w.inBounds(rx, ry)) continue;
      final r = ry * width + rx;
      if (base[r] <= 0) continue;
      f.habitatThreat[r] += threat.weight * (1 - d / maxTiles);
    }
  }

  final k = hp.halfSaturation;
  final z = hp.scalingZ;
  final kz = math.pow(k, z).toDouble();
  final isHabitat = Uint8List(n);
  for (var i = 0; i < n; i++) {
    if (base[i] <= 0) continue;
    isHabitat[i] = 1;
    // Four adjacent full-weight threats saturate the degradation.
    final d = clamp01(f.habitatThreat[i] / 4);
    f.habitatThreat[i] = d;
    final dz = math.pow(d, z).toDouble();
    f.habitatQuality[i] = base[i] * (1 - dz / (dz + kz));
  }

  // Patches and effective mesh size.
  final ds = DisjointSet(n);
  for (var i = 0; i < n; i++) {
    if (isHabitat[i] == 0) continue;
    final x = i % width;
    final y = i ~/ width;
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        if (dx == 0 && dy == 0) continue;
        final nx = x + dx;
        final ny = y + dy;
        if (!w.inBounds(nx, ny)) continue;
        final j = ny * width + nx;
        if (isHabitat[j] == 1) ds.union(i, j);
      }
    }
  }
  final patchArea = Float64List(n);
  var total = 0.0;
  for (var i = 0; i < n; i++) {
    if (isHabitat[i] == 0) continue;
    patchArea[ds.find(i)] += f.habitatQuality[i];
    total += f.habitatQuality[i];
  }
  var sumSquares = 0.0;
  for (var i = 0; i < n; i++) {
    sumSquares += patchArea[i] * patchArea[i];
  }
  final connectivity = total > 0 ? (sumSquares / total) / total : 0.0;
  f.habitatAreaEff = total;
  f.habitatConnectivity = connectivity;
  f.biodiversityIndex =
      total > 0 ? 100 * math.pow(total / n, hp.speciesAreaZ) * (0.5 + 0.5 * connectivity) : 0.0;
}

/// The degradation each threat within its reach adds to [cell], before the
/// total is capped: w_r · (1 − d / d_max), as [computeHabitat] sums them.
/// Empty when [cell] is not habitat, since threats only degrade habitat.
Map<int, double> threatSources(WorldState w, SimParams p, int cell) {
  final out = <int, double>{};
  // The same base-quality test as computeHabitat: green, with a biotope value
  // and some maturity.
  final tp = p.tile(w.tiles[cell]);
  if (!tp.isHabitat) return out;
  final start = tp.biotopeStart.value;
  final months = math.max(1.0, tp.recoveryMonths.value);
  final maturity = start + (1 - start) * clamp01(w.tileAge[cell] / months);
  if (tp.biotopeValue.value / 24.0 * maturity <= 0) return out;
  final hp = p.habitat;
  var maxRadius = 0;
  for (final t in hp.threats.values) {
    maxRadius = math.max(maxRadius, (t.maxDistanceM / p.cellSizeM).ceil());
  }
  final offsets = Offsets.radius(maxRadius);
  final x = cell % w.width;
  final y = cell ~/ w.width;
  for (var k = 0; k < offsets.length; k++) {
    final sx = x - offsets.dx[k];
    final sy = y - offsets.dy[k];
    if (!w.inBounds(sx, sy)) continue;
    final s = sy * w.width + sx;
    final threat = hp.threats[w.tiles[s]];
    if (threat == null) continue;
    final maxTiles = threat.maxDistanceM / p.cellSizeM;
    final d = offsets.dist[k];
    if (d > maxTiles) continue;
    out[s] = threat.weight * (1 - d / maxTiles);
  }
  return out;
}
