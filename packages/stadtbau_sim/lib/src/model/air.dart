// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:math' as math;
import 'dart:typed_data';

import '../fields.dart';
import '../geometry.dart';
import '../params.dart';
import '../tile_type.dart';
import '../world.dart';
import 'noise.dart' show Contribution;

/// Air pollution (docs/model/air.md).
///
/// Every emitter spreads its emission E over its neighbourhood with the
/// kernel exp(−d / L) (isotropic near-field approximation of a Gaussian
/// plume, L = 300 m), normalised so that the kernel sums to one: a uniform
/// field of emitters yields a concentration equal to the emission rate, and
/// a single emitter dilutes with distance. Road emissions scale with
/// traffic. Vegetation in the receiver's 300 m neighbourhood removes a share
/// of the local concentration (deposition, magnitudes after Nowak et al.).
/// The index is 100 · exp(−C / scale).

/// The dispersion kernel: how much of a source's emission reaches each offset.
///
/// Calm is the isotropic exp(−d / L) the model has always used. With wind the
/// same exponential is applied to a distance measured in a stretched frame:
/// the along-wind component is divided by the stretch downwind and multiplied
/// by it upwind, and the crosswind component is multiplied by its square root.
/// That is a screening-level stand-in for a Gaussian plume — advection carries
/// material downwind and the same material occupies a narrower cross-section —
/// not a solution of one (docs/model/air.md).
///
/// Shared by [computeAir] and [explainAir] so that the two cannot drift, and
/// cached per parameter set because it depends on nothing else.
class AirKernel {
  AirKernel._(this.params, this.offsets, this.weights, this.sum);

  final SimParams params;
  final Offsets offsets;

  /// Weight per offset, before normalisation by [sum].
  final Float64List weights;

  /// The centre cell (1.0) plus every offset weight. Dividing an emission by
  /// this keeps a uniform field of emitters at a concentration equal to the
  /// emission rate, whatever the wind is doing.
  final double sum;

  static AirKernel? _cached;

  static AirKernel of(SimParams p) {
    final cached = _cached;
    if (cached != null && identical(cached.params, p)) return cached;
    return _cached = _build(p);
  }

  static AirKernel _build(SimParams p) {
    final ap = p.air;
    final offsets = Offsets.radius(ap.radiusTiles);
    final weights = Float64List(offsets.length);
    // Meteorological degrees say where the wind comes FROM; the plume travels
    // the opposite way, and screen y grows southward.
    final towards = (ap.windFromDegrees + 180) * math.pi / 180;
    final wx = math.sin(towards);
    final wy = -math.cos(towards);
    final stretch = ap.windStretch;
    final spread = math.sqrt(stretch);
    var sum = 1.0;
    for (var k = 0; k < offsets.length; k++) {
      final dxM = offsets.dx[k] * p.cellSizeM;
      final dyM = offsets.dy[k] * p.cellSizeM;
      double distance;
      if (!ap.hasWind) {
        distance = offsets.dist[k] * p.cellSizeM;
      } else {
        final along = dxM * wx + dyM * wy;
        final cross = (dxM * wy - dyM * wx).abs();
        final scaledAlong = along >= 0 ? along / stretch : along * stretch;
        final scaledCross = cross * spread;
        distance = math.sqrt(
          scaledAlong * scaledAlong + scaledCross * scaledCross,
        );
      }
      weights[k] = math.exp(-distance / ap.decayLengthM);
      sum += weights[k];
    }
    return AirKernel._(p, offsets, weights, sum);
  }
}

void computeAir(WorldState w, SimParams p, Fields f) {
  final n = w.cellCount;
  final width = w.width;
  final ap = p.air;
  final airKernel = AirKernel.of(p);
  final offsets = airKernel.offsets;
  final kernel = airKernel.weights;
  final kernelSum = airKernel.sum;
  final conc = f.airConcentration;
  for (var i = 0; i < n; i++) {
    conc[i] = 0;
  }

  for (var s = 0; s < n; s++) {
    final t = w.tiles[s];
    var e = p.tile(t).airEmission.value;
    if (e <= 0) continue;
    if (t == TileType.road) {
      e *= f.traffic[s] / ap.trafficReferenceVehiclesPerDay;
    }
    e /= kernelSum;
    conc[s] += e;
    final sx = s % width;
    final sy = s ~/ width;
    for (var k = 0; k < offsets.length; k++) {
      final rx = sx + offsets.dx[k];
      final ry = sy + offsets.dy[k];
      if (!w.inBounds(rx, ry)) continue;
      conc[ry * width + rx] += e * kernel[k];
    }
  }

  // Local deposition: mean sink coefficient in the neighbourhood.
  final sinkOffsets = Offsets.radius(ap.sinkRadiusTiles);
  for (var i = 0; i < n; i++) {
    final x = i % width;
    final y = i ~/ width;
    var sink = p.tile(w.tiles[i]).airSink.value;
    var count = 1;
    for (var k = 0; k < sinkOffsets.length; k++) {
      final nx = x + sinkOffsets.dx[k];
      final ny = y + sinkOffsets.dy[k];
      if (!w.inBounds(nx, ny)) continue;
      sink += p.tile(w.tiles[ny * width + nx]).airSink.value;
      count++;
    }
    final factor = 1 - sink / count;
    conc[i] *= factor;
    f.airIndex[i] = 100 * math.exp(-conc[i] / ap.indexScale);
  }
}

/// Air concentration at [cell] broken down by source tile type, after the
/// local deposition factor, sorted by contribution.
List<Contribution> explainAir(WorldState w, SimParams p, Fields f, int cell) {
  final width = w.width;
  final ap = p.air;
  final airKernel = AirKernel.of(p);
  final offsets = airKernel.offsets;
  final kernelSum = airKernel.sum;
  final total = <TileType, double>{};
  final count = <TileType, int>{};
  final nearest = <TileType, double>{};

  double emissionOf(int i) {
    final t = w.tiles[i];
    var e = p.tile(t).airEmission.value;
    if (e <= 0) return 0;
    if (t == TileType.road) e *= f.traffic[i] / ap.trafficReferenceVehiclesPerDay;
    return e / kernelSum;
  }

  void add(TileType t, double v, double dist) {
    total[t] = (total[t] ?? 0) + v;
    count[t] = (count[t] ?? 0) + 1;
    nearest[t] = math.min(nearest[t] ?? double.infinity, dist);
  }

  final own = emissionOf(cell);
  if (own > 0) add(w.tiles[cell], own, 0);
  final rx = cell % width;
  final ry = cell ~/ width;
  for (var k = 0; k < offsets.length; k++) {
    final sx = rx - offsets.dx[k];
    final sy = ry - offsets.dy[k];
    if (!w.inBounds(sx, sy)) continue;
    final s = sy * width + sx;
    final e = emissionOf(s);
    if (e <= 0) continue;
    // The receiver sits at +offset from the source, which is the direction
    // the kernel is indexed by, so the same weight applies here.
    add(w.tiles[s], e * airKernel.weights[k], offsets.dist[k]);
  }
  // Scale to the deposited concentration actually stored in the field.
  var raw = 0.0;
  for (final v in total.values) {
    raw += v;
  }
  final factor = raw > 0 ? f.airConcentration[cell] / raw : 0.0;
  final rows = [
    for (final t in total.keys)
      Contribution(type: t, count: count[t]!, nearestTiles: nearest[t]!, value: total[t]! * factor),
  ]..sort((a, b) => b.value.compareTo(a.value));
  return rows;
}
