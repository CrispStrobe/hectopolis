// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:math' as math;
import 'dart:typed_data';

import '../fields.dart';
import '../geometry.dart';
import '../lookup.dart';
import '../params.dart';
import '../tile_type.dart';
import '../world.dart';

/// Noise propagation (docs/model/noise.md).
///
/// Every emitting tile is a point/area source with −20 dB per decade of
/// distance from the tile boundary (ISO 9613-2 geometric divergence). Roads
/// are treated as 100 m segments the way CNOSSOS-EU splits a line into point
/// sources; their energetic sum reproduces the 3 dB per doubling of a line.
/// Road emission scales with traffic (10·log10(Q/Q_ref), RLS-19). Foliage and
/// building rows on the straight path attenuate further. Contributions are
/// summed energetically over a rural background.
void computeNoise(WorldState w, SimParams p, Fields f) {
  final n = w.cellCount;
  final width = w.width;
  final height = w.height;
  final np = p.noise;
  final offsets = Offsets.radius(np.radiusTiles);
  final dxs = offsets.dx;
  final dys = offsets.dy;
  final paths = offsets.pathOffsets;
  final maxAttenuation = np.maxPathAttenuationDb;
  final noiseEmissionOf = TileLookup.of(p).noiseEmissionDb;

  // A cell on the path attenuates as foliage, as a building row, or not at
  // all — three classes, never a continuum. Each is counted rather than
  // summed in decibels, so the whole path collapses to one small integer and
  // the attenuation factor comes out of a table instead of a call to exp.
  // Foliage counts as 1 and a building row as `attStride`, so a single
  // accumulator carries both counts: code = foliageCells + buildingCells *
  // attStride.
  final maxPathCells = offsets.maxPathCells;
  final attStride = maxPathCells + 1;
  // A building row is counted as `attStride` in a Uint8 cell, so a radius
  // beyond 254 tiles would wrap it. Nothing comes close (the shipped radius is
  // 6), but a scenario can override the radius, and a silent wrap here would
  // read the wrong attenuation rather than fail.
  assert(attStride <= 255, 'noise radius too large for the attenuation table');
  final attCodeOf = Uint8List(TileType.values.length);
  for (final t in TileType.values) {
    final cat = p.tile(t).category;
    if (t == TileType.forest || t == TileType.park) {
      attCodeOf[t.index] = 1;
    } else if (cat == TileCategory.work || t == TileType.housingHigh) {
      attCodeOf[t.index] = attStride;
    }
  }
  final attFactor = Float64List(attStride * attStride);
  for (var buildings = 0; buildings <= maxPathCells; buildings++) {
    for (var foliage = 0; foliage <= maxPathCells; foliage++) {
      final db = math.min(
        maxAttenuation,
        foliage * np.foliageAttenuationDbPerTile +
            buildings * np.buildingScreeningDbPerTile,
      );
      attFactor[buildings * attStride + foliage] = _dbToEnergy(-db);
    }
  }

  // Emission and screening per cell, so the inner loops index flat arrays
  // rather than resolving enums and parameters per offset.
  final emission = Float64List(n);
  // Night emission per cell: the same source, quieter (docs/model/noise.md).
  final nightEmission = Float64List(n);
  final nightReductionOf = Float64List(TileType.values.length);
  for (final t in TileType.values) {
    nightReductionOf[t.index] = p.tile(t).noiseNightReductionDb.value;
  }
  final attCode = Uint8List(n);
  final sources = <int>[];
  final trafficReference = np.trafficReferenceVehiclesPerDay;
  for (var i = 0; i < n; i++) {
    final t = w.tiles[i];
    attCode[i] = attCodeOf[t.index];
    final base = noiseEmissionOf[t.index];
    if (base <= 0) continue;
    final e = t == TileType.road
        ? base + 10 * _log10(math.max(f.traffic[i], 1.0) / trafficReference)
        : base;
    if (e <= 0) continue;
    emission[i] = e;
    nightEmission[i] = e - nightReductionOf[t.index];
    sources.add(i);
  }

  // Free-field level per offset is the same for every source: precompute.
  final divergence = Float64List(offsets.length);
  for (var k = 0; k < offsets.length; k++) {
    final dM = offsets.dist[k] * p.cellSizeM;
    divergence[k] =
        np.areaDecayDbPerDecade * _log10(math.max(dM, np.areaReferenceDistanceM) / np.areaReferenceDistanceM);
  }
  final cutoff = np.backgroundDb - 15;
  // The cutoff test is on the level in dB and the accumulation is in energy;
  // both are monotone in the other, so comparing energies decides it without
  // turning the energy back into a level.
  final cutoffEnergy = _dbToEnergy(cutoff);

  // A contribution is `source energy × divergence × path attenuation`. All
  // three factors are now table lookups: the source term is one exp per cell,
  // the divergence one per offset, and the path one per (foliage, building)
  // pair. Before this, every source-receiver pair called exp up to four times.
  final divFactor = Float64List(offsets.length);
  for (var k = 0; k < offsets.length; k++) {
    divFactor[k] = _dbToEnergy(-divergence[k]);
  }
  final srcEnergy = Float64List(n);
  final srcNightEnergy = Float64List(n);
  for (final s in sources) {
    srcEnergy[s] = _dbToEnergy(emission[s]);
    if (nightEmission[s] > 0) srcNightEnergy[s] = _dbToEnergy(nightEmission[s]);
  }

  final energy = Float64List(n)..fillRange(0, n, _dbToEnergy(np.backgroundDb));
  // The night level rides along in the same pass: the geometry and the path
  // attenuation are identical, and only the source term differs, so a second
  // sweep would repeat the expensive half of the work for nothing.
  final nightEnergy = Float64List(n)
    ..fillRange(0, n, _dbToEnergy(np.backgroundDb));
  for (final s in sources) {
    energy[s] += srcEnergy[s];
    nightEnergy[s] += srcNightEnergy[s];
  }

  // Path attenuation is reciprocal, so each unordered pair of cells is visited
  // once (over half the offsets) and the shared attenuation serves both
  // directions.
  final half = offsets.half;
  final halfCount = half.length;
  for (var s = 0; s < n; s++) {
    final sx = s % width;
    final sy = s ~/ width;
    final es = emission[s];
    final ns = nightEmission[s];
    for (var h = 0; h < halfCount; h++) {
      final k = half[h];
      final rx = sx + dxs[k];
      if (rx < 0 || rx >= width) continue;
      final ry = sy + dys[k];
      if (ry < 0 || ry >= height) continue;
      final r = ry * width + rx;
      final er = emission[r];
      final nr = nightEmission[r];
      final loudest = es > er ? es : er;
      if (loudest <= 0) continue;
      final divergenceDb = divergence[k];
      if (loudest - divergenceDb <= cutoff) continue;
      var code = 0;
      final path = paths[k];
      for (var q = 0; q < path.length; q += 2) {
        code += attCode[(sy + path[q + 1]) * width + sx + path[q]];
      }
      final drop = divFactor[k] * attFactor[code];
      if (es > 0) {
        final day = srcEnergy[s] * drop;
        if (day > cutoffEnergy) energy[r] += day;
        if (ns > 0) {
          final night = srcNightEnergy[s] * drop;
          if (night > cutoffEnergy) nightEnergy[r] += night;
        }
      }
      if (er > 0) {
        final day = srcEnergy[r] * drop;
        if (day > cutoffEnergy) energy[s] += day;
        if (nr > 0) {
          final night = srcNightEnergy[r] * drop;
          if (night > cutoffEnergy) nightEnergy[s] += night;
        }
      }
    }
  }
  for (var i = 0; i < n; i++) {
    f.noiseDb[i] = 10 * _log10(energy[i]);
    f.noiseNightDb[i] = 10 * _log10(nightEnergy[i]);
  }
}

