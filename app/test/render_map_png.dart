// SPDX-License-Identifier: AGPL-3.0-or-later
// Renders the map painter to a PNG so tile art can be looked at (T-202).
//
// Not named *_test.dart on purpose: `flutter test` must not run it, since it
// asserts nothing and writes a file. Run it deliberately:
//
//   MAP_PNG=/tmp/map.png flutter test test/render_map_png.dart
//
// This exists because the headless-Chrome route needs about a gigabyte and a
// working compositor, which a loaded box cannot always give. RepaintBoundary
// .toImage() runs inside flutter_test with no browser at all. Text renders as
// boxes here (the test font is Ahem); the tile art is the point.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide Simulation;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stadtbau/game/game_controller.dart';
import 'package:stadtbau/l10n/generated/app_localizations.dart';
import 'package:stadtbau/ui/game_screen.dart';
import 'package:stadtbau_sim/stadtbau_sim.dart';

void main() {
  testWidgets('render the map to a png for visual inspection', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final c = GameController(size: 16);
    addTearDown(c.dispose);
    // A mixed scene: nature, water, a road, housing, shops, industry.
    for (var y = 0; y < 16; y++) {
      c.place(7, y, TileType.road);
    }
    for (var x = 8; x < 13; x++) {
      for (var y = 2; y < 5; y++) {
        c.place(x, y, TileType.housingHigh);
      }
    }
    for (var x = 8; x < 12; x++) {
      c.place(x, 6, TileType.commercial);
    }
    for (var x = 13; x < 16; x++) {
      for (var y = 8; y < 11; y++) {
        c.place(x, y, TileType.industry);
      }
    }
    for (var x = 1; x < 6; x++) {
      for (var y = 9; y < 13; y++) {
        c.place(x, y, TileType.forest);
      }
    }
    for (var x = 2; x < 5; x++) {
      c.place(x, 3, TileType.water);
    }
    c.place(5, 6, TileType.park);
    for (var i = 0; i < 36; i++) {
      c.step();
    }
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: GameScreen(controller: c, onLocaleToggle: () {}),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 300));
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final out = Platform.environment['MAP_PNG'] ?? '/tmp/map.png';
    File(out).writeAsBytesSync(data!.buffer.asUint8List());
    debugPrint('WROTE $out');
  });
}
