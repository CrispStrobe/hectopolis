// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:math' as math;
import 'dart:typed_data';

import '../fields.dart';
import '../geometry.dart';
import '../lookup.dart';
import '../params.dart';
import '../world.dart';

/// Accessibility fields (docs/model/access.md).
///
/// Green access: best recreational green within 300 m (WHO, 3-30-300), plus a
/// variety bonus. Retail access: Huff gravity with λ = 2 within 700 m.
/// Job access: gravity kernel exp(−d / 2 km), normalised to a reference.
void computeAccess(WorldState w, SimParams p, Fields f) {
  final n = w.cellCount;
  final width = w.width;
  final height = w.height;
  final ap = p.access;
  final lookup = TileLookup.of(p);
  final greenWeightOf = lookup.greenWeight;
  final retailFloorOf = lookup.retailFloorM2;
  final jobsPerHaOf = lookup.jobsPerHa;

  final greenOffsets = Offsets.radius(ap.greenRadiusTiles);
  final retailOffsets = Offsets.radius(ap.retailRadiusTiles);

  // Tile type per cell, so the inner loops index arrays instead of walking
  // enum objects.
  final tileIndex = Uint8List(n);
  for (var i = 0; i < n; i++) {
    tileIndex[i] = w.tiles[i].index;
  }

  // Huff distance weight per offset: the same for every cell.
  final retailWeight = Float64List(retailOffsets.length);
  for (var k = 0; k < retailOffsets.length; k++) {
    retailWeight[k] = 1 / math.pow(math.max(retailOffsets.dist[k], 0.5), ap.huffLambda);
  }
  final ownRetailWeight = 1 / math.pow(0.5, ap.huffLambda);

  // Job access uses the whole map (kernel decays smoothly).
  final jobCellList = <int>[];
  for (var i = 0; i < n; i++) {
    if (jobsPerHaOf[tileIndex[i]] > 0) jobCellList.add(i);
  }
  final jobCount = jobCellList.length;
  final jobX = Int32List(jobCount);
  final jobY = Int32List(jobCount);
  final jobCounts = Float64List(jobCount);
  for (var k = 0; k < jobCount; k++) {
    final j = jobCellList[k];
    jobX[k] = j % width;
    jobY[k] = j ~/ width;
    jobCounts[k] = jobsPerHaOf[tileIndex[j]];
  }
  final decay = DecayTables.get(
    maxDist2: w.width * w.width + w.height * w.height,
    cellSizeM: p.cellSizeM,
    decayM: ap.jobDecayM,
  );
  final decayValues = decay.values;

  final greenDx = greenOffsets.dx;
  final greenDy = greenOffsets.dy;
  final retailDx = retailOffsets.dx;
  final retailDy = retailOffsets.dy;

  for (var i = 0; i < n; i++) {
    final x = i % width;
    final y = i ~/ width;

    var bestGreen = greenWeightOf[tileIndex[i]];
    var greenCount = 0;
    for (var k = 0; k < greenOffsets.length; k++) {
      final nx = x + greenDx[k];
      if (nx < 0 || nx >= width) continue;
      final ny = y + greenDy[k];
      if (ny < 0 || ny >= height) continue;
      final gw = greenWeightOf[tileIndex[ny * width + nx]];
      if (gw > 0) {
        greenCount++;
        if (gw > bestGreen) bestGreen = gw;
      }
    }
    var green = bestGreen;
    if (greenCount >= ap.greenVarietyMinTiles) green += ap.greenVarietyBonus;
    f.greenAccess[i] = clamp01(green);

    var supply = 0.0;
    for (var k = 0; k < retailOffsets.length; k++) {
      final nx = x + retailDx[k];
      if (nx < 0 || nx >= width) continue;
      final ny = y + retailDy[k];
      if (ny < 0 || ny >= height) continue;
      final floor = retailFloorOf[tileIndex[ny * width + nx]];
      if (floor <= 0) continue;
      supply += floor * retailWeight[k];
    }
    final ownFloor = retailFloorOf[tileIndex[i]];
    if (ownFloor > 0) supply += ownFloor * ownRetailWeight;
    f.retailAccess[i] = clamp01(supply / ap.retailReferenceSupply);

    var jobs = 0.0;
    for (var k = 0; k < jobCount; k++) {
      final dx = jobX[k] - x;
      final dy = jobY[k] - y;
      jobs += jobCounts[k] * decayValues[dx * dx + dy * dy];
    }
    f.jobAccess[i] = clamp01(jobs / ap.jobReferenceJobs);
  }
}
