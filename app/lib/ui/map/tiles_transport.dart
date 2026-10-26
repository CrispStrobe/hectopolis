// SPDX-License-Identifier: AGPL-3.0-or-later
part of '../map_view.dart';

/// Tile art for the movement network: road, traffic, cycle path and tram stop.
extension _TransportTiles on _MapPainter {
  /// A path through a green corridor, with its verge left planted.
  void _drawCyclePath(Canvas canvas, int index, Rect rect) {
    if (rect.width * scale < 10) return;
    final horizontal = _unit(index * 211) > 0.5;
    final band = horizontal
        ? Rect.fromLTWH(
            rect.left,
            rect.center.dy - rect.height * 0.13,
            rect.width,
            rect.height * 0.26,
          )
        : Rect.fromLTWH(
            rect.center.dx - rect.width * 0.13,
            rect.top,
            rect.width * 0.26,
            rect.height,
          );
    canvas.drawRect(band, Paint()..color = const Color(0xFF6E6A63));
    final dash = Paint()
      ..color = const Color(0xFFF5F0E1).withValues(alpha: 0.75)
      ..strokeWidth = math.max(0.6 / scale, rect.width * 0.014);
    for (var d = 0; d < 4; d++) {
      final t = 0.15 + d * 0.23;
      canvas.drawLine(
        horizontal
            ? Offset(rect.left + rect.width * t, band.center.dy)
            : Offset(band.center.dx, rect.top + rect.height * t),
        horizontal
            ? Offset(rect.left + rect.width * (t + 0.1), band.center.dy)
            : Offset(band.center.dx, rect.top + rect.height * (t + 0.1)),
        dash,
      );
    }
  }

  /// Rails with a platform beside them.
  void _drawTramStop(Canvas canvas, int index, Rect rect) {
    if (rect.width * scale < 10) return;
    canvas.drawRect(
      Rect.fromLTWH(
        rect.left,
        rect.center.dy - rect.height * 0.18,
        rect.width,
        rect.height * 0.36,
      ),
      Paint()..color = const Color(0xFF5B6268),
    );
    final rail = Paint()
      ..color = const Color(0xFFCFD8DC)
      ..strokeWidth = math.max(0.7 / scale, rect.width * 0.022);
    for (final dy in [-0.07, 0.07]) {
      canvas.drawLine(
        Offset(rect.left, rect.center.dy + rect.height * dy),
        Offset(rect.right, rect.center.dy + rect.height * dy),
        rail,
      );
    }
    // The platform, which is what makes it a stop rather than track.
    canvas.drawRect(
      Rect.fromLTWH(
        rect.left + rect.width * 0.2,
        rect.center.dy + rect.height * 0.2,
        rect.width * 0.6,
        rect.height * 0.14,
      ),
      Paint()..color = const Color(0xFFE0E0E0),
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
}
