// SPDX-License-Identifier: AGPL-3.0-or-later
part of '../map_view.dart';

/// Tile art for buildings: housing, mixed use, school, commercial, industry
/// and the solar field, with the facade, window and occupancy helpers they
/// share.
extension _BuiltTiles on _MapPainter {
  /// [body] draws the masonry, [lights] the windows and the chimney smoke:
  /// the windows shift with the time of day and so live on the moving layer
  /// even when the building itself does not.
  void _drawBuilding(
    Canvas canvas,
    int index,
    Rect rect,
    TileType tile, {
    required bool body,
    required bool lights,
  }) {
    if (rect.width * scale < 11) return;
    switch (tile) {
      case TileType.housingLow:
        _drawLowHousing(canvas, index, rect, body: body, lights: lights);
      case TileType.housingHigh:
        _drawHighHousing(canvas, index, rect, body: body, lights: lights);
      case TileType.mixedUse:
        _drawMixedUse(canvas, index, rect, body: body, lights: lights);
      case TileType.school:
        if (body) _drawSchool(canvas, index, rect);
      case TileType.commercial:
        if (body) _drawCommercial(canvas, index, rect);
      case TileType.industry:
        _drawIndustry(canvas, index, rect, body: body, smoke: lights);
      case _:
        break;
    }
  }

  void _drawLowHousing(
    Canvas canvas,
    int index,
    Rect rect, {
    required bool body,
    required bool lights,
  }) {
    final occupied = _occupancy(index);
    for (var house = 0; house < 2; house++) {
      final left = rect.left + rect.width * (house == 0 ? 0.13 : 0.55);
      final top = rect.top + rect.height * (house == 0 ? 0.22 : 0.52);
      final walls = Rect.fromLTWH(
        left,
        top,
        rect.width * 0.29,
        rect.height * 0.24,
      );
      if (body) {
        _shadowedRect(canvas, walls, _facade(index, const Color(0xFFFFF3E0)));
        final roof = Path()
          ..moveTo(walls.left - rect.width * 0.035, walls.top)
          ..lineTo(walls.center.dx, walls.top - rect.height * 0.13)
          ..lineTo(walls.right + rect.width * 0.035, walls.top)
          ..close();
        canvas.drawPath(
          roof,
          Paint()
            ..color = house == 0
                ? const Color(0xFFB5523B)
                : const Color(0xFF8D493A),
        );
      }
      if (lights) {
        _window(
          canvas,
          walls.center + Offset(0, walls.height * 0.05),
          rect.width * 0.055,
          occupied,
          index + house,
        );
      }
    }
  }

