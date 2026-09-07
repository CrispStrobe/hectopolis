// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:stadtbau_sim/stadtbau_sim.dart';

import 'save_store.dart';

/// Colour overlays the player can toggle on the map.
enum MapOverlay {
  none,
  noise,
  air,
  heat,
  green,
  retail,
  jobs,
  habitat,
  traffic,
  attractiveness,
}

/// Read-only result of applying a prospective tile placement to a copy of the
/// current simulation. The renderer uses this for the ghost tile, affected
/// cells and score deltas; the authoritative simulation is never mutated.
class PlacementPreview {
  const PlacementPreview({
    required this.cell,
    required this.tile,
    required this.costKEur,
    required this.error,
    required this.indicatorDeltas,
    required this.affectedCells,
    required this.affectedOverlay,
  });

  final int cell;
  final TileType tile;
  final double? costKEur;
  final CommandError? error;
  final Map<Indicator, double> indicatorDeltas;
  final Set<int> affectedCells;
  final MapOverlay affectedOverlay;

  bool get isValid => error == null;
}

/// UI-facing state around the simulation: level, brush, overlay, selection,
/// clock, autosave.
class GameController extends ChangeNotifier {
  GameController({int size = 16, SaveStore? store})
    : sim = Simulation.sandbox(width: size, height: size),
      _store = store; // ignore: prefer_initializing_formals

  final SaveStore? _store;
  Timer? _saveTimer;

  Simulation sim;

  /// The level being played, or null for the sandbox.
  Level? level;
  LevelProgress? progress;

  bool simpleMode = false;

  void toggleSimpleMode() {
    simpleMode = !simpleMode;
    notifyListeners();
  }

  /// Set once when the level ends (time up or all goals met); the UI shows
  /// the result dialog and then clears it via [acknowledgeEnd].
  bool endPending = false;
  bool _endShown = false;

  TileType? brush;
  MapOverlay overlay = MapOverlay.none;
  int? selectedCell;
  int? hoverCell;

  /// Increments after every successful model mutation. It lets animation code
  /// distinguish a simulation change from hover/selection notifications.
  int visualRevision = 0;

  PlacementPreview? _cachedPreview;
  int _previewRevision = -1;
  int? _previewCell;
  TileType? _previewTile;
  int _previewChangedMs = 0;
  bool _previewComplete = false;

  /// Cell the keyboard cursor sits on, or null while the keyboard is unused
  /// (task T-203). Drawn with a double outline, distinct from the selection.
  int? cursorCell;
  CommandError? lastError;

  /// 0 = paused, otherwise months per second.
  int speed = 0;
  Timer? _timer;

  static const speeds = [1, 3, 10];

  int get width => sim.state.width;
  int get height => sim.state.height;

  /// Restore the autosave, if any. Returns whether a game was restored.
  Future<bool> restore() async {
    final saved = await _store?.load();
    if (saved == null) return false;
    final levelId = saved.levelId;
    final lvl = levelId == null ? null : Level.byId(levelId);
    if (levelId != null && lvl == null) return false;
    _reset();
    level = lvl;
    sim = lvl == null
        ? Simulation(state: saved.state)
        : lvl.resume(saved.state);
    _evaluate();
    _endShown = endPending; // do not re-announce an already finished level
    endPending = false;
    notifyListeners();
    return true;
  }

  void startSandbox(int w, int h) {
    _reset();
    level = null;
    sim = Simulation.sandbox(width: w, height: h);
    _evaluate();
    _scheduleSave();
    notifyListeners();
  }

  void startLevel(Level lvl) {
    _reset();
    level = lvl;
    sim = lvl.start();
    _evaluate();
    _scheduleSave();
    notifyListeners();
  }

  void _reset() {
    _stopTimer();
    _saveTimer?.cancel();
    brush = null;
    selectedCell = null;
    hoverCell = null;
    cursorCell = null;
    lastError = null;
    speed = 0;
    progress = null;
    endPending = false;
    _endShown = false;
    visualRevision++;
    _cachedPreview = null;
  }

  void _evaluate() {
    final lvl = level;
    if (lvl == null) {
      progress = null;
      return;
    }
    final p = lvl.evaluate(sim.indicators);
    progress = p;
    if (!_endShown && (p.timeUp || p.allMet)) {
      _endShown = true;
      endPending = true;
      _stopTimer();
      speed = 0;
      _store?.recordStars(lvl.id, p.stars);
    }
  }

  void acknowledgeEnd() {
    endPending = false;
    notifyListeners();
  }

  void _scheduleSave() {
    final store = _store;
    if (store == null) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(
      const Duration(seconds: 2),
      () => store.save(level?.id, sim),
    );
  }

  void setBrush(TileType? t) {
    brush = brush == t ? null : t;
    notifyListeners();
  }

  /// The tile types the player may place, in palette order. Digits 1–9 and 0
  /// in the map view select from this list.
  List<TileType> get allowedTypes => sim.tileBudget.allowedTypes.toList();

