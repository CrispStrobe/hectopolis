// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:typed_data';

import 'params.dart';
import 'tile_type.dart';

/// Deterministic xorshift32 generator. Uses only 32-bit arithmetic so it
/// behaves identically on the VM and on the web (JS numbers).
class Rng {
  Rng(int seed)
    : _s = (seed & 0xFFFFFFFF) == 0 ? 0x9E3779B9 : seed & 0xFFFFFFFF;

  int _s;

  int get state => _s;

  int nextUint32() {
    var x = _s;
    x ^= (x << 13) & 0xFFFFFFFF;
    x ^= x >>> 17;
    x ^= (x << 5) & 0xFFFFFFFF;
    _s = x & 0xFFFFFFFF;
    return _s;
  }

  /// Uniform double in [0, 1).
  double nextDouble() => nextUint32() / 4294967296.0;

  int nextInt(int max) => (nextDouble() * max).floor();
}

/// The complete mutable game state. Everything needed to reproduce a game is
/// here; fields and indicators are derived from it.
class WorldState {
  WorldState._({
    required this.width,
    required this.height,
    required this.tiles,
    required this.tileAge,
    required this.population,
    required this.tick,
    required this.budgetKEur,
    required this.seed,
  });

  /// A map filled with [TileType.terrain].
  factory WorldState.empty({
    required int width,
    required int height,
    required double budgetKEur,
    int seed = 1,
  }) {
    final n = width * height;
    return WorldState._(
      width: width,
      height: height,
      tiles: List<TileType>.filled(n, TileType.terrain),
      tileAge: Int32List(n),
      population: Float64List(n),
      tick: 0,
      budgetKEur: budgetKEur,
      seed: seed,
    );
  }

  final int width;
  final int height;

  /// Row-major tile types, index = y * width + x.
  final List<TileType> tiles;

  /// Months since the tile was placed (drives biotope maturation).
  final Int32List tileAge;

  /// Residents per cell.
  final Float64List population;

  int tick;
  double budgetKEur;
  final int seed;

  int get cellCount => width * height;

  int index(int x, int y) => y * width + x;

  bool inBounds(int x, int y) => x >= 0 && y >= 0 && x < width && y < height;

  TileType tileAt(int x, int y) => tiles[index(x, y)];

  double get totalPopulation {
    var sum = 0.0;
    for (final p in population) {
      sum += p;
    }
    return sum;
  }

  /// Fill every existing residential tile to [occupancy] of its capacity.
  /// Used by levels so that pre-built quarters are inhabited from the start.
  void populateExisting(
    SimParams params, {
    double occupancy = 0.9,
    int ageMonths = 240,
  }) {
    for (var i = 0; i < cellCount; i++) {
      final tp = params.tile(tiles[i]);
      tileAge[i] = ageMonths;
      population[i] = tp.isResidential
          ? tp.residentsPerHa.value * occupancy
          : 0;
    }
  }

  WorldState copy() => WorldState._(
    width: width,
    height: height,
    tiles: List<TileType>.of(tiles),
    tileAge: Int32List.fromList(tileAge),
    population: Float64List.fromList(population),
    tick: tick,
    budgetKEur: budgetKEur,
    seed: seed,
  );

  Map<String, dynamic> toJson() => {
    'version': 1,
    'width': width,
    'height': height,
    'tick': tick,
    // JSON has no representation for infinity. Sandboxes use an unlimited
    // budget, so store that semantic value explicitly while keeping old
    // numeric save files backwards compatible.
    'budgetKEur': budgetKEur.isFinite ? budgetKEur : 'unlimited',
    'seed': seed,
    'tiles': [for (final t in tiles) t.id],
    'tileAge': tileAge.toList(),
    'population': population.toList(),
  };

  static WorldState fromJson(Map<String, dynamic> json) {
    final width = json['width'] as int;
    final height = json['height'] as int;
    final n = width * height;
    final tiles = (json['tiles'] as List<dynamic>)
        .map((e) => TileType.fromId(e as String))
        .toList();
    if (tiles.length != n) throw const FormatException('tiles length mismatch');
    final age = Int32List.fromList(
      (json['tileAge'] as List<dynamic>)
          .map((e) => (e as num).toInt())
          .toList(),
    );
    final pop = Float64List.fromList(
      (json['population'] as List<dynamic>)
          .map((e) => (e as num).toDouble())
          .toList(),
    );
    if (age.length != n || pop.length != n) {
      throw const FormatException('array length mismatch');
    }
    return WorldState._(
      width: width,
      height: height,
      tiles: tiles,
      tileAge: age,
      population: pop,
      tick: json['tick'] as int,
      budgetKEur: json['budgetKEur'] == 'unlimited'
          ? double.infinity
          : (json['budgetKEur'] as num).toDouble(),
      seed: json['seed'] as int,
    );
  }

  /// Small deterministic hash of the state (FNV-1a over the JSON text) for
  /// replay verification and multiplayer sync checks.
  int hash() {
    final text = toJson().toString();
    var h = 0x811C9DC5;
    for (var i = 0; i < text.length; i++) {
      h ^= text.codeUnitAt(i);
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h;
  }
}