  void _drawHighHousing(
    Canvas canvas,
    int index,
    Rect rect, {
    required bool body,
    required bool lights,
  }) {
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
      if (body) {
        _shadowedRect(
          canvas,
          block,
          _facade(
            index,
            b == 0 ? const Color(0xFFE4D6CB) : const Color(0xFFD5C4B8),
          ),
        );
        canvas.drawRect(
          Rect.fromLTWH(
            block.left,
            block.top,
            block.width,
            block.height * 0.09,
          ),
          Paint()..color = const Color(0xFF8D6E63),
        );
      }
      if (!lights) continue;
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

  /// A facade, dulled where the place is a poor one to live.
  ///
  /// Attractiveness is what population actually follows, so this shows the
  /// crowding loop on the map: the blocks beside the loud road go grey before
  /// their residents leave.
  Color _facade(int index, Color base) {
    if (!_modelTinting) return base;
    return Color.lerp(
      const Color(0xFF9E9689),
      base,
      0.35 + 0.65 * _appeal(index),
    )!;
  }

  /// Rows of dark modules on posts, with the sward showing between them.
  void _drawSolarField(Canvas canvas, int index, Rect rect) {
    if (rect.width * scale < 11) return;
    final panel = Paint()..color = const Color(0xFF1A2733);
    final glint = Paint()
      ..color = const Color(0xFF7EA8C4).withValues(alpha: 0.5);
    const rows = 3;
    for (var row = 0; row < rows; row++) {
      final top = rect.top + rect.height * (0.18 + row * 0.26);
      final r = Rect.fromLTWH(
        rect.left + rect.width * 0.1,
        top,
        rect.width * 0.8,
        rect.height * 0.15,
      );
      canvas.drawRect(
        r.shift(Offset(0, r.height * 0.35)),
        Paint()..color = Colors.black.withValues(alpha: 0.12),
      );
      canvas.drawRect(r, panel);
      // A single highlight per row reads as glass without becoming stripes.
      canvas.drawRect(
        Rect.fromLTWH(r.left, r.top, r.width, r.height * 0.22),
        glint,
      );
    }
  }

  /// Homes over shops: a block with a lit shopfront along its foot.
  void _drawMixedUse(
    Canvas canvas,
    int index,
    Rect rect, {
    required bool body,
    required bool lights,
  }) {
    final block = Rect.fromLTWH(
      rect.left + rect.width * 0.12,
      rect.top + rect.height * 0.16,
      rect.width * 0.76,
      rect.height * 0.66,
    );
    if (body) {
      _shadowedRect(canvas, block, _facade(index, const Color(0xFFE8DEF8)));
      canvas.drawRect(
        Rect.fromLTWH(block.left, block.top, block.width, block.height * 0.1),
        Paint()..color = const Color(0xFF7E57C2),
      );
      // The shopfront band along the ground floor.
      canvas.drawRect(
        Rect.fromLTWH(
          block.left,
          block.bottom - block.height * 0.26,
          block.width,
          block.height * 0.26,
        ),
        Paint()..color = const Color(0xFF9575CD),
      );
    }
    if (!lights) return;
    final occupied = _occupancy(index);
    for (var row = 0; row < 2; row++) {
      for (var column = 0; column < 3; column++) {
        _window(
          canvas,
          Offset(
            block.left + block.width * (0.22 + 0.28 * column),
            block.top + block.height * (0.3 + 0.24 * row),
          ),
          rect.width * 0.035,
          occupied,
          index * 23 + row * 3 + column,
        );
      }
    }
  }

  /// A low building with a yard and a sports field.
  void _drawSchool(Canvas canvas, int index, Rect rect) {
    if (rect.width * scale < 11) return;
    final wing = Rect.fromLTWH(
      rect.left + rect.width * 0.1,
      rect.top + rect.height * 0.2,
      rect.width * 0.52,
      rect.height * 0.34,
    );
    _shadowedRect(canvas, wing, const Color(0xFFFFF8E1));
    canvas.drawRect(
      Rect.fromLTWH(wing.left, wing.top, wing.width, wing.height * 0.2),
      Paint()..color = const Color(0xFFBF8A2E),
    );
    for (var w = 0; w < 4; w++) {
      canvas.drawRect(
        Rect.fromLTWH(
          wing.left + wing.width * (0.1 + w * 0.22),
          wing.center.dy,
          wing.width * 0.12,
          wing.height * 0.28,
        ),
        Paint()..color = const Color(0xFF90A4AE),
      );
    }
    // The yard: a pitch marking is the clearest sign of a school from above.
    final yard = Rect.fromLTWH(
      rect.left + rect.width * 0.14,
      rect.bottom - rect.height * 0.34,
      rect.width * 0.72,
      rect.height * 0.22,
    );
    canvas.drawRect(yard, Paint()..color = const Color(0xFF8FB96B));
    canvas.drawRect(
      yard.deflate(yard.height * 0.18),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.6 / scale, rect.width * 0.012),
    );
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

  void _drawIndustry(
    Canvas canvas,
    int index,
    Rect rect, {
    required bool body,
    required bool smoke,
  }) {
    final hall = Rect.fromLTWH(
      rect.left + rect.width * 0.10,
      rect.top + rect.height * 0.38,
      rect.width * 0.68,
      rect.height * 0.43,
    );
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
    final chimney = Rect.fromLTWH(
      rect.left + rect.width * 0.73,
      rect.top + rect.height * 0.18,
      rect.width * 0.12,
      rect.height * 0.46,
    );
    if (body) {
      _shadowedRect(canvas, hall, const Color(0xFFCFD8DC));
      canvas.drawPath(roof, Paint()..color = const Color(0xFF78909C));
      canvas.drawRect(chimney, Paint()..color = const Color(0xFF546E7A));
    }
    if (!smoke ||
        !animateAmbient ||
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
    // The plume leans the way the wind actually blows it in the air model, so
    // a player can see which homes are downwind before reading an overlay.
    // Costs nothing extra: the same puffs, offset.
    final air = c.sim.params.air;
    final towards = (air.windFromDegrees + 180) * math.pi / 180;
    final drift = air.hasWind
        ? Offset(math.sin(towards), -math.cos(towards)) *
              (rect.width * 0.34 * (1 - 1 / air.windStretch))
        : Offset.zero;
    for (var puff = 0; puff < 1 + (intensity * 2).round(); puff++) {
      final rise =
          (motion * (0.35 + intensity * 0.35) + _unit(index * 83 + puff)) % 1;
      final centre = Offset(
        chimney.center.dx +
            math.sin((rise + puff) * math.pi * 2) * rect.width * 0.05 +
            drift.dx * rise,
        chimney.top - rise * rect.height * 0.32 + drift.dy * rise,
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
}
