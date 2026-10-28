// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsService;
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:stadtbau_sim/stadtbau_sim.dart';

import '../game/game_controller.dart';
import '../game/overlay_math.dart' show isCausalSource;
import '../l10n/generated/app_localizations.dart';
import 'tile_naming.dart';
import 'tile_style.dart';

part 'map/map_cards.dart';
part 'map/map_painter.dart';
part 'map/tiles_built.dart';
part 'map/tiles_nature.dart';
part 'map/tiles_transport.dart';

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

  /// Bumped when the still layer has to be redrawn for a reason the controller
  /// does not announce: so far only a building whose construction animation
  /// has finished and which the moving layer therefore hands back.
  final ValueNotifier<int> _stillRevision = ValueNotifier<int>(0);
  Timer? _constructionHandover;

  /// How long the construction animation in [_MapPainter] runs.
  static const int _constructionMs = 950;
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
    c.mapFocusRequests.addListener(_onMapFocusRequested);
    _focus.addListener(_onFocusChanged);
  }

  /// Something outside the map (a palette card, a global shortcut) handed the
  /// keyboard back.
  void _onMapFocusRequested() {
    if (mounted && !_focus.hasFocus) _focus.requestFocus();
  }

  /// The cursor is drawn differently when the map does not hold the keyboard,
  /// so "why do the arrow keys do nothing" is answerable by looking.
  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant MapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_onControllerChanged);
    oldWidget.controller.mapFocusRequests.removeListener(_onMapFocusRequested);
    widget.controller.addListener(_onControllerChanged);
    widget.controller.mapFocusRequests.addListener(_onMapFocusRequested);
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
    _constructionHandover?.cancel();
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
    _announceChanges();
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
      _scheduleConstructionHandover();
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

  String? _lastSpoken;
  TileType? _lastBrush;

  /// Speaks what a keyboard action changed, where nothing else would.
  ///
  /// The brush: a digit key changes the palette card's label, but focus is on
  /// the map, so no platform reads it. The cursor: the map is a live region,
  /// but the web engine announces a live region only when its *label*
  /// changes, and the cursor reading is the value, so on the web an arrow key
  /// moved a cursor nobody heard. The native platforms are left to the live
  /// region, so they do not hear it twice.
  void _announceChanges() {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final view = View.of(context);
    final direction = Directionality.of(context);
    final brush = c.brush;
    if (brush != _lastBrush) {
      _lastBrush = brush;
      if (brush != null) {
        unawaited(
          SemanticsService.sendAnnouncement(
            view,
            l10n.a11yTileSelected(tileDisplayName(l10n, c.level, brush)),
            direction,
          ),
        );
      }
    }
    if (kIsWeb && _focus.hasFocus) {
      final spoken = _cursorDescription(l10n);
      if (spoken != _lastSpoken) {
        _lastSpoken = spoken;
        unawaited(SemanticsService.sendAnnouncement(view, spoken, direction));
      }
    }
  }

  /// What the cursor is standing on, for a screen reader.
  ///
  /// Read from the same fields the tile inspector shows, so the spoken
  /// description and the visible panel cannot disagree.
  String _cursorDescription(AppLocalizations l10n) {
    final cell = c.cursorCell ?? c.selectedCell;
    if (cell == null) return l10n.a11yMapNoCursor;
    final f = c.sim.fields;
    return l10n.a11yMapCursor(
      cell % c.width,
      cell ~/ c.width,
      tileDisplayName(l10n, c.level, c.sim.state.tiles[cell]),
      f.noiseDb[cell].round().toString(),
      f.airIndex[cell].round().toString(),
    );
  }

  _MapPainter _layerPainter(
    BuildContext context,
    _MapLayer layer,
  ) => _MapPainter(
    c,
    Theme.of(context),
    m.scale,
    layer: layer,
    motion: _motion.value,
    overlayProgress: Curves.easeOutCubic.transform(_overlayTransition.value),
    overlayFrom: _overlayFrom,
    overlayTo: _overlayTo,
    constructionStartedMs: _constructionStartedMs,
    animateAmbient: !_platformReduceMotion && c.experience.ambientAnimations,
    animateEffects: !_platformReduceMotion && c.experience.effectAnimations,
    cleanVisuals: c.experience.cleanVisuals,
    keyboardFocused: _focus.hasFocus,
    stillRevision: _stillRevision.value,
  );

  /// Hand finished buildings back to the still layer once their construction
  /// animation is over. Without this they would fall between the layers: the
  /// moving layer stops drawing them and the still layer has no reason to
  /// repaint.
  void _scheduleConstructionHandover() {
    _constructionHandover?.cancel();
    if (_constructionStartedMs.isEmpty) return;
    final newest = _constructionStartedMs.values.reduce(math.max);
    final remaining =
        _constructionMs - (DateTime.now().millisecondsSinceEpoch - newest);
    if (remaining <= 0) {
      _finishConstructions();
      return;
    }
    _constructionHandover = Timer(
      Duration(milliseconds: remaining),
      _finishConstructions,
    );
  }

  void _finishConstructions() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _constructionStartedMs.removeWhere(
      (_, started) => now - started >= _constructionMs,
    );
    _stillRevision.value++;
    if (_constructionStartedMs.isNotEmpty) _scheduleConstructionHandover();
  }

  @override
  void dispose() {
    c.removeListener(_onControllerChanged);
    c.mapFocusRequests.removeListener(_onMapFocusRequested);
    _focus.removeListener(_onFocusChanged);
    _constructionHandover?.cancel();
    _stillRevision.dispose();
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
              // The region below carries the focus flags, so that the map's
              // focus lands on the node a screen reader is reading.
              includeSemantics: false,
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
                              // A screen reader acts on the map through its
                              // focusable region below. Left in, these taps
                              // merged into the screen's node, which became
                              // one full-window button that also swallowed
                              // every loose text on the screen.
                              excludeFromSemantics: true,
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
                              // Two layers: the still one is rebuilt only by
                              // the listenables it depends on -- the motion
                              // controller is deliberately not among them --
                              // and a RepaintBoundary keeps the moving layer
                              // above it from dragging it into every frame.
                              // One region for the whole map, whose value is
                              // the cursor cell. A semantics node per cell
                              // would be 256 to 576 nodes rebuilt on every
                              // placement, describing a grid a screen reader
                              // cannot usefully wander. The app already moves
                              // cell by cell with the arrow keys, so this
                              // announces what that cursor is standing on.
                              child: Semantics(
                                container: true,
                                label: l10n.a11yMapLabel,
                                value: _cursorDescription(l10n),
                                hint: l10n.keyboardHint,
                                liveRegion: true,
                                // Without these the region was never a Tab
                                // stop for a screen reader on the web, so
                                // the arrow keys had nothing to act on.
                                focusable: true,
                                focused: _focus.hasFocus,
                                onFocus: _focus.requestFocus,
                                child: Stack(
                                  children: [
                                    RepaintBoundary(
                                      child: ListenableBuilder(
                                        listenable: Listenable.merge([
                                          c,
                                          m.transformation,
                                          _stillRevision,
                                        ]),
                                        builder: (context, _) => CustomPaint(
                                          size: size,
                                          painter: _layerPainter(
                                            context,
                                            _MapLayer.still,
                                          ),
                                        ),
                                      ),
                                    ),
                                    ListenableBuilder(
                                      listenable: Listenable.merge([
                                        c,
                                        c.hoverChanges,
                                        m.transformation,
                                        _motion,
                                        _overlayTransition,
                                      ]),
                                      builder: (context, _) => CustomPaint(
                                        size: size,
                                        painter: _layerPainter(
                                          context,
                                          _MapLayer.moving,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Follows the pointer through its own notifier, so
                        // hovering rebuilds this card and not the screen.
                        Positioned(
                          top: 8,
                          right: 8,
                          child: ListenableBuilder(
                            listenable: c.hoverChanges,
                            builder: (context, _) =>
                                switch (c.placementPreview) {
                                  final preview? => _PlacementPreviewCard(
                                    preview: preview,
                                    simpleMode: c.simpleMode,
                                    level: c.level,
                                  ),
                                  null => const SizedBox.shrink(),
                                },
                          ),
                        ),
                        if (c.brush case final brush?)
                          Positioned(
                            left: 8,
                            bottom: 8,
                            child: _PlacementModeChip(
                              tile: brush,
                              onCancel: c.clearBrush,
                              level: c.level,
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
                              level: c.level,
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
