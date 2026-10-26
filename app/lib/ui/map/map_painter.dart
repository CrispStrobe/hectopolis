// SPDX-License-Identifier: AGPL-3.0-or-later
part of '../map_view.dart';

/// A model-driven renderer. Static land-use remains legible while road
/// topology, traffic, forest maturity, construction and overlays animate from
/// values already present in the simulation.
/// The map is painted in two layers, so that the six-second ambient animation
/// does not redraw the whole city sixty times a second.
enum _MapLayer {
  /// The expensive part: ground, decoration and finished buildings. Repainted
  /// only when the simulation or the viewport changes, and kept behind a
  /// [RepaintBoundary] so that the moving layer cannot drag it along.
  still,

  /// Waves, smoke, lit windows, swaying trees, traffic, buildings still going
  /// up, and the hover, preview and selection outlines: everything that moves.
  ///
  /// The overlay tint, the grid and the threshold outlines belong here too,
  /// not because they move but because they have to stay above the tile art --
  /// including the parts of it drawn on this layer. They are two rectangles
  /// per cell, far cheaper than the art below them.
  moving,
}

/// How often each map layer has painted, so that a test can assert the ambient
/// animation does not drag the expensive layer along. Costs one increment per
/// paint.
@visibleForTesting
class MapPaintCounters {
  const MapPaintCounters._();

  static int still = 0;
  static int moving = 0;

  static void reset() {
    still = 0;
    moving = 0;
  }
}

class _MapPainter extends CustomPainter {
  _MapPainter(
    this.c,
    this.theme,
    this.scale, {
    required this.layer,
    required this.motion,
    required this.overlayProgress,
    required this.overlayFrom,
    required this.overlayTo,
    required this.constructionStartedMs,
    required this.animateAmbient,
    required this.animateEffects,
    required this.cleanVisuals,
    required this.keyboardFocused,
  });

  final GameController c;
  final ThemeData theme;
  final double scale;
  final _MapLayer layer;
  final double motion;
  final double overlayProgress;
  final List<double> overlayFrom;
  final List<double> overlayTo;
  final Map<int, int> constructionStartedMs;
  final bool animateAmbient;
  final bool animateEffects;
  final bool cleanVisuals;

  /// Whether the map holds the keyboard focus, and so whether the cursor keys
  /// currently do anything.
  final bool keyboardFocused;

  /// Per-cell readings the tile art responds to, each normalised against the
  /// range the field **actually occupies**, not against 0-1.
  ///
  /// This matters more than it looks. These are absolute model scores, and
  /// most of them never approach 1: a healthy untouched meadow scores 0.42 for
  /// habitat quality, a decent residential block 0.65 for attractiveness, and
  /// a busy map only drags the air index from 100 down to about 95. Driving
  /// colour across the full 0-1 of them paints a pristine map brown and dulls
  /// every facade. The anchors below are measured from the model, not assumed.
  ///
  /// They are read on the still layer, which is rasterised once and cached, so
  /// letting the art express the model costs nothing per frame -- only a
  /// repaint when the simulation actually changes.

  /// Encroachment on habitat: 0 where nothing is pressing, up to about 0.66
  /// beside a road. The degradation is what varies, so the art keys off it
  /// rather than off the quality score.
  double _threat(int i) => c.sim.fields.habitatThreat[i].clamp(0.0, 1.0);

  /// Heat, against the roughly 1 degree a town of this size reaches rather
  /// than the 3 degree theoretical maximum.
  ///
  /// Deliberately an **absolute** scale, unlike the heat overlay and the
  /// indicators, which divide by the month's ceiling (`fields.uhiMaxNowC`) so
  /// that a score keeps discriminating in July. This is a tint, not a score:
  /// what it should say is "this place is hot right now", so a July city is
  /// meant to look hotter than the same city in January.
  double _warmth(int i) =>
      (c.sim.fields.heatDeltaC[i] / (c.sim.params.heat.uhiMaxC * 0.35)).clamp(
        0.0,
        1.0,
      );

  /// Dirty air on the scale the game reaches: 100 is clean and a busy map
  /// sits near 95, so the band is a few points wide, not a hundred.
  double _haze(int i) => ((100 - c.sim.fields.airIndex[i]) / 8).clamp(0.0, 1.0);

  /// Appeal against a decent block rather than an unreachable perfect one.
  double _appeal(int i) =>
      (c.sim.fields.attractiveness[i] / 0.7).clamp(0.0, 1.0);

  /// Whether the art may colour itself by the model.
  ///
  /// Suppressed while an overlay is up: the overlay is the precise reading and
  /// a second, vaguer one underneath it only muddies the colours.
  bool get _modelTinting =>
      !_lowDetail && c.overlay == MapOverlay.none && !cleanVisuals;

  bool get _still => layer == _MapLayer.still;

  bool get _moving => layer == _MapLayer.moving;

  double get _growth => c.sim.params.seasons.growthAt(c.sim.state.tick);

  Color _seasonal(Color base) => seasonalVegetationColor(base, _growth);

