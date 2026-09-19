// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stadtbau/ui/tile_style.dart';

void main() {
  const base = Color(0xFF388E3C);

  test('seasonal vegetation keeps the annual-mean colour unchanged', () {
    expect(seasonalVegetationColor(base, 1), base);
  });

  test('winter is warmer and less green than the growing season', () {
    final winter = seasonalVegetationColor(base, 0.278);
    final summer = seasonalVegetationColor(base, 1.778);

    expect(winter, isNot(base));
    expect(summer, isNot(base));
    expect(winter.r, greaterThan(summer.r));
    expect(winter.g - winter.r, lessThan(summer.g - summer.r));
  });

  test('seasonal colour clamps factors beyond the model range', () {
    expect(
      seasonalVegetationColor(base, -10),
      seasonalVegetationColor(base, 0.25),
    );
    expect(
      seasonalVegetationColor(base, 10),
      seasonalVegetationColor(base, 1.8),
    );
  });
}
