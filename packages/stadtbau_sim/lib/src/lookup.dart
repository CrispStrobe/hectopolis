// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:typed_data';

import 'geometry.dart';
import 'params.dart';
import 'tile_type.dart';

/// Per-tile-type parameter values flattened into arrays indexed by
/// `TileType.index`.
///
/// Field kernels read the same handful of parameters for every cell of every
/// offset; going through `p.tile(t).someParam.value` costs a map lookup and
/// two object hops each time, which dominates the inner loops. The tables are
/// derived purely from [params] and cached per parameter set.
class TileLookup {
  TileLookup._(this.params)
      : jobsPerHa = _table(params, (t) => t.jobsPerHa.value),
        greenWeight = _table(params, (t) => t.greenWeight.value),
        retailFloorM2 = _table(params, (t) => t.retailFloorM2.value),
        noiseEmissionDb = _table(params, (t) => t.noiseEmissionDb.value);

  static Float64List _table(SimParams p, double Function(TileParams) read) {
    final values = Float64List(TileType.values.length);
    for (final t in TileType.values) {
      values[t.index] = read(p.tile(t));
    }
    return values;
  }

  final SimParams params;
  final Float64List jobsPerHa;
  final Float64List greenWeight;
  final Float64List retailFloorM2;
  final Float64List noiseEmissionDb;

  static TileLookup? _cached;

  /// The tables for [p], reusing the previous ones when [p] is unchanged.
  static TileLookup of(SimParams p) {
    final cached = _cached;
    if (cached != null && identical(cached.params, p)) return cached;
    return _cached = TileLookup._(p);
  }
}

/// A [DecayTable] cache: the table depends only on the grid diagonal and two
/// parameters, but is read by both the commute and the access kernel on every
/// tick.
class DecayTables {
  static final Map<String, DecayTable> _cache = {};

  static DecayTable get({
    required int maxDist2,
    required double cellSizeM,
    required double decayM,
  }) {
    final key = '$maxDist2:$cellSizeM:$decayM';
    return _cache[key] ??= DecayTable(
      maxDist2: maxDist2,
      cellSizeM: cellSizeM,
      decayM: decayM,
    );
  }
}
