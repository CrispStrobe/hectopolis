// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:math' as math;
import 'dart:typed_data';

import '../fields.dart';
import '../geometry.dart';
import '../params.dart';
import '../tile_type.dart';
import '../world.dart';

/// Rainfall runoff by the SCS curve number method (docs/model/water.md).
///
/// For each cell, the sealed and unsealed parts are composed into one curve
/// number the way TR-55 does for connected impervious area:
///
///   CN = CN_pervious + sealing · (98 − CN_pervious)
///
/// then the classical runoff equation, in millimetres:
///
///   S  = 25400 / CN − 254        maximum retention
///   Ia = 0.2 · S                 initial abstraction
///   Q  = (P − Ia)² / (P − Ia + S)   for P > Ia, else 0
///
/// Open water and wetland do not generate runoff; they take it. Each such cell
/// absorbs depth from the cells within `retentionRadiusTiles`, sharing its
/// capacity equally among them, which is a stand-in for storage rather than a
/// routing model: nothing here knows which way the ground slopes.
void computeWater(WorldState w, SimParams p, Fields f) {
  final n = w.cellCount;
  final width = w.width;
  final height = w.height;
  final wp = p.water;
  final rain = wp.designStormMm;

  // Composite curve number per tile type, and the runoff it produces for this
  // storm. Both depend only on the parameters, so they are computed once per
  // type rather than once per cell.
  final runoffOf = Float64List(TileType.values.length);
  for (final t in TileType.values) {
    if (_isRetention(t)) continue;
    final tp = p.tile(t);
    final pervious = tp.perviousCurveNumber.value;
    final cn = pervious + tp.sealing.value * (wp.imperviousCurveNumber - pervious);
    final s = 25400 / cn - 254;
    final ia = wp.initialAbstractionRatio * s;
    runoffOf[t.index] = rain > ia ? math.pow(rain - ia, 2) / (rain - ia + s) : 0.0;
  }

  final runoff = f.runoffMm;
  for (var i = 0; i < n; i++) {
    runoff[i] = runoffOf[w.tiles[i].index];
  }

  // Retention: each water cell hands its capacity to the cells it can reach,
  // including itself, in equal shares.
  final offsets = Offsets.radius(wp.retentionRadiusTiles);
  for (var i = 0; i < n; i++) {
    if (!_isRetention(w.tiles[i])) continue;
    final x = i % width;
    final y = i ~/ width;
    final reached = <int>[];
    for (var k = 0; k < offsets.length; k++) {
      final nx = x + offsets.dx[k];
      if (nx < 0 || nx >= width) continue;
      final ny = y + offsets.dy[k];
      if (ny < 0 || ny >= height) continue;
      final j = ny * width + nx;
      if (runoff[j] > 0) reached.add(j);
    }
    if (reached.isEmpty) continue;
    final share = wp.retentionMmPerCell / reached.length;
    for (final j in reached) {
      runoff[j] = math.max(0, runoff[j] - share);
    }
  }

  var total = 0.0;
  var atRisk = 0;
  for (var i = 0; i < n; i++) {
    total += runoff[i];
    if (runoff[i] > wp.floodRiskMm) atRisk++;
  }
  f.meanRunoffMm = n == 0 ? 0 : total / n;
  f.floodRiskCells = atRisk;
}

/// Tiles that take water rather than shed it.
///
/// Wetland is here for the reason it exists: reed beds and wet soil hold a
/// storm back where sealed ground passes it straight on. T-503 landed with
/// only open water in this set because wetland did not exist yet.
bool _isRetention(TileType t) =>
    t == TileType.water || t == TileType.wetland;
