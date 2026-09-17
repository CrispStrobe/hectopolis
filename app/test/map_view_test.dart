// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stadtbau/game/game_controller.dart';
import 'package:stadtbau/l10n/generated/app_localizations.dart';
import 'package:stadtbau/ui/map_view.dart';
import 'package:stadtbau_sim/stadtbau_sim.dart';

/// The map is pinned to a 400 px square with an 8×8 grid, so one cell is
/// 50 map units wide.
const double _side = 400;
const double _cell = _side / 8;

Widget _app(GameController c, MapViewController m) => MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: _side,
            height: _side,
            child: MapView(controller: c, mapController: m),
          ),
        ),
      ),
    );

/// Centre of cell (x, y) in map (scene) coordinates.
Offset _sceneCentre(int x, int y) => Offset((x + 0.5) * _cell, (y + 0.5) * _cell);

void main() {
  late GameController c;
  late MapViewController m;

  setUp(() {
    c = GameController(size: 8);
    m = MapViewController();
  });

  tearDown(() {
    c.dispose();
    m.dispose();
  });

  Future<Rect> pumpMap(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app(c, m));
    return tester.getRect(find.byType(MapView));
  }

  /// Focus the map without side effects on the brush: a tap with no brush
  /// only selects a cell.
  Future<void> focusMap(WidgetTester tester, Rect rect) async {
    await tester.tapAt(rect.topLeft + _sceneCentre(0, 0));
    await tester.pump();
  }

  testWidgets('a tap places the brush in the cell under the pointer', (tester) async {
    final rect = await pumpMap(tester);
    expect(rect.size, const Size(_side, _side));
    c.setBrush(TileType.forest);

    await tester.tapAt(rect.topLeft + _sceneCentre(2, 1));
    await tester.pump();

    expect(c.sim.state.tileAt(2, 1), TileType.forest);
    expect(c.selectedCell, c.sim.state.index(2, 1));
  });

  testWidgets('a tap still hits the right cell after zooming', (tester) async {
    final rect = await pumpMap(tester);
    m.zoomIn();
    await tester.pump();
    expect(m.scale, closeTo(1.5, 1e-9));
    // Zoom is anchored on the viewport centre and the map stays inside it.
    expect(m.transformation.value.getTranslation().x, closeTo(-100, 1e-9));

    c.setBrush(TileType.industry);
    // Map coordinates -> viewport coordinates through the live transform.
    final viewport = MatrixUtils.transformPoint(m.transformation.value, _sceneCentre(2, 1));
    expect(rect.contains(rect.topLeft + viewport), isTrue);
    await tester.tapAt(rect.topLeft + viewport);
    await tester.pump();

    expect(c.sim.state.tileAt(2, 1), TileType.industry);
    // The same screen position addresses a different cell than at scale 1.
    expect(c.sim.state.tileAt(1, 0), isNot(TileType.industry));

    m.reset();
    await tester.pump();
    expect(m.scale, 1.0);
  });

  testWidgets('arrow keys move the cursor and Enter places a tile', (tester) async {
    final rect = await pumpMap(tester);
    await focusMap(tester, rect);
    expect(c.selectedCell, 0);

    c.setBrush(TileType.forest);
    // The first arrow only reveals the cursor on the current selection.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(c.cursorCell, c.sim.state.index(0, 0));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    expect(c.cursorCell, c.sim.state.index(1, 1));
    expect(c.selectedCell, c.cursorCell);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(c.sim.state.tileAt(1, 1), TileType.forest);

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    expect(c.sim.state.tileAt(1, 1), isNot(TileType.forest));

    // The cursor cannot leave the grid.
    for (var i = 0; i < 12; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    }
    expect(c.cursorCell, 0);
  });

  testWidgets('digit keys select the brush and Escape drops it', (tester) async {
    final rect = await pumpMap(tester);
    await focusMap(tester, rect);
    final types = c.allowedTypes;
    // The sandbox allows everything, so this tracks the tile table rather than
    // a number that has to be edited whenever a tile type is added.
    expect(types.length, TileType.values.length);

    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    expect(c.brush, types.first);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    expect(c.brush, types[2]);
    // 0 is the tenth tile, and the last one a digit can reach: there are only
    // ten keys. Tiles beyond the tenth are mouse- or Tab-only, and the palette
    // shows no shortcut badge on them.
    await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
    expect(c.brush, types[9]);
    expect(types.length, greaterThan(10), reason: 'the gap above is real');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(c.brush, isNull);
  });
}