  /// Select the [i]-th allowed tile (0-based) as the brush; out-of-range
  /// indices are ignored so that a digit without a tile does nothing.
  void selectBrushByIndex(int i) {
    final types = allowedTypes;
    if (i < 0 || i >= types.length) return;
    brush = types[i];
    notifyListeners();
  }

  void clearBrush() {
    if (brush == null) return;
    brush = null;
    notifyListeners();
  }

  /// Preview the active brush at the hover or keyboard-cursor cell.
  PlacementPreview? get placementPreview {
    final tile = brush;
    final cell = hoverCell ?? cursorCell;
    if (tile == null || cell == null) return null;
    final targetChanged =
        _previewCell != cell ||
        _previewTile != tile ||
        _previewRevision != visualRevision;
    if (targetChanged) {
      _previewCell = cell;
      _previewTile = tile;
      _previewRevision = visualRevision;
      _previewChangedMs = DateTime.now().millisecondsSinceEpoch;
      _previewComplete = false;
      _cachedPreview = _buildPlacementPreview(cell, tile, forecast: false);
    }
    final cached = _cachedPreview;
    if (_previewComplete) {
      return cached;
    }
    if (DateTime.now().millisecondsSinceEpoch - _previewChangedMs >= 90) {
      _cachedPreview = _buildPlacementPreview(cell, tile);
      _previewComplete = true;
    }
    return _cachedPreview;
  }

  PlacementPreview _buildPlacementPreview(
    int cell,
    TileType tile, {
    bool forecast = true,
  }) {
    final x = cell % width;
    final y = cell ~/ width;
    CommandError? error;
    final cost = sim.placementCost(x, y, tile);
    if (!sim.tileBudget.allowed(tile)) {
      error = CommandError.tileNotAllowed;
    } else if (cost == null) {
      error = CommandError.sameTile;
    } else if ((sim.tileBudget.remaining(tile) ?? 1) <= 0) {
      error = CommandError.tileExhausted;
    } else if (cost > sim.state.budgetKEur) {
      error = CommandError.insufficientBudget;
    }
    if (error != null) {
      return PlacementPreview(
        cell: cell,
        tile: tile,
        costKEur: cost,
        error: error,
        indicatorDeltas: const {},
        affectedCells: {cell},
        affectedOverlay: _previewOverlay(tile),
      );
    }
    if (!forecast) {
      return PlacementPreview(
        cell: cell,
        tile: tile,
        costKEur: cost,
        error: null,
        indicatorDeltas: const {},
        affectedCells: {cell},
        affectedOverlay: _previewOverlay(tile),
      );
    }

    final prospective = Simulation(state: sim.state.copy(), params: sim.params);
    prospective.apply(PlaceTile(x, y, tile));
    final deltas = <Indicator, double>{
      for (final indicator in Indicator.values)
        indicator:
            prospective.indicators.score(indicator) -
            sim.indicators.score(indicator),
    };
    final affectedOverlay = _previewOverlay(tile);
    final affected = <int>{cell};
    for (var i = 0; i < sim.state.cellCount; i++) {
      if (_fieldDifference(affectedOverlay, sim, prospective, i) >
          _previewThreshold(affectedOverlay)) {
        affected.add(i);
      }
    }
    return PlacementPreview(
      cell: cell,
      tile: tile,
      costKEur: cost,
      error: null,
      indicatorDeltas: deltas,
      affectedCells: affected,
      affectedOverlay: affectedOverlay,
    );
  }

  static MapOverlay _previewOverlay(TileType tile) => switch (tile) {
    TileType.forest || TileType.meadow => MapOverlay.habitat,
    TileType.water || TileType.park => MapOverlay.green,
    TileType.cropland => MapOverlay.heat,
    TileType.housingLow || TileType.housingHigh => MapOverlay.attractiveness,
    TileType.commercial => MapOverlay.retail,
    TileType.industry => MapOverlay.air,
    TileType.road => MapOverlay.noise,
  };

  static double _previewThreshold(MapOverlay overlay) => switch (overlay) {
    MapOverlay.noise => 0.15,
    MapOverlay.air || MapOverlay.traffic => 0.1,
    _ => 0.005,
  };

  static double _fieldDifference(
    MapOverlay overlay,
    Simulation before,
    Simulation after,
    int i,
  ) {
    final a = before.fields;
    final b = after.fields;
    return switch (overlay) {
      MapOverlay.noise => (b.noiseDb[i] - a.noiseDb[i]).abs(),
      MapOverlay.air => (b.airIndex[i] - a.airIndex[i]).abs(),
      MapOverlay.heat => (b.heatDeltaC[i] - a.heatDeltaC[i]).abs(),
      MapOverlay.green => (b.greenAccess[i] - a.greenAccess[i]).abs(),
      MapOverlay.retail => (b.retailAccess[i] - a.retailAccess[i]).abs(),
      MapOverlay.jobs => (b.jobAccess[i] - a.jobAccess[i]).abs(),
      MapOverlay.habitat => (b.habitatQuality[i] - a.habitatQuality[i]).abs(),
      MapOverlay.traffic => (b.traffic[i] - a.traffic[i]).abs(),
      MapOverlay.attractiveness =>
        (b.attractiveness[i] - a.attractiveness[i]).abs(),
      MapOverlay.none => 0,
    };
  }

