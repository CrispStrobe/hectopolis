// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:stadtbau_sim/stadtbau_sim.dart';

import '../game/game_controller.dart';
import '../l10n/generated/app_localizations.dart';
import 'tile_style.dart';

/// Zoom and pan state of the map (task T-202).
///
/// Owned by the widget layer, not by [GameController], so that the controller
/// stays free of Flutter widget imports. The map is a square whose unscaled
/// size equals the viewport, so scale 1 fits the whole map and is the minimum;
/// the translation is clamped so that the map always covers the viewport.
class MapViewController {
  static const double minScale = 1;
  static const double maxScale = 4;
  static const double _step = 1.5;

  final TransformationController transformation = TransformationController();

  /// Side length of the square viewport, written by [MapView] on every layout.
  double viewportSide = 0;

  /// The current uniform scale factor.
  double get scale => transformation.value.getMaxScaleOnAxis();

  Offset get _translation {
    final t = transformation.value.getTranslation();
    return Offset(t.x, t.y);
  }

  void zoomIn() => zoomBy(_step);

  void zoomOut() => zoomBy(1 / _step);

  /// Multiply the current scale by [factor], keeping the viewport centre.
  void zoomBy(double factor) => zoomTo(scale * factor);

  /// Scale to [target] (clamped) around the centre of the viewport.
  void zoomTo(double target) {
    final side = viewportSide;
    if (side <= 0) return;
    final next = target.clamp(minScale, maxScale);
    final old = scale;
    final t = _translation;
    final focus = Offset(side / 2, side / 2);
    // Scene point currently under the focus stays under the focus.
    final sx = (focus.dx - t.dx) / old;
    final sy = (focus.dy - t.dy) / old;
    _apply(next, Offset(focus.dx - next * sx, focus.dy - next * sy));
  }

  /// Back to "whole map visible".
  void reset() {
    transformation.value = Matrix4.identity();
  }

  /// Pan so that [rect] (in scene/map coordinates) is inside the viewport.
  /// Used to follow the keyboard cursor while zoomed in.
  void revealScene(Rect rect) {
    final side = viewportSide;
    if (side <= 0) return;
    final s = scale;
    final t = _translation;
    double fit(double value, double lo, double hi) {
      var v = value;
      if (s * lo + v < 0) v = -s * lo;
      if (s * hi + v > side) v = side - s * hi;
      return v;
    }

    _apply(
      s,
      Offset(
        fit(t.dx, rect.left, rect.right),
        fit(t.dy, rect.top, rect.bottom),
      ),
    );
  }

  /// Write scale and translation, clamping the translation so that the map
  /// cannot be dragged (partly) out of the viewport.
  void _apply(double scale, Offset translation) {
    final side = viewportSide;
    final limit = side * (1 - scale); // <= 0
    final tx = translation.dx.clamp(limit, 0.0);
    final ty = translation.dy.clamp(limit, 0.0);
    transformation.value = Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setEntry(0, 3, tx)
      ..setEntry(1, 3, ty);
  }

  void dispose() => transformation.dispose();
}

/// The playing field: a square grid painted with a CustomPainter inside an
/// [InteractiveViewer] (pinch / wheel zoom, drag pan), accepting drops from the
/// palette, taps (brush placement / inspection), long-presses (clear) and
/// keyboard input (task T-203).
class MapView extends StatefulWidget {
  const MapView({super.key, required this.controller, this.mapController});

  final GameController controller;