/// Sound energy for a level in dB. `exp` is markedly cheaper than `pow` and
/// this runs once per source and offset.
double _dbToEnergy(double db) => math.exp(db * (math.ln10 / 10));

/// One row of a per-cell breakdown: how much a tile type contributes.
class Contribution {
  const Contribution({required this.type, required this.count, required this.nearestTiles, required this.value});

  final TileType type;

  /// Number of source tiles of this type that reach the cell.
  final int count;

  /// Distance in tiles to the nearest of them.
  final double nearestTiles;

  /// Contribution in the field's unit (dB for noise, concentration for air).
  final double value;
}

/// Noise at [cell] broken down by source tile type (energetic sums), sorted
/// by level, for the tile inspector. Uses the same formulas as [computeNoise].
List<Contribution> explainNoise(WorldState w, SimParams p, Fields f, int cell) {
  final width = w.width;
  final np = p.noise;
  final offsets = Offsets.radius(np.radiusTiles);
  final rx = cell % width;
  final ry = cell ~/ width;
  final energy = <TileType, double>{};
  final count = <TileType, int>{};
  final nearest = <TileType, double>{};

  void add(TileType t, double level, double dist) {
    energy[t] = (energy[t] ?? 0) + math.pow(10, level / 10).toDouble();
    count[t] = (count[t] ?? 0) + 1;
    nearest[t] = math.min(nearest[t] ?? double.infinity, dist);
  }

  double emissionOf(int i) {
    final t = w.tiles[i];
    final base = p.tile(t).noiseEmissionDb.value;
    if (base <= 0) return 0;
    if (t == TileType.road) return base + 10 * _log10(math.max(f.traffic[i], 1.0) / np.trafficReferenceVehiclesPerDay);
    return base;
  }

  final own = emissionOf(cell);
  if (own > 0) add(w.tiles[cell], own, 0);
  for (var k = 0; k < offsets.length; k++) {
    // Source at the mirrored offset so that the path runs source → receiver.
    final sx = rx - offsets.dx[k];
    final sy = ry - offsets.dy[k];
    if (!w.inBounds(sx, sy)) continue;
    final s = sy * width + sx;
    final e = emissionOf(s);
    if (e <= 0) continue;
    final dM = offsets.dist[k] * p.cellSizeM;
    var level = e -
        np.areaDecayDbPerDecade * _log10(math.max(dM, np.areaReferenceDistanceM) / np.areaReferenceDistanceM);
    var att = 0.0;
    final path = offsets.pathOffsets[k];
    for (var i = 0; i < path.length; i += 2) {
      final c = (sy + path[i + 1]) * width + sx + path[i];
      final t = w.tiles[c];
      if (t == TileType.forest || t == TileType.park) {
        att += np.foliageAttenuationDbPerTile;
      } else if (p.tile(t).category == TileCategory.work || t == TileType.housingHigh) {
        att += np.buildingScreeningDbPerTile;
      }
    }
    level -= math.min(att, np.maxPathAttenuationDb);
    if (level <= np.backgroundDb - 15) continue;
    add(w.tiles[s], level, offsets.dist[k]);
  }
  final rows = [
    for (final t in energy.keys)
      Contribution(type: t, count: count[t]!, nearestTiles: nearest[t]!, value: 10 * _log10(energy[t]!)),
  ]..sort((a, b) => b.value.compareTo(a.value));
  return rows;
}

double _log10(double v) => math.log(v) / math.ln10;