  /// Move the keyboard cursor by [dx]/[dy] cells, clamped to the grid. The
  /// first move only places the cursor (on the selection, else the centre) so
  /// that the player sees where it is before it starts moving. The cursor
  /// drives the inspector selection as well.
  void moveCursor(int dx, int dy) {
    final anchor =
        cursorCell ?? selectedCell ?? sim.state.index(width ~/ 2, height ~/ 2);
    final first = cursorCell == null;
    final x = (anchor % width + (first ? 0 : dx)).clamp(0, width - 1);
    final y = (anchor ~/ width + (first ? 0 : dy)).clamp(0, height - 1);
    setCursor(sim.state.index(x, y));
  }

  void setCursor(int? cell) {
    cursorCell = cell;
    if (cell != null) selectedCell = cell;
    notifyListeners();
  }

  /// Enter/Space: place the brush at the cursor, or select the cell for the
  /// inspector when no brush is active. Returns whether a tile was placed.
  bool activateCursor() {
    final cell = cursorCell;
    if (cell == null) return false;
    final t = brush;
    if (t == null) {
      select(cell);
      return false;
    }
    return place(cell % width, cell ~/ width, t);
  }

  /// Delete/Backspace: clear the cell under the cursor.
  bool clearCursor() {
    final cell = cursorCell;
    if (cell == null) return false;
    return clear(cell % width, cell ~/ width);
  }

  void setOverlay(MapOverlay o) {
    overlay = o;
    notifyListeners();
  }

  void select(int? cell) {
    selectedCell = cell;
    notifyListeners();
  }

  void setHover(int? cell) {
    if (hoverCell == cell) return;
    hoverCell = cell;
    notifyListeners();
  }

  bool place(int x, int y, TileType t) {
    final result = sim.apply(PlaceTile(x, y, t));
    lastError = result.error;
    selectedCell = sim.state.index(x, y);
    if (result.ok) {
      visualRevision++;
      _cachedPreview = null;
      _evaluate();
      _scheduleSave();
    }
    notifyListeners();
    return result.ok;
  }

  bool clear(int x, int y) {
    final result = sim.apply(RemoveTile(x, y));
    lastError = result.error;
    if (result.ok) {
      visualRevision++;
      _cachedPreview = null;
      _evaluate();
      _scheduleSave();
    }
    notifyListeners();
    return result.ok;
  }

  void step() {
    sim.apply(const AdvanceTick());
    visualRevision++;
    _cachedPreview = null;
    _evaluate();
    _scheduleSave();
    notifyListeners();
  }

  void setSpeed(int monthsPerSecond) {
    speed = monthsPerSecond;
    _stopTimer();
    if (speed > 0) {
      _timer = Timer.periodic(
        Duration(milliseconds: 1000 ~/ speed),
        (_) => step(),
      );
    }
    notifyListeners();
  }

  void togglePlay() => setSpeed(speed == 0 ? speeds.first : 0);

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// Value of the active overlay at [cell], normalised to 0–1 for colouring.
  double overlayValue(int cell) {
    final f = sim.fields;
    switch (overlay) {
      case MapOverlay.none:
        return 0;
      case MapOverlay.noise:
        return ((f.noiseDb[cell] - 35) / 40).clamp(0, 1);
      case MapOverlay.air:
        return (1 - f.airIndex[cell] / 100).clamp(0, 1);
      case MapOverlay.heat:
        return (f.heatDeltaC[cell] / sim.params.heat.uhiMaxC).clamp(0, 1);
      case MapOverlay.green:
        return f.greenAccess[cell];
      case MapOverlay.retail:
        return f.retailAccess[cell];
      case MapOverlay.jobs:
        return f.jobAccess[cell];
      case MapOverlay.habitat:
        return f.habitatQuality[cell];
      case MapOverlay.traffic:
        return (f.traffic[cell] / 20000).clamp(0, 1);
      case MapOverlay.attractiveness:
        return f.attractiveness[cell];
    }
  }

  /// Whether high overlay values are "bad" (drawn warm) or "good" (drawn cool).
  bool get overlayHighIsBad => switch (overlay) {
    MapOverlay.noise ||
    MapOverlay.air ||
    MapOverlay.heat ||
    MapOverlay.traffic => true,
    _ => false,
  };

  @override
  void dispose() {
    _stopTimer();
    _saveTimer?.cancel();
    super.dispose();
  }
}