  /// Zoom/pan state; created internally when not supplied.
  final MapViewController? mapController;

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> with TickerProviderStateMixin {
  final _viewportKey = GlobalKey();
  final _focus = FocusNode(debugLabel: 'map');
  MapViewController? _own;
  late final AnimationController _motion;
  late final AnimationController _overlayTransition;
  late int _lastVisualRevision;
  late MapOverlay _lastOverlay;
  late List<double> _overlayFrom;
  late List<double> _overlayTo;
  late List<TileType> _previousTiles;
  final Map<int, int> _constructionStartedMs = {};
  bool _platformReduceMotion = false;
  late bool _lastAmbientAnimations;
  late bool _lastEffectAnimations;
  late bool _lastTrafficAnimations;
  late bool _lastEnvironmentAnimations;
  late bool _lastCityActivityAnimations;

  GameController get c => widget.controller;

  MapViewController get m =>
      widget.mapController ?? (_own ??= MapViewController());

  /// Physical keyboards are the norm on desktop and web, so grab focus there;
  /// on touch platforms focus follows the first tap instead.
  static bool get _autofocus =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows;

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
    _overlayTransition = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    )..value = 1;
    _lastVisualRevision = c.visualRevision;
    _lastOverlay = c.overlay;
    _overlayTo = _captureOverlay();
    _overlayFrom = List<double>.of(_overlayTo);
    _previousTiles = List<TileType>.of(c.sim.state.tiles);
    _lastAmbientAnimations = c.experience.ambientAnimations;
    _lastEffectAnimations = c.experience.effectAnimations;
    _lastTrafficAnimations = c.experience.trafficAnimations;
    _lastEnvironmentAnimations = c.experience.environmentAnimations;
    _lastCityActivityAnimations = c.experience.cityActivityAnimations;
    c.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant MapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_onControllerChanged);
    widget.controller.addListener(_onControllerChanged);
    _lastVisualRevision = c.visualRevision;
    _lastOverlay = c.overlay;
    _overlayTo = _captureOverlay();
    _overlayFrom = List<double>.of(_overlayTo);
    _previousTiles = List<TileType>.of(c.sim.state.tiles);
    _lastAmbientAnimations = c.experience.ambientAnimations;
    _lastEffectAnimations = c.experience.effectAnimations;
    _lastTrafficAnimations = c.experience.trafficAnimations;
    _lastEnvironmentAnimations = c.experience.environmentAnimations;
    _lastCityActivityAnimations = c.experience.cityActivityAnimations;
    _constructionStartedMs.clear();
    _syncMotion();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion == _platformReduceMotion) return;
    _platformReduceMotion = reduceMotion;
    _syncMotion();
  }

  void _syncMotion() {
    final ambientLayerEnabled =
        c.experience.ambientAnimations &&
        (c.experience.trafficAnimations ||
            c.experience.environmentAnimations ||
            c.experience.cityActivityAnimations);
    final shouldAnimate =
        !_platformReduceMotion &&
        (ambientLayerEnabled || c.experience.effectAnimations);
    if (!shouldAnimate) {
      _motion.stop();
      _motion.value = 0;
      _overlayTransition.value = 1;
    } else {
      _motion.repeat();
    }
  }

  List<double> _captureOverlay() => [
    for (var i = 0; i < c.sim.state.cellCount; i++)
      c.overlay == MapOverlay.none ? 0 : c.overlayValue(i),
  ];

  void _onControllerChanged() {
    final revisionChanged = c.visualRevision != _lastVisualRevision;
    final overlayChanged = c.overlay != _lastOverlay;
    final animationChanged =
        c.experience.ambientAnimations != _lastAmbientAnimations ||
        c.experience.effectAnimations != _lastEffectAnimations ||
        c.experience.trafficAnimations != _lastTrafficAnimations ||
        c.experience.environmentAnimations != _lastEnvironmentAnimations ||
        c.experience.cityActivityAnimations != _lastCityActivityAnimations;
    if (animationChanged) {
      _lastAmbientAnimations = c.experience.ambientAnimations;
      _lastEffectAnimations = c.experience.effectAnimations;
      _lastTrafficAnimations = c.experience.trafficAnimations;
      _lastEnvironmentAnimations = c.experience.environmentAnimations;
      _lastCityActivityAnimations = c.experience.cityActivityAnimations;
      _syncMotion();
    }
    if (!revisionChanged && !overlayChanged && !animationChanged) return;

    if (revisionChanged) {
      final tiles = c.sim.state.tiles;
      if (tiles.length == _previousTiles.length) {
        final now = DateTime.now().millisecondsSinceEpoch;
        for (var i = 0; i < tiles.length; i++) {
          if (tiles[i] != _previousTiles[i] &&
              c.sim.params.tile(tiles[i]).category.isBuilt) {
            _constructionStartedMs[i] = now;
          }
        }
      } else {
        _constructionStartedMs.clear();
      }
      _previousTiles = List<TileType>.of(tiles);
    }

    final progress = Curves.easeOutCubic.transform(_overlayTransition.value);
    final current =
        overlayChanged || _overlayFrom.length != c.sim.state.cellCount
        ? List<double>.filled(c.sim.state.cellCount, 0)
        : [
            for (var i = 0; i < _overlayFrom.length; i++)
              _overlayFrom[i] + (_overlayTo[i] - _overlayFrom[i]) * progress,
          ];
    _overlayFrom = current;
    _overlayTo = _captureOverlay();
    if (_platformReduceMotion || !c.experience.effectAnimations) {
      _overlayTransition.value = 1;
    } else {
      _overlayTransition.forward(from: 0);
    }
    _lastVisualRevision = c.visualRevision;
    _lastOverlay = c.overlay;
  }

  @override
  void dispose() {
    c.removeListener(_onControllerChanged);
    _motion.dispose();
    _overlayTransition.dispose();
    _focus.dispose();
    _own?.dispose();
    super.dispose();
  }

  /// Global pointer position -> cell index, through the zoom/pan transform.
  int? _cellAtGlobal(Offset global, Size size) {
    final box = _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    return _cellAtLocal(
      m.transformation.toScene(box.globalToLocal(global)),
      size,
    );
  }

  /// Position in map (scene) coordinates -> cell index.
  int? _cellAtLocal(Offset local, Size size) {
    final cell = size.width / c.width;
    final x = (local.dx / cell).floor();
    final y = (local.dy / cell).floor();
    if (!c.sim.state.inBounds(x, y)) return null;
    return c.sim.state.index(x, y);
  }

  void _follow(Size size) {
    final cursor = c.cursorCell;
    if (cursor == null) return;
    final cell = size.width / c.width;
    m.revealScene(
      Rect.fromLTWH(
        (cursor % c.width) * cell,
        (cursor ~/ c.width) * cell,
        cell,
        cell,
      ),
    );
  }

  KeyEventResult _onKey(KeyEvent event, Size size) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final keyboard = HardwareKeyboard.instance;
    final command = keyboard.isControlPressed || keyboard.isMetaPressed;
    if (command && key == LogicalKeyboardKey.keyZ) {
      keyboard.isShiftPressed ? c.redo() : c.undo();
      return KeyEventResult.handled;
    }
    if (command && key == LogicalKeyboardKey.keyY) {
      c.redo();
      return KeyEventResult.handled;
    }
    final delta = _arrows[key];
    if (delta != null) {
      c.moveCursor(delta.dx.round(), delta.dy.round());
      _follow(size);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space) {
      c.activateCursor();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      c.clearCursor();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      c.clearBrush();
      return KeyEventResult.handled;
    }
    final digit = _digits[key];
    if (digit != null) {
      c.selectBrushByIndex(digit);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  static final _arrows = <LogicalKeyboardKey, Offset>{
    LogicalKeyboardKey.arrowLeft: const Offset(-1, 0),
    LogicalKeyboardKey.arrowRight: const Offset(1, 0),
    LogicalKeyboardKey.arrowUp: const Offset(0, -1),
    LogicalKeyboardKey.arrowDown: const Offset(0, 1),
  };

  /// 1–9 select the first nine allowed tiles, 0 the tenth.
  static final _digits = <LogicalKeyboardKey, int>{
    LogicalKeyboardKey.digit1: 0,
    LogicalKeyboardKey.digit2: 1,
    LogicalKeyboardKey.digit3: 2,
    LogicalKeyboardKey.digit4: 3,
    LogicalKeyboardKey.digit5: 4,
    LogicalKeyboardKey.digit6: 5,
    LogicalKeyboardKey.digit7: 6,
    LogicalKeyboardKey.digit8: 7,
    LogicalKeyboardKey.digit9: 8,
    LogicalKeyboardKey.digit0: 9,
    LogicalKeyboardKey.numpad1: 0,
    LogicalKeyboardKey.numpad2: 1,
    LogicalKeyboardKey.numpad3: 2,
    LogicalKeyboardKey.numpad4: 3,
    LogicalKeyboardKey.numpad5: 4,
    LogicalKeyboardKey.numpad6: 5,
    LogicalKeyboardKey.numpad7: 6,
    LogicalKeyboardKey.numpad8: 7,
    LogicalKeyboardKey.numpad9: 8,
    LogicalKeyboardKey.numpad0: 9,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.biggest.shortestSide;
        final size = Size(side, side);
        m.viewportSide = side;
        return Center(
          child: SizedBox(
            key: _viewportKey,
            width: side,
            height: side,
            child: Focus(
              focusNode: _focus,
              autofocus: _autofocus,
              onKeyEvent: (node, event) => _onKey(event, size),
              child: DragTarget<TileType>(
                onMove: (details) =>
                    c.setHover(_cellAtGlobal(details.offset, size)),
                onLeave: (_) => c.setHover(null),
                onAcceptWithDetails: (details) {
                  final cell = _cellAtGlobal(details.offset, size);
                  c.setHover(null);
                  if (cell != null) {
                    c.place(cell % c.width, cell ~/ c.width, details.data);
                  }
                },
                builder: (context, candidates, rejected) {
                  return ListenableBuilder(
                    listenable: c,
                    builder: (context, _) => Stack(
                      children: [
                        MouseRegion(
                          onHover: (event) =>
                              c.setHover(_cellAtGlobal(event.position, size)),
                          onExit: (_) => c.setHover(null),
                          child: InteractiveViewer(
                            transformationController: m.transformation,
                            minScale: MapViewController.minScale,
                            maxScale: MapViewController.maxScale,
                            boundaryMargin: EdgeInsets.zero,
                            panEnabled: c.brush == null,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              // Inside the InteractiveViewer, so localPosition is
                              // already in map coordinates at any zoom level.
                              onTapUp: (d) {
                                _focus.requestFocus();
                                final cell = _cellAtLocal(
                                  d.localPosition,
                                  size,
                                );
                                if (cell == null) return;
                                final brush = c.brush;
                                if (brush != null) {
                                  c.place(
                                    cell % c.width,
                                    cell ~/ c.width,
                                    brush,
                                  );
                                } else {
                                  c.select(cell);
                                }
                              },
                              onPanStart: c.brush == null
                                  ? null
                                  : (d) {
                                      _focus.requestFocus();
                                      final cell = _cellAtLocal(
                                        d.localPosition,
                                        size,
                                      );
                                      if (cell != null) {
                                        c.setHover(cell);
                                        c.place(
                                          cell % c.width,
                                          cell ~/ c.width,
                                          c.brush!,
                                        );
                                      }
                                    },
                              onPanUpdate: c.brush == null
                                  ? null
                                  : (d) {
                                      final cell = _cellAtLocal(
                                        d.localPosition,
                                        size,
                                      );
                                      if (cell != null) {
                                        c.setHover(cell);
                                        c.place(
                                          cell % c.width,
                                          cell ~/ c.width,
                                          c.brush!,
                                        );
                                      }
                                    },
                              onLongPressStart: (d) {
                                _focus.requestFocus();
                                final cell = _cellAtLocal(
                                  d.localPosition,
                                  size,
                                );
                                if (cell != null) {
                                  c.clear(cell % c.width, cell ~/ c.width);
                                }
                              },
                              child: ListenableBuilder(
                                listenable: Listenable.merge([
                                  c,
                                  m.transformation,
                                  _motion,
                                  _overlayTransition,
                                ]),
                                builder: (context, _) => Semantics(
                                  label: l10n.keyboardHint,
                                  child: CustomPaint(
                                    size: size,
                                    painter: _MapPainter(
                                      c,
                                      Theme.of(context),
                                      m.scale,
                                      motion: _motion.value,
                                      overlayProgress: Curves.easeOutCubic
                                          .transform(_overlayTransition.value),
                                      overlayFrom: _overlayFrom,
                                      overlayTo: _overlayTo,
                                      constructionStartedMs:
                                          _constructionStartedMs,
                                      animateAmbient:
                                          !_platformReduceMotion &&
                                          c.experience.ambientAnimations,
                                      animateEffects:
                                          !_platformReduceMotion &&
                                          c.experience.effectAnimations,
                                      cleanVisuals: c.experience.cleanVisuals,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (c.placementPreview case final preview?)
                          Positioned(
                            top: 8,
                            right: 8,
                            child: _PlacementPreviewCard(
                              preview: preview,
                              simpleMode: c.simpleMode,
                            ),
                          ),
                        if (c.brush case final brush?)
                          Positioned(
                            left: 8,
                            bottom: 8,
                            child: _PlacementModeChip(
                              tile: brush,
                              onCancel: c.clearBrush,
                            ),
                          ),
                        if (c.lastImpact case final impact?)
                          Positioned(
                            right: 8,
                            bottom: 8,
                            child: _BuildImpactCard(
                              impact: impact,
                              simpleMode: c.simpleMode,
                              onClose: c.dismissImpact,
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PlacementModeChip extends StatelessWidget {
  const _PlacementModeChip({required this.tile, required this.onCancel});

  final TileType tile;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final style = TileStyle.of(tile);
    return InputChip(
      elevation: 3,
      avatar: Icon(style.icon, size: 18, color: style.iconColor),
      label: Text(l10n.placementMode(l10n.tileName(tile.id))),
      deleteIcon: const Icon(Icons.close, size: 18),
      deleteButtonTooltipMessage: l10n.actionCancelPlacement,
      onDeleted: onCancel,
    );
  }
}

class _PlacementPreviewCard extends StatelessWidget {
  const _PlacementPreviewCard({
    required this.preview,
    required this.simpleMode,
  });

  final PlacementPreview preview;
  final bool simpleMode;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final number = NumberFormat.decimalPatternDigits(
      locale: Localizations.localeOf(context).toString(),
      decimalDigits: 0,
    );
    final changes =
        preview.indicatorDeltas.entries
            .where((entry) => entry.value.isFinite && entry.value.abs() >= 0.05)
            .toList()
          ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
    final error = switch (preview.error) {
      CommandError.outOfBounds => l10n.errorOutOfBounds,
      CommandError.sameTile => l10n.errorSameTile,
      CommandError.insufficientBudget => l10n.errorInsufficientBudget,
      CommandError.tileNotAllowed => l10n.errorTileNotAllowed,
      CommandError.tileExhausted => l10n.errorTileExhausted,
      null => null,
    };
    final scheme = theme.colorScheme;
    return IgnorePointer(
      child: Card(
        elevation: 4,
        color: scheme.surface.withValues(alpha: 0.94),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 230),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      TileStyle.of(preview.tile).icon,
                      size: 18,
                      color: TileStyle.of(preview.tile).iconColor,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        l10n.placementPreviewTitle(
                          l10n.tileName(preview.tile.id),
                        ),
                      ),
                    ),
                  ],
                ),
                if (!simpleMode)
                  if (preview.costKEur case final cost?)
                    Text(
                      l10n.placementPreviewCost(l10n.kEur(number.format(cost))),
                      style: theme.textTheme.bodySmall,
                    ),
                if (error != null)
                  Text(
                    error,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.error,
                    ),
                  )
                else if (simpleMode)
                  Text(
                    _friendlyImpact(l10n, changes),
                    style: theme.textTheme.bodySmall,
                  )
                else if (changes.isEmpty)
                  Text(
                    l10n.placementPreviewNoScoreChange,
                    style: theme.textTheme.bodySmall,
                  )
                else
                  for (final change in changes.take(3))
                    Text(
                      '${l10n.indicatorName(change.key.name)} ${change.value >= 0 ? '+' : ''}${change.value.toStringAsFixed(1)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: change.value >= 0
                            ? const Color(0xFF2E7D32)
                            : scheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                if (preview.isValid && !simpleMode)
                  Text(
                    l10n.placementPreviewAffected(
                      preview.affectedCells.length,
                      l10n.overlayName(preview.affectedOverlay.name),
                    ),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _friendlyImpact(
  AppLocalizations l10n,
  List<MapEntry<Indicator, double>> changes,
) {
  if (changes.isEmpty) return l10n.impactSimpleSteady;
  final total = changes.fold<double>(0, (sum, entry) => sum + entry.value);
  final positive = changes.any((entry) => entry.value > 0.15);
  final negative = changes.any((entry) => entry.value < -0.15);
  if (positive && negative) return l10n.impactSimpleMixed;
  if (total > 0.15) return l10n.impactSimpleBetter;
  if (total < -0.15) return l10n.impactSimpleWorse;
  return l10n.impactSimpleSteady;
}

class _BuildImpactCard extends StatelessWidget {
  const _BuildImpactCard({
    required this.impact,
    required this.simpleMode,
    required this.onClose,
  });

  final BuildImpact impact;
  final bool simpleMode;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final changes =
        impact.indicatorDeltas.entries
            .where((entry) => entry.value.isFinite && entry.value.abs() >= 0.05)
            .toList()
          ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
    return Card(
      elevation: 5,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 240),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 6, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    impact.removed ? Icons.delete_outline : Icons.check_circle,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      impact.removed
                          ? l10n.impactRemoved(l10n.tileName(impact.tile.id))
                          : l10n.impactBuilt(l10n.tileName(impact.tile.id)),
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: l10n.actionClose,
                    icon: const Icon(Icons.close, size: 17),
                    onPressed: onClose,
                  ),
                ],
              ),
              if (simpleMode)
                Text(
                  _friendlyImpact(l10n, changes),
                  style: theme.textTheme.bodyMedium,
                )
              else if (changes.isEmpty)
                Text(
                  l10n.placementPreviewNoScoreChange,
                  style: theme.textTheme.bodySmall,
                )
              else
                for (final change in changes.take(3))
                  Text(
                    '${l10n.indicatorName(change.key.name)} ${change.value >= 0 ? '+' : ''}${change.value.toStringAsFixed(1)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: change.value >= 0
                          ? const Color(0xFF2E7D32)
                          : theme.colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              if (!simpleMode)
                Text(
                  l10n.placementPreviewAffected(
                    impact.affectedCells.length,
                    l10n.overlayName(impact.affectedOverlay.name),
                  ),
                  style: theme.textTheme.labelSmall,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A model-driven renderer. Static land-use remains legible while road
/// topology, traffic, forest maturity, construction and overlays animate from
/// values already present in the simulation.
class _MapPainter extends CustomPainter {
  _MapPainter(
    this.c,
    this.theme,
    this.scale, {
    required this.motion,
    required this.overlayProgress,
    required this.overlayFrom,
    required this.overlayTo,
    required this.constructionStartedMs,
    required this.animateAmbient,
    required this.animateEffects,
    required this.cleanVisuals,
  });

  final GameController c;
  final ThemeData theme;
  final double scale;
  final double motion;
  final double overlayProgress;
  final List<double> overlayFrom;
  final List<double> overlayTo;
  final Map<int, int> constructionStartedMs;
  final bool animateAmbient;
  final bool animateEffects;
  final bool cleanVisuals;

  /// Large maps automatically shed decorative detail while zoomed out.
  bool get _lowDetail =>
      cleanVisuals || (c.sim.state.cellCount > 1024 && scale < 1.35);

  @override
  void paint(Canvas canvas, Size size) {
    final state = c.sim.state;
    final cell = size.width / c.width;
    final hair = 1 / scale;
    final now = DateTime.now().millisecondsSinceEpoch;
    final grid = Paint()
      ..color = Colors.black.withValues(alpha: 0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = hair;

    Rect cellRect(int index) => Rect.fromLTWH(
      (index % c.width) * cell,
      (index ~/ c.width) * cell,
      cell,
      cell,
    );

    for (var i = 0; i < state.cellCount; i++) {
      final rect = cellRect(i);
      final construction = !animateEffects
          ? 1.0
          : ((now - (constructionStartedMs[i] ?? now - 1000)) / 900).clamp(
              0.0,
              1.0,
            );
      _drawTile(
        canvas,
        i,
        rect,
        construction: Curves.easeOutBack.transform(construction),
      );
      if (c.overlay != MapOverlay.none &&
          i < overlayFrom.length &&
          i < overlayTo.length) {
        final value =
            overlayFrom[i] + (overlayTo[i] - overlayFrom[i]) * overlayProgress;
        canvas.drawRect(
          rect,
          Paint()
            ..color = overlayColor(
              value,
              highIsBad: c.overlayHighIsBad,
            ).withValues(alpha: 0.56),
        );
        if (c.experience.causalHighlights &&
            _isCausalSource(c.overlay, state.tiles[i])) {
          canvas.drawCircle(
            rect.topRight + Offset(-rect.width * 0.14, rect.height * 0.14),
            math.max(1.5 / scale, rect.width * 0.055),
            Paint()
              ..color = theme.colorScheme.onSurface.withValues(alpha: 0.82)
              ..style = PaintingStyle.stroke
              ..strokeWidth = math.max(0.8 / scale, rect.width * 0.025),
          );
        }
      }
      canvas.drawRect(rect, grid);
    }

    if (animateAmbient && c.experience.trafficAnimations && !_lowDetail) {
      _drawTraffic(canvas, cell);
    }

    final impact = c.lastImpact;
    if (impact != null && c.experience.causalHighlights) {
      final age = now - impact.createdAtMs;
      if (age < 2600 || !animateEffects) {
        final fade = animateEffects ? (1 - age / 2600).clamp(0.0, 1.0) : 0.45;
        final color = theme.colorScheme.primary;
        for (final affected in impact.affectedCells) {
          canvas.drawRect(
            cellRect(affected).deflate(hair),
            Paint()
              ..color = color.withValues(alpha: 0.05 + fade * 0.16)
              ..style = PaintingStyle.fill,
          );
        }
        _outline(
          canvas,
          cellRect(impact.cell).deflate(2 * hair),
          color.withValues(alpha: 0.45 + fade * 0.55),
          3 * hair,
        );
      }
    }

    final preview = c.placementPreview;
    if (preview != null) {
      final color = preview.isValid
          ? theme.colorScheme.primary
          : theme.colorScheme.error;
      for (final affected in preview.affectedCells) {
        canvas.drawRect(
          cellRect(affected).deflate(hair),
          Paint()..color = color.withValues(alpha: 0.12),
        );
      }
      final rect = cellRect(preview.cell);
      if (preview.isValid) {
        canvas.saveLayer(
          rect,
          Paint()..color = Colors.white.withValues(alpha: 0.62),
        );
        _drawTile(
          canvas,
          preview.cell,
          rect,
          tileOverride: preview.tile,
          construction: 1,
        );
        canvas.restore();
      }
      _outline(canvas, rect, color, 3 * hair);
    }

    final hover = c.hoverCell;
    if (hover != null && preview == null) {
      _outline(canvas, cellRect(hover), theme.colorScheme.primary, 3 * hair);
    }
    final selected = c.selectedCell;
    if (selected != null) {
      _outline(
        canvas,
        cellRect(selected),
        theme.colorScheme.onSurface,
        2 * hair,
      );
    }
    final cursor = c.cursorCell;
    if (cursor != null) {
      final rect = cellRect(cursor);
      _outline(
        canvas,
        rect.deflate(hair),
        theme.colorScheme.onSurface,
        2 * hair,
      );
      _outline(
        canvas,
        rect.deflate(4 * hair),
        theme.colorScheme.surface,
        2 * hair,
      );
    }
  }

  void _drawTile(
    Canvas canvas,
    int index,
    Rect rect, {
    TileType? tileOverride,
    required double construction,
  }) {
    final state = c.sim.state;
    final tile = tileOverride ?? state.tiles[index];
    canvas.drawRect(rect, Paint()..color = _groundColor(tile));
    if (!_lowDetail) {
      canvas.drawRect(
        Rect.fromLTWH(rect.left, rect.top, rect.width, rect.height * 0.08),
        Paint()..color = Colors.white.withValues(alpha: 0.08),
      );
    }

    switch (tile) {
      case TileType.meadow:
        if (!_lowDetail) _drawMeadow(canvas, index, rect);
        break;
      case TileType.cropland:
        _drawCropland(canvas, index, rect);
        break;
      case TileType.forest:
        _drawForest(
          canvas,
          index,
          rect,
          tileOverride != null ? 1 : _maturity(index),
        );
        break;
      case TileType.water:
        _drawWater(canvas, index, rect);
        break;
      case TileType.park:
        _drawPark(canvas, index, rect);
        break;
      case TileType.road:
        _drawRoad(canvas, index, rect);
        break;
      case TileType.housingLow ||
          TileType.housingHigh ||
          TileType.commercial ||
          TileType.industry:
        _withConstruction(
          canvas,
          rect,
          construction,
          () => _drawBuilding(canvas, index, rect, tile),
        );
        break;
    }
    if (animateEffects &&
        c.sim.params.tile(tile).category.isBuilt &&
        construction < 0.98) {
      final frame = Paint()
        ..color = const Color(0xFFFFB300).withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1 / scale, rect.width * 0.045);
      canvas.drawRect(rect.deflate(rect.width * 0.16), frame);
      canvas.drawLine(
        rect.topLeft + Offset(rect.width * 0.16, rect.height * 0.16),
        rect.bottomRight - Offset(rect.width * 0.16, rect.height * 0.16),
        frame,
      );
    }
  }

  Color _groundColor(TileType tile) => switch (tile) {
    TileType.road => const Color(0xFF9FC58F),
    TileType.housingLow => const Color(0xFFC8D7AD),
    TileType.housingHigh => const Color(0xFFD8C8B8),
    TileType.commercial => const Color(0xFFD6C9E7),
    TileType.industry => const Color(0xFFBCC5C8),
    _ => TileStyle.of(tile).color,
  };

  void _withConstruction(
    Canvas canvas,
    Rect rect,
    double progress,
    VoidCallback draw,
  ) {
    canvas.save();
    canvas.translate(rect.center.dx, rect.center.dy);
    canvas.scale(progress, progress);
    canvas.translate(-rect.center.dx, -rect.center.dy);
    draw();
    canvas.restore();
  }

  void _drawMeadow(Canvas canvas, int index, Rect rect) {
    if (rect.width * scale < 14) return;
    final grass = Paint()
      ..color = const Color(0xFF4F8A51).withValues(alpha: 0.65)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.55 / scale, rect.width * 0.018)
      ..strokeCap = StrokeCap.round;
    for (var tuft = 0; tuft < 5; tuft++) {
      final x =
          rect.left + rect.width * (0.12 + _unit(index * 41 + tuft) * 0.76);
      final y =
          rect.top + rect.height * (0.28 + _unit(index * 59 + tuft) * 0.58);
      final h = rect.height * (0.07 + _unit(index * 73 + tuft) * 0.05);
      canvas.drawLine(Offset(x, y), Offset(x - h * 0.28, y - h), grass);
      canvas.drawLine(Offset(x, y), Offset(x + h * 0.30, y - h * 0.82), grass);
    }
    if (_unit(index * 101) > 0.48) {
      canvas.drawCircle(
        Offset(rect.left + rect.width * 0.68, rect.top + rect.height * 0.40),
        math.max(0.7 / scale, rect.width * 0.022),
        Paint()..color = const Color(0xFFFFF59D),
      );
    }
  }

  void _drawCropland(Canvas canvas, int index, Rect rect) {
    if (rect.width * scale < 10) return;
    final rows = Paint()
      ..color = const Color(0xFF8D6E3F).withValues(alpha: 0.46)
      ..strokeWidth = math.max(0.55 / scale, rect.width * 0.022);
    final horizontal = _unit(index * 113) > 0.5;
    for (var row = 1; row < 6; row++) {
      final p = row / 6;
      if (horizontal) {
        canvas.drawLine(
          Offset(rect.left, rect.top + rect.height * p),
          Offset(rect.right, rect.top + rect.height * p),
          rows,
        );
      } else {
        canvas.drawLine(
          Offset(rect.left + rect.width * p, rect.top),
          Offset(rect.left + rect.width * p, rect.bottom),
          rows,
        );
      }
    }
  }

  void _drawWater(Canvas canvas, int index, Rect rect) {
    final state = c.sim.state;
    final x = index % c.width;
    final y = index ~/ c.width;
    bool water(int nx, int ny) =>
        state.inBounds(nx, ny) && state.tileAt(nx, ny) == TileType.water;
    final shore = Paint()
      ..color = const Color(0xFFE7D7A5).withValues(alpha: 0.72)
      ..strokeWidth = math.max(0.8 / scale, rect.width * 0.045);
    if (!water(x - 1, y)) canvas.drawLine(rect.topLeft, rect.bottomLeft, shore);
    if (!water(x + 1, y)) {
      canvas.drawLine(rect.topRight, rect.bottomRight, shore);
    }
    if (!water(x, y - 1)) canvas.drawLine(rect.topLeft, rect.topRight, shore);
    if (!water(x, y + 1)) {
      canvas.drawLine(rect.bottomLeft, rect.bottomRight, shore);
    }
    if (_lowDetail ||
        !c.experience.environmentAnimations ||
        rect.width * scale < 18) {
      return;
    }
    for (var wave = 0; wave < 2; wave++) {
      final waveY = (motion * 0.35 + _unit(index * 37 + wave)) % 1;
      canvas.drawArc(
        Rect.fromCenter(
          center: Offset(
            rect.center.dx + (wave.isEven ? -0.12 : 0.14) * rect.width,
            rect.top + waveY * rect.height,
          ),
          width: rect.width * 0.38,
          height: rect.height * 0.12,
        ),
        0,
        math.pi,
        false,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.42)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(0.7 / scale, rect.width * 0.018),
      );
    }
  }

  void _drawPark(Canvas canvas, int index, Rect rect) {
    if (rect.width * scale < 11) return;
    final path = Paint()
      ..color = const Color(0xFFE8D7AD)
      ..strokeWidth = rect.width * 0.13
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(rect.left + rect.width * 0.05, rect.bottom - rect.height * 0.12),
      Offset(rect.right - rect.width * 0.05, rect.top + rect.height * 0.18),
      path,
    );
    _drawTree(
      canvas,
      Offset(rect.left + rect.width * 0.28, rect.top + rect.height * 0.30),
      rect.width * 0.12,
      0.82,
    );
    _drawTree(
      canvas,
      Offset(rect.left + rect.width * 0.70, rect.top + rect.height * 0.66),
      rect.width * 0.10,
      0.72,
    );
    if (!_lowDetail && rect.width * scale >= 24) {
      final bench = Paint()
        ..color = const Color(0xFF795548)
        ..strokeWidth = math.max(0.8 / scale, rect.width * 0.035)
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(rect.left + rect.width * 0.46, rect.top + rect.height * 0.68),
        Offset(rect.left + rect.width * 0.61, rect.top + rect.height * 0.61),
        bench,
      );
    }
  }

  void _drawBuilding(Canvas canvas, int index, Rect rect, TileType tile) {
    if (rect.width * scale < 11) return;
    switch (tile) {
      case TileType.housingLow:
        _drawLowHousing(canvas, index, rect);
      case TileType.housingHigh:
        _drawHighHousing(canvas, index, rect);
      case TileType.commercial:
        _drawCommercial(canvas, index, rect);
      case TileType.industry:
        _drawIndustry(canvas, index, rect);
      case _:
        break;
    }
  }

  void _drawLowHousing(Canvas canvas, int index, Rect rect) {
    final occupied = _occupancy(index);
    for (var house = 0; house < 2; house++) {
      final left = rect.left + rect.width * (house == 0 ? 0.13 : 0.55);
      final top = rect.top + rect.height * (house == 0 ? 0.22 : 0.52);
      final body = Rect.fromLTWH(
        left,
        top,
        rect.width * 0.29,
        rect.height * 0.24,
      );
      _shadowedRect(canvas, body, const Color(0xFFFFF3E0));
      final roof = Path()
        ..moveTo(body.left - rect.width * 0.035, body.top)
        ..lineTo(body.center.dx, body.top - rect.height * 0.13)
        ..lineTo(body.right + rect.width * 0.035, body.top)
        ..close();
      canvas.drawPath(
        roof,
        Paint()
          ..color = house == 0
              ? const Color(0xFFB5523B)
              : const Color(0xFF8D493A),
      );
      _window(
        canvas,
        body.center + Offset(0, body.height * 0.05),
        rect.width * 0.055,
        occupied,
        index + house,
      );
    }
  }

  void _drawHighHousing(Canvas canvas, int index, Rect rect) {
    final occupied = _occupancy(index);
    final blocks = [
      Rect.fromLTWH(
        rect.left + rect.width * 0.12,
        rect.top + rect.height * 0.14,
        rect.width * 0.31,
        rect.height * 0.66,
      ),
      Rect.fromLTWH(
        rect.left + rect.width * 0.55,
        rect.top + rect.height * 0.24,
        rect.width * 0.31,
        rect.height * 0.58,
      ),
    ];
    for (var b = 0; b < blocks.length; b++) {
      final block = blocks[b];
      _shadowedRect(
        canvas,
        block,
        b == 0 ? const Color(0xFFE4D6CB) : const Color(0xFFD5C4B8),
      );
      canvas.drawRect(
        Rect.fromLTWH(block.left, block.top, block.width, block.height * 0.09),
        Paint()..color = const Color(0xFF8D6E63),
      );
      for (var row = 0; row < 3; row++) {
        for (var column = 0; column < 2; column++) {
          _window(
            canvas,
            Offset(
              block.left + block.width * (0.30 + 0.40 * column),
              block.top + block.height * (0.25 + 0.22 * row),
            ),
            rect.width * 0.035,
            occupied,
            index * 17 + b * 7 + row * 2 + column,
          );
        }
      }
    }
  }

  void _drawCommercial(Canvas canvas, int index, Rect rect) {
    final activity = c.sim.indicators.jobsCapacity <= 0
        ? 0.0
        : (c.sim.indicators.jobsFilled / c.sim.indicators.jobsCapacity).clamp(
            0.0,
            1.0,
          );
    final building = Rect.fromLTWH(
      rect.left + rect.width * 0.12,
      rect.top + rect.height * 0.18,
      rect.width * 0.76,
      rect.height * 0.62,
    );
    _shadowedRect(canvas, building, const Color(0xFFEDE7F6));
    canvas.drawRect(
      Rect.fromLTWH(
        building.left,
        building.top,
        building.width,
        building.height * 0.34,
      ),
      Paint()..color = const Color(0xFF73558F),
    );
    final awning = Rect.fromLTWH(
      building.left + building.width * 0.08,
      building.top + building.height * 0.42,
      building.width * 0.84,
      building.height * 0.12,
    );
    for (var stripe = 0; stripe < 6; stripe++) {
      canvas.drawRect(
        Rect.fromLTWH(
          awning.left + awning.width * stripe / 6,
          awning.top,
          awning.width / 6,
          awning.height,
        ),
        Paint()
          ..color = stripe.isEven
              ? const Color(0xFFFFF8E1)
              : const Color(0xFF8E6AAA),
      );
    }
    canvas.drawRect(
      Rect.fromLTWH(
        building.left + building.width * 0.18,
        building.bottom - building.height * 0.32,
        building.width * 0.64,
        building.height * 0.25,
      ),
      Paint()
        ..color = Color.lerp(
          const Color(0xFF455A64),
          const Color(0xFF90CAF9),
          activity,
        )!,
    );
  }

  void _drawIndustry(Canvas canvas, int index, Rect rect) {
    final hall = Rect.fromLTWH(
      rect.left + rect.width * 0.10,
      rect.top + rect.height * 0.38,
      rect.width * 0.68,
      rect.height * 0.43,
    );
    _shadowedRect(canvas, hall, const Color(0xFFCFD8DC));
    final roof = Path()..moveTo(hall.left, hall.top);
    for (var tooth = 0; tooth < 4; tooth++) {
      final x = hall.left + hall.width * tooth / 4;
      roof
        ..lineTo(x + hall.width * 0.13, hall.top - rect.height * 0.13)
        ..lineTo(x + hall.width * 0.25, hall.top);
    }
    roof
      ..lineTo(hall.right, hall.bottom)
      ..lineTo(hall.left, hall.bottom)
      ..close();
    canvas.drawPath(roof, Paint()..color = const Color(0xFF78909C));
    final chimney = Rect.fromLTWH(
      rect.left + rect.width * 0.73,
      rect.top + rect.height * 0.18,
      rect.width * 0.12,
      rect.height * 0.46,
    );
    canvas.drawRect(chimney, Paint()..color = const Color(0xFF546E7A));
    if (!animateAmbient ||
        !c.experience.environmentAnimations ||
        _lowDetail ||
        rect.width * scale < 18) {
      return;
    }
    final emission = c.sim.params.tile(TileType.industry).airEmission.value;
    final reference = math.max(1.0, emission);
    final intensity =
        (c.sim.params.tile(c.sim.state.tiles[index]).airEmission.value /
                reference)
            .clamp(0.0, 1.0);
    for (var puff = 0; puff < 1 + (intensity * 2).round(); puff++) {
      final rise =
          (motion * (0.35 + intensity * 0.35) + _unit(index * 83 + puff)) % 1;
      final centre = Offset(
        chimney.center.dx +
            math.sin((rise + puff) * math.pi * 2) * rect.width * 0.05,
        chimney.top - rise * rect.height * 0.32,
      );
      canvas.drawCircle(
        centre,
        rect.width * (0.045 + rise * 0.045),
        Paint()
          ..color = const Color(
            0xFF546E7A,
          ).withValues(alpha: (1 - rise) * 0.34 * intensity),
      );
    }
  }

  double _occupancy(int index) {
    final capacity = c.sim.params
        .tile(c.sim.state.tiles[index])
        .residentsPerHa
        .value;
    return capacity <= 0
        ? 0
        : (c.sim.state.population[index] / capacity).clamp(0.0, 1.0);
  }

  void _shadowedRect(Canvas canvas, Rect rect, Color color) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect.shift(Offset(rect.width * 0.06, rect.height * 0.07)),
        Radius.circular(rect.width * 0.08),
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.16),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(rect.width * 0.07)),
      Paint()..color = color,
    );
  }

  void _window(
    Canvas canvas,
    Offset center,
    double radius,
    double occupancy,
    int seed,
  ) {
    final occupied = _unit(seed * 127) <= occupancy;
    final evening =
        0.5 + 0.5 * math.sin(motion * math.pi * 2 + _unit(seed) * math.pi * 2);
    canvas.drawRect(
      Rect.fromCenter(center: center, width: radius * 1.4, height: radius),
      Paint()
        ..color = occupied
            ? Color.lerp(
                const Color(0xFF90A4AE),
                const Color(0xFFFFD54F),
                animateAmbient &&
                        c.experience.cityActivityAnimations &&
                        !_lowDetail
                    ? evening
                    : 0.65,
              )!
            : const Color(0xFF78909C),
    );
  }

  void _drawRoad(Canvas canvas, int index, Rect rect) {
    final state = c.sim.state;
    final x = index % c.width;
    final y = index ~/ c.width;
    bool road(int nx, int ny) =>
        state.inBounds(nx, ny) && state.tileAt(nx, ny) == TileType.road;
    final asphalt = Paint()..color = const Color(0xFF596168);
    final lane = Paint()
      ..color = const Color(0xFFFFF3C4).withValues(alpha: 0.82)
      ..strokeWidth = math.max(0.65 / scale, rect.width * 0.025);
    final half = rect.width * 0.19;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: rect.center, width: half * 2, height: half * 2),
        Radius.circular(half * 0.35),
      ),
      asphalt,
    );
    void arm(Rect arm, Offset a, Offset b) {
      canvas.drawRect(arm, asphalt);
      canvas.drawLine(a, b, lane);
    }

    if (road(x - 1, y)) {
      arm(
        Rect.fromLTRB(
          rect.left,
          rect.center.dy - half,
          rect.center.dx,
          rect.center.dy + half,
        ),
        Offset(rect.left, rect.center.dy),
        rect.center,
      );
    }
    if (road(x + 1, y)) {
      arm(
        Rect.fromLTRB(
          rect.center.dx,
          rect.center.dy - half,
          rect.right,
          rect.center.dy + half,
        ),
        rect.center,
        Offset(rect.right, rect.center.dy),
      );
    }
    if (road(x, y - 1)) {
      arm(
        Rect.fromLTRB(
          rect.center.dx - half,
          rect.top,
          rect.center.dx + half,
          rect.center.dy,
        ),
        Offset(rect.center.dx, rect.top),
        rect.center,
      );
    }
    if (road(x, y + 1)) {
      arm(
        Rect.fromLTRB(
          rect.center.dx - half,
          rect.center.dy,
          rect.center.dx + half,
          rect.bottom,
        ),
        rect.center,
        Offset(rect.center.dx, rect.bottom),
      );
    }
  }

  void _drawTraffic(Canvas canvas, double cell) {
    if (cell * scale < 13) return;
    final state = c.sim.state;
    final reference = math.max(
      1.0,
      c.sim.params.noise.trafficReferenceVehiclesPerDay,
    );
    for (var i = 0; i < state.cellCount; i++) {
      if (state.tiles[i] != TileType.road) continue;
      final x = i % c.width;
      final y = i ~/ c.width;
      void segment(int nx, int ny, int other) {
        if (!state.inBounds(nx, ny) || state.tiles[other] != TileType.road) {
          return;
        }
        final intensity =
            ((c.sim.fields.traffic[i] + c.sim.fields.traffic[other]) /
                    (2 * reference))
                .clamp(0.0, 1.0);
        if (intensity < 0.01) return;
        final count = 1 + (intensity * 3).floor();
        final from = Offset((x + 0.5) * cell, (y + 0.5) * cell);
        final to = Offset((nx + 0.5) * cell, (ny + 0.5) * cell);
        final perpendicular =
            Offset(-(to.dy - from.dy), to.dx - from.dx) / cell * (cell * 0.075);
        for (var car = 0; car < count; car++) {
          final phase =
              (motion * (0.45 + 0.55 * intensity) + _unit(i * 17 + car * 31)) %
              1;
          final position =
              Offset.lerp(from, to, phase)! +
              (car.isEven ? perpendicular : -perpendicular);
          canvas.drawCircle(
            position,
            math.max(0.8 / scale, cell * 0.045),
            Paint()
              ..color = car.isEven
                  ? const Color(0xFFFFD54F)
                  : const Color(0xFFECEFF1),
          );
        }
      }

      if (x + 1 < c.width) segment(x + 1, y, i + 1);
      if (y + 1 < c.height) segment(x, y + 1, i + c.width);
    }
  }

  void _drawForest(Canvas canvas, int index, Rect rect, double maturity) {
    final sway =
        math.sin((motion + _unit(index)) * math.pi * 2) *
        rect.width *
        0.018 *
        maturity;
    final positions = <Offset>[
      const Offset(0.28, 0.30),
      const Offset(0.67, 0.27),
      const Offset(0.48, 0.55),
      const Offset(0.22, 0.72),
      const Offset(0.75, 0.72),
    ];
    final visible = 2 + (maturity * 3).round();
    for (var tree = 0; tree < visible; tree++) {
      final p = positions[tree];
      final centre = Offset(
        rect.left + p.dx * rect.width + sway * (tree.isEven ? 1 : -1),
        rect.top + p.dy * rect.height,
      );
      final radius =
          rect.width *
          (0.075 + 0.075 * maturity) *
          (0.88 + _unit(index * 13 + tree) * 0.22);
      canvas.drawCircle(
        centre + Offset(radius * 0.12, radius * 0.20),
        radius,
        Paint()..color = Colors.black.withValues(alpha: 0.12),
      );
      canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..color = Color.lerp(
            const Color(0xFF81C784),
            const Color(0xFF1B5E20),
            maturity,
          )!,
      );
      canvas.drawCircle(
        centre - Offset(radius * 0.25, radius * 0.25),
        radius * 0.48,
        Paint()..color = Colors.white.withValues(alpha: 0.13),
      );
    }
  }

  void _drawTree(Canvas canvas, Offset centre, double radius, double vitality) {
    canvas.drawCircle(
      centre + Offset(radius * 0.14, radius * 0.20),
      radius,
      Paint()..color = Colors.black.withValues(alpha: 0.13),
    );
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..color = Color.lerp(
          const Color(0xFF66BB6A),
          const Color(0xFF1B5E20),
          vitality,
        )!,
    );
    canvas.drawCircle(
      centre - Offset(radius * 0.24, radius * 0.25),
      radius * 0.43,
      Paint()..color = Colors.white.withValues(alpha: 0.14),
    );
  }

  double _maturity(int index) {
    final params = c.sim.params.tile(TileType.forest);
    final recovered =
        (c.sim.state.tileAge[index] / math.max(1, params.recoveryMonths.value))
            .clamp(0.0, 1.0);
    return params.biotopeStart.value +
        (1 - params.biotopeStart.value) * recovered;
  }

  bool _isCausalSource(MapOverlay overlay, TileType tile) => switch (overlay) {
    MapOverlay.noise =>
      tile == TileType.road ||
          tile == TileType.industry ||
          tile == TileType.commercial,
    MapOverlay.air => c.sim.params.tile(tile).airEmission.value > 0,
    MapOverlay.heat => c.sim.params.tile(tile).sealing.value >= 0.5,
    MapOverlay.green =>
      tile == TileType.park ||
          tile == TileType.forest ||
          tile == TileType.water,
    MapOverlay.retail => tile == TileType.commercial,
    MapOverlay.jobs => tile == TileType.commercial || tile == TileType.industry,
    MapOverlay.habitat =>
      tile == TileType.forest ||
          tile == TileType.meadow ||
          tile == TileType.water,
    MapOverlay.traffic => tile == TileType.road,
    MapOverlay.attractiveness =>
      tile == TileType.housingLow || tile == TileType.housingHigh,
    MapOverlay.none => false,
  };

  double _unit(int value) {
    var hash = value ^ c.sim.state.seed;
    hash = (hash * 1103515245 + 12345) & 0x7fffffff;
    return hash / 0x80000000;
  }

  void _outline(Canvas canvas, Rect rect, Color color, double width) {
    canvas.drawRect(
      rect.deflate(width / 2),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width,
    );
  }

  @override
  bool shouldRepaint(covariant _MapPainter oldDelegate) => true;
}