  /// Large maps automatically shed decorative detail while zoomed out.
  bool get _lowDetail =>
      cleanVisuals || (c.sim.state.cellCount > 1024 && scale < 1.35);

  @override
  void paint(Canvas canvas, Size size) {
    if (_still) {
      MapPaintCounters.still++;
    } else {
      MapPaintCounters.moving++;
    }
    final state = c.sim.state;
    final cell = size.width / c.width;
    final hair = 1 / scale;
    final now = DateTime.now().millisecondsSinceEpoch;
    // Once the ground has texture, a hard grid fights it. Kept faint, and
    // faintest when zoomed in far enough that cells are obvious anyway.
    final grid = Paint()
      ..color = Colors.black.withValues(
        alpha: _lowDetail ? 0.10 : (scale > 2 ? 0.045 : 0.07),
      )
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
      if (_still) continue;
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
            isCausalSource(c.overlay, state.tiles[i], c.sim)) {
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
      if (c.overlay != MapOverlay.none && c.overlayMeetsThreshold(i)) {
        final x = i % c.width;
        final y = i ~/ c.width;
        bool below(int nx, int ny) =>
            !state.inBounds(nx, ny) ||
            !c.overlayMeetsThreshold(state.index(nx, ny));
        if (below(x - 1, y) ||
            below(x + 1, y) ||
            below(x, y - 1) ||
            below(x, y + 1)) {
          canvas.drawRect(
            rect.deflate(hair * 0.8),
            Paint()
              ..color = theme.colorScheme.onSurface.withValues(alpha: 0.72)
              ..style = PaintingStyle.stroke
              ..strokeWidth = math.max(1.2 / scale, rect.width * 0.035),
          );
        }
      }
      canvas.drawRect(rect, grid);
    }

    if (_still) return;

    // Co-op districts divide build rights, not effects. Keep every border
    // visible while giving this device's own strip the strongest outline.
    if (c.cooperative) {
      const districtColors = [
        Color(0xFF1565C0),
        Color(0xFFC62828),
        Color(0xFF6A1B9A),
        Color(0xFFEF6C00),
      ];
      final mine = c.myDistrict;
      for (var i = 0; i < c.cooperativePlayers.length; i++) {
        final district = c.cooperativePlayers[i].district;
        if (district == null) continue;
        final isMine =
            mine != null &&
            district.x == mine.x &&
            district.y == mine.y &&
            district.width == mine.width &&
            district.height == mine.height;
        final rect = Rect.fromLTWH(
          district.x * cell,
          district.y * cell,
          district.width * cell,
          district.height * cell,
        ).deflate(2 * hair);
        final color = districtColors[i % districtColors.length];
        if (isMine) {
          canvas.drawRect(
            rect,
            Paint()..color = color.withValues(alpha: 0.045),
          );
        }
        _outline(
          canvas,
          rect,
          color.withValues(alpha: isMine ? 0.95 : 0.62),
          (isMine ? 4 : 2) * hair,
        );
      }
    }

