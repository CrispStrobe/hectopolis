// SPDX-License-Identifier: AGPL-3.0-or-later
part of '../map_view.dart';

/// Tile art for the open land: meadow, cropland, water, wetland reeds, park
/// and forest.
extension _NatureTiles on _MapPainter {
  void _drawMeadow(Canvas canvas, int index, Rect rect) {
    if (rect.width * scale < 14) return;
    // A meadow hemmed in by roads and buildings is thinner and drier than one
    // in the open. Both readings come from the habitat model, so the picture
    // and the biodiversity score cannot disagree.
    final pressure = _modelTinting ? _threat(index) : 0.0;
    final grass = Paint()
      // Green by default, drying only where something is pressing on it.
      ..color = _seasonal(
        Color.lerp(
          const Color(0xFF4F8A51),
          const Color(0xFF9E8B3F),
          pressure * 0.7,
        )!,
      ).withValues(alpha: 0.65)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.55 / scale, rect.width * 0.018)
      ..strokeCap = StrokeCap.round;
    final tufts = (_lowDetail ? 5 : 9) - (pressure * 3).round();
    for (var tuft = 0; tuft < tufts; tuft++) {
      final x =
          rect.left + rect.width * (0.08 + _unit(index * 41 + tuft) * 0.84);
      final y =
          rect.top + rect.height * (0.20 + _unit(index * 59 + tuft) * 0.72);
      final h = rect.height * (0.06 + _unit(index * 73 + tuft) * 0.08);
      // A third blade and a per-tuft lean stop the meadow looking stamped.
      final lean = (_unit(index * 89 + tuft) - 0.5) * 0.5;
      canvas.drawLine(
        Offset(x, y),
        Offset(x - h * (0.28 - lean), y - h),
        grass,
      );
      canvas.drawLine(
        Offset(x, y),
        Offset(x + h * (0.30 + lean), y - h * 0.82),
        grass,
      );
      if (!_lowDetail && tuft.isEven) {
        canvas.drawLine(Offset(x, y), Offset(x + lean * h, y - h * 1.1), grass);
      }
    }
    // Flowers thin out where the meadow is under pressure.
    if (pressure < 0.4 && !_lowDetail) {
      const petals = [Color(0xFFFFF59D), Color(0xFFF8BBD0), Color(0xFFE1F5FE)];
      for (var f = 0; f < 3; f++) {
        if (_unit(index * 101 + f * 19) < 0.45) continue;
        canvas.drawCircle(
          Offset(
            rect.left + rect.width * (0.15 + _unit(index * 103 + f) * 0.7),
            rect.top + rect.height * (0.25 + _unit(index * 107 + f) * 0.6),
          ),
          math.max(0.7 / scale, rect.width * 0.021),
          Paint()..color = petals[f % petals.length],
        );
      }
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

  void _drawWater(
    Canvas canvas,
    int index,
    Rect rect, {
    required bool still,
    required bool moving,
  }) {
    final state = c.sim.state;
    final x = index % c.width;
    final y = index ~/ c.width;
    bool water(int nx, int ny) =>
        state.inBounds(nx, ny) && state.tileAt(nx, ny) == TileType.water;
    if (still) {
      final shore = Paint()
        ..color = const Color(0xFFE7D7A5).withValues(alpha: 0.72)
        ..strokeWidth = math.max(0.8 / scale, rect.width * 0.045);
      if (!water(x - 1, y)) {
        canvas.drawLine(rect.topLeft, rect.bottomLeft, shore);
      }
      if (!water(x + 1, y)) {
        canvas.drawLine(rect.topRight, rect.bottomRight, shore);
      }
      if (!water(x, y - 1)) {
        canvas.drawLine(rect.topLeft, rect.topRight, shore);
      }
      if (!water(x, y + 1)) {
        canvas.drawLine(rect.bottomLeft, rect.bottomRight, shore);
      }
    }
    if (!moving ||
        _lowDetail ||
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
      seed: index * 71,
    );
    _drawTree(
      canvas,
      Offset(rect.left + rect.width * 0.70, rect.top + rect.height * 0.66),
      rect.width * 0.10,
      0.72,
      seed: index * 71 + 5,
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

  /// Reeds standing in shallow water.
  void _drawReeds(Canvas canvas, int index, Rect rect) {
    if (rect.width * scale < 12) return;
    final stem = Paint()
      ..color = const Color(0xFF6D8C3A)
      ..strokeWidth = math.max(0.6 / scale, rect.width * 0.016)
      ..strokeCap = StrokeCap.round;
    final head = Paint()..color = const Color(0xFF8D6E63);
    for (var r = 0; r < 7; r++) {
      final x = rect.left + rect.width * (0.12 + _unit(index * 149 + r) * 0.76);
      final base =
          rect.top + rect.height * (0.3 + _unit(index * 151 + r) * 0.6);
      final h = rect.height * (0.16 + _unit(index * 157 + r) * 0.12);
      canvas.drawLine(Offset(x, base), Offset(x, base - h), stem);
      canvas.drawCircle(Offset(x, base - h), rect.width * 0.016, head);
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
    // Maturity says how grown the wood is; threat says how much of it survives
    // being hemmed in. A fragmented wood should look fragmented.
    final pressure = _modelTinting ? _threat(index) : 0.0;
    final visible = math.max(
      1,
      (2 + (maturity * 3).round()) - (pressure * 2).round(),
    );
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
      _drawTree(canvas, centre, radius, maturity, seed: index * 53 + tree);
    }
  }

  /// A tree as a cluster rather than a disc: three overlapping lobes, a trunk,
  /// and light from the top left. [seed] varies the lobes so a wood is not a
  /// field of identical dots.
  void _drawTree(
    Canvas canvas,
    Offset centre,
    double radius,
    double vitality, {
    int seed = 0,
  }) {
    canvas.drawOval(
      Rect.fromCenter(
        center: centre + Offset(radius * 0.18, radius * 0.34),
        width: radius * 2.0,
        height: radius * 1.1,
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.13),
    );
    if (radius * scale > 3.2) {
      canvas.drawRect(
        Rect.fromCenter(
          center: centre + Offset(0, radius * 0.72),
          width: radius * 0.26,
          height: radius * 0.8,
        ),
        Paint()..color = const Color(0xFF6D4C41),
      );
    }
    final rawDark = Color.lerp(
      const Color(0xFF66BB6A),
      const Color(0xFF1B5E20),
      vitality,
    )!;
    final dark = _seasonal(rawDark);
    final lit = _seasonal(Color.lerp(rawDark, const Color(0xFFC5E1A5), 0.34)!);
    // Three lobes, jittered per tree, drawn dark first so the lit one reads
    // as the sunlit side.
    for (var lobe = 0; lobe < 3; lobe++) {
      final jitter = Offset(
        (_unit(seed * 17 + lobe) - 0.5) * radius * 0.7,
        (_unit(seed * 29 + lobe) - 0.5) * radius * 0.5,
      );
      canvas.drawCircle(
        centre + jitter,
        radius * (0.62 + _unit(seed * 37 + lobe) * 0.3),
        Paint()..color = dark,
      );
    }
    canvas.drawCircle(
      centre - Offset(radius * 0.28, radius * 0.3),
      radius * 0.46,
      Paint()..color = lit,
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
}
