// SPDX-License-Identifier: AGPL-3.0-or-later
import 'commands.dart';
import 'fields.dart';
import 'indicators.dart';
import 'model/access.dart';
import 'model/air.dart' as air_model;
import 'model/commute.dart';
import 'model/habitat.dart';
import 'model/heat.dart';
import 'model/noise.dart' as noise_model;
import 'model/stocks.dart';
import 'params.dart';
import 'tile_type.dart';
import 'world.dart';

/// Which tiles the player may place and how many (null = unlimited).
class TileBudget {
  TileBudget(Map<TileType, int?> remaining) : _remaining = Map.of(remaining);

  /// Everything unlimited.
  TileBudget.unlimited()
    : _remaining = {for (final t in TileType.values) t: null};

  final Map<TileType, int?> _remaining;

  /// An independent snapshot, including finite remaining counts.
  TileBudget copy() => TileBudget(_remaining);

  bool allowed(TileType t) => _remaining.containsKey(t);

  /// Remaining count, or null when unlimited.
  int? remaining(TileType t) => _remaining[t];

  Iterable<TileType> get allowedTypes => _remaining.keys;

  bool _take(TileType t) {
    if (!_remaining.containsKey(t)) return false;
    final r = _remaining[t];
    if (r == null) return true;
    if (r <= 0) return false;
    _remaining[t] = r - 1;
    return true;
  }

  void _giveBack(TileType t) {
    final r = _remaining[t];
    if (r != null) _remaining[t] = r + 1;
  }
}

/// The game engine: owns the state, applies commands, advances ticks and
/// exposes fields and indicators. Deterministic for a given command log.
class Simulation {
  Simulation({required this.state, SimParams? params, TileBudget? tileBudget})
    : params = params ?? SimParams.defaults(),
      tileBudget = tileBudget ?? TileBudget.unlimited(),
      fields = Fields(state.cellCount) {
    recompute();
  }

  /// A 16×16 sandbox with a few starting tiles.
  factory Simulation.sandbox({int width = 16, int height = 16, int seed = 1}) {
    final params = SimParams.defaults();
    final w = WorldState.empty(
      width: width,
      height: height,
      budgetKEur: double.infinity,
      seed: seed,
    );
    return Simulation(state: w, params: params);
  }

  final WorldState state;
  final SimParams params;
  final TileBudget tileBudget;
  final Fields fields;
  final List<CommandRecord> log = [];

  late IndicatorSnapshot indicators;
  double _lastBudgetDelta = 0;

  /// An independent snapshot suitable for forecasts and UI history.
  Simulation copy() {
    final result = Simulation(
      state: state.copy(),
      params: params,
      tileBudget: tileBudget.copy(),
    );
    result
      .._lastBudgetDelta = _lastBudgetDelta
      ..log.addAll(log)
      ..recompute();
    return result;
  }

  /// Recompute all fields and indicators from the current state without
  /// advancing time. Called after every placement.
  void recompute() {
    _computeFields();
    indicators = computeIndicators(
      state,
      params,
      fields,
      budgetDeltaKEur: _lastBudgetDelta,
      co2TonsPerYear: estimateCo2(state, params, fields),
    );
  }

  void _computeFields() {
    computeCommute(state, params, fields);
    noise_model.computeNoise(state, params, fields);
    air_model.computeAir(state, params, fields);
    computeHeat(state, params, fields);
    computeAccess(state, params, fields);
    computeHabitat(state, params, fields);
    computeAttractiveness(state, params, fields);
  }

  /// Noise sources reaching (x, y), by tile type, loudest first.
  List<noise_model.Contribution> explainNoise(int x, int y) =>
      noise_model.explainNoise(state, params, fields, state.index(x, y));

  /// Air pollution sources reaching (x, y), by tile type, largest first.
  List<noise_model.Contribution> explainAir(int x, int y) =>
      air_model.explainAir(state, params, fields, state.index(x, y));

  /// Cost in kEUR of placing [tile] at (x, y), or null if not placeable.
  double? placementCost(int x, int y, TileType tile) {
    if (!state.inBounds(x, y)) return null;
    final current = state.tileAt(x, y);
    if (current == tile) return null;
    var cost = params.tile(tile).buildCostKEur.value;
    if (params.tile(current).category.isBuilt)
      cost += params.economy.demolitionCostKEur;
    return cost;
  }

  CommandResult apply(Command command) {
    final result = switch (command) {
      PlaceTile(:final x, :final y, :final tile) => _place(x, y, tile),
      RemoveTile(:final x, :final y) => _remove(x, y),
      AdvanceTick(:final count) => _tick(count),
    };
    if (result.ok) log.add(CommandRecord(state.tick, command));
    return result;
  }

  CommandResult _place(int x, int y, TileType tile) {
    if (!state.inBounds(x, y))
      return const CommandResult.failed(CommandError.outOfBounds);
    if (!tileBudget.allowed(tile))
      return const CommandResult.failed(CommandError.tileNotAllowed);
    final cost = placementCost(x, y, tile);
    if (cost == null) return const CommandResult.failed(CommandError.sameTile);
    final remaining = tileBudget.remaining(tile);
    if (remaining != null && remaining <= 0)
      return const CommandResult.failed(CommandError.tileExhausted);
    if (cost > state.budgetKEur)
      return const CommandResult.failed(CommandError.insufficientBudget);
    tileBudget._take(tile);
    final i = state.index(x, y);
    final previous = state.tiles[i];
    tileBudget._giveBack(previous);
    state.tiles[i] = tile;
    state.tileAge[i] = 0;
    state.population[i] = 0;
    state.budgetKEur -= cost;
    recompute();
    return CommandResult.ok(costKEur: cost);
  }

  CommandResult _remove(int x, int y) {
    if (!state.inBounds(x, y))
      return const CommandResult.failed(CommandError.outOfBounds);
    final i = state.index(x, y);
    final current = state.tiles[i];
    if (current == TileType.terrain)
      return const CommandResult.failed(CommandError.sameTile);
    final cost = params.tile(current).category.isBuilt
        ? params.economy.demolitionCostKEur
        : 0.0;
    if (cost > state.budgetKEur)
      return const CommandResult.failed(CommandError.insufficientBudget);
    tileBudget._giveBack(current);
    state.tiles[i] = TileType.terrain;
    state.tileAge[i] = 0;
    state.population[i] = 0;
    state.budgetKEur -= cost;
    recompute();
    return CommandResult.ok(costKEur: cost);
  }

  CommandResult _tick(int count) {
    // Fields are always current at the start of a tick (constructor,
    // placement and the previous tick recompute them), so stocks advance on
    // them directly and the fields are recomputed once afterwards.
    for (var k = 0; k < count; k++) {
      final delta = advanceStocks(state, params, fields);
      _lastBudgetDelta = delta.netKEur;
      _computeFields();
      indicators = computeIndicators(
        state,
        params,
        fields,
        budgetDeltaKEur: delta.netKEur,
        co2TonsPerYear: delta.co2TonsPerYear,
      );
    }
    return const CommandResult.ok();
  }

  /// Rebuild a simulation by replaying a command log onto an initial state.
  static Simulation replay(
    WorldState initial,
    List<CommandRecord> records, {
    SimParams? params,
  }) {
    final sim = Simulation(state: initial.copy(), params: params);
    for (final r in records) {
      sim.apply(r.command);
    }
    return sim;
  }

  Map<String, dynamic> toJson() => {
    'state': state.toJson(),
    'log': [for (final r in log) r.toJson()],
  };
}