    if (c.experience.causalHighlights &&
        c.overlay != MapOverlay.none &&
        c.selectedCell != null) {
      final target = cellRect(c.selectedCell!).center;
      final sourcePaint = Paint()
        ..color = theme.colorScheme.primary.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1 / scale, cell * 0.025);
      for (final source in c.selectedCausalSourceCells) {
        final origin = cellRect(source).center;
        canvas.drawLine(origin, target, sourcePaint);
        canvas.drawCircle(
          origin,
          math.max(1.5 / scale, cell * 0.06),
          sourcePaint..style = PaintingStyle.fill,
        );
        sourcePaint.style = PaintingStyle.stroke;
      }
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
      // Solid and full strength while the map has the keyboard; faint when it
      // does not, so a dead arrow key is visible rather than mysterious.
      final strength = keyboardFocused ? 1.0 : 0.35;
      _outline(
        canvas,
        rect.deflate(hair),
        theme.colorScheme.onSurface.withValues(alpha: strength),
        (keyboardFocused ? 2 : 1.5) * hair,
      );
      _outline(
        canvas,
        rect.deflate(4 * hair),
        theme.colorScheme.surface.withValues(alpha: strength),
        2 * hair,
      );
      if (keyboardFocused) {
        _outline(
          canvas,
          rect.deflate(-2 * hair),
          theme.colorScheme.primary.withValues(alpha: 0.9),
          2 * hair,
        );
      }
    }
  }

  /// Draws the part of a tile that belongs to this layer.
  ///
  /// A preview tile ([tileOverride]) is drawn whole, on whichever layer asks
  /// for it, because it is a single cell and has no layer of its own.
  void _drawTile(
    Canvas canvas,
    int index,
    Rect rect, {
    TileType? tileOverride,
    required double construction,
  }) {
    final state = c.sim.state;
    final tile = tileOverride ?? state.tiles[index];
    final whole = tileOverride != null;
    final still = whole || _still;
    final moving = whole || _moving;
    // A building that is still going up is rescaled every frame, so it belongs
    // to the moving layer until it is finished and handed back.
    final growing = animateEffects && construction < 0.98;

    if (still) {
      final ground = _groundColor(tile);
      if (_lowDetail) {
        canvas.drawRect(rect, Paint()..color = ground);
      } else {
        // Ground is the largest thing on screen and was a single flat fill,
        // which is most of why the map read as coloured squares rather than
        // as land. A light-to-dark gradient plus a few seeded blobs give it a
        // surface. Both are still-layer work, so they are paid once.
        canvas.drawRect(
          rect,
          Paint()
            ..shader = ui.Gradient.linear(
              rect.topLeft,
              rect.bottomRight,
              [
                Color.lerp(ground, Colors.white, 0.10)!,
                ground,
                Color.lerp(ground, Colors.black, 0.07)!,
              ],
              const [0.0, 0.55, 1.0],
            ),
        );
        _mottle(canvas, index, rect, ground);
      }
      if (!whole && _modelTinting) {
        // Heat and dirty air are fields the player could only see by turning
        // an overlay on. A wash this faint does not read as a measurement --
        // it reads as a place that feels hot, or hazy.
        final warmth = _warmth(index);
        if (warmth > 0.05) {
          canvas.drawRect(
            rect,
            Paint()
              ..color = const Color(
                0xFFFF7043,
              ).withValues(alpha: 0.16 * warmth),
          );
        }
        final haze = _haze(index);
        if (haze > 0.05) {
          canvas.drawRect(
            rect,
            Paint()
              ..color = const Color(0xFF8D8778).withValues(alpha: 0.16 * haze),
          );
        }
      }
    }

    switch (tile) {
      case TileType.meadow:
        if (still && !_lowDetail) _drawMeadow(canvas, index, rect);
        break;
      case TileType.cropland:
        if (still) _drawCropland(canvas, index, rect);
        break;
      case TileType.forest:
        // The whole cluster sways, so it is drawn on the moving layer.
        if (moving) {
          _drawForest(canvas, index, rect, whole ? 1 : _maturity(index));
        }
        break;
      case TileType.water:
        _drawWater(canvas, index, rect, still: still, moving: moving);
        break;
      case TileType.wetland:
        // Shallow water with reeds standing in it: the shoreline and reeds are
        // still, the ripples move.
        _drawWater(canvas, index, rect, still: still, moving: moving);
        if (still) _drawReeds(canvas, index, rect);
        break;
      case TileType.solarField:
        if (still) _drawSolarField(canvas, index, rect);
        break;
      case TileType.cyclePath:
        if (still) _drawCyclePath(canvas, index, rect);
        break;
      case TileType.tramStop:
        if (still) _drawTramStop(canvas, index, rect);
        break;
      case TileType.park:
        if (still) _drawPark(canvas, index, rect);
        break;
      case TileType.road:
        if (still) _drawRoad(canvas, index, rect);
        break;
      case TileType.housingLow ||
          TileType.housingHigh ||
          TileType.mixedUse ||
          TileType.commercial ||
          TileType.industry ||
          TileType.school:
        final body = growing ? moving : still;
        if (body || moving) {
          _withConstruction(
            canvas,
            rect,
            construction,
            () => _drawBuilding(
              canvas,
              index,
              rect,
              tile,
              body: body,
              lights: moving,
            ),
          );
        }
        break;
    }
    if (moving &&
        animateEffects &&
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
    TileType.meadow ||
    TileType.cropland ||
    TileType.forest ||
    TileType.park ||
    TileType.wetland => _seasonal(TileStyle.of(tile).color),
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

  /// Fine speckle in the ground colour, seeded by the cell, so that no two
  /// tiles of a type are identical and none of them is flat.
  ///
  /// Deliberately near-invisible per mark. An earlier version used three large
  /// blobs at about 45% alpha and every tile ended up wearing the same pair of
  /// dark and light bubbles -- at tile scale a few big marks read as a
  /// repeating pattern, never as texture. Many small faint ones read as a
  /// surface.
  void _mottle(Canvas canvas, int index, Rect rect, Color ground) {
    if (rect.width * scale < 14) return;
    final dark = Paint()
      ..color = Color.lerp(ground, Colors.black, 0.18)!.withValues(alpha: 0.13);
    final light = Paint()
      ..color = Color.lerp(ground, Colors.white, 0.22)!.withValues(alpha: 0.11);
    for (var blob = 0; blob < 7; blob++) {
      final seed = index * 197 + blob * 31;
      canvas.drawCircle(
        Offset(
          rect.left + rect.width * (0.08 + _unit(seed) * 0.84),
          rect.top + rect.height * (0.08 + _unit(seed + 7) * 0.84),
        ),
        rect.width * (0.05 + _unit(seed + 13) * 0.09),
        blob.isEven ? dark : light,
      );
    }
  }

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
  // Both layers repaint whenever they are rebuilt, and the still layer is
  // rebuilt only by the listenables it actually depends on -- the motion
  // controller is not one of them.
  bool shouldRepaint(covariant _MapPainter oldDelegate) => true;
}
