// SPDX-License-Identifier: AGPL-3.0-or-later
// T-701: contrast, as something CI can fail on rather than something we
// believe. Ratios are WCAG 2.1 (BITV 2.0 and EN 301 549 both point at it):
//
//   1.4.3 Contrast (Minimum) -- text needs 4.5:1, large text 3:1
//   1.4.11 Non-text Contrast -- UI components and graphics need 3:1
//
// Only pairs that actually meet on screen are listed. Tile art is exempt from
// 1.4.11 by its own wording ("a particular presentation of graphics is
// essential"): the colours are the map, not a control.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stadtbau/ui/goals_panel.dart';
import 'package:stadtbau/ui/indicator_panel.dart';

/// Relative luminance, WCAG 2.1 definition.
double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

double contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// Flattens a translucent foreground onto its background, since that is what
/// the eye sees and what the ratio has to be computed from.
Color _over(Color fg, Color bg) => Color.alphaBlend(fg, bg);

void main() {
  final themes = {
    'light': ThemeData(
      colorSchemeSeed: const Color(0xFF2E7D32),
      useMaterial3: true,
    ),
    'dark': ThemeData(
      colorSchemeSeed: const Color(0xFF2E7D32),
      brightness: Brightness.dark,
      useMaterial3: true,
    ),
  };

  group('WCAG 1.4.3: text', () {
    for (final entry in themes.entries) {
      final name = entry.key;
      final s = entry.value.colorScheme;
      test('the generated scheme keeps its on-colours legible ($name)', () {
        final pairs = <String, (Color, Color)>{
          'onSurface/surface': (s.onSurface, s.surface),
          'onSurfaceVariant/surfaceContainerHighest': (
            s.onSurfaceVariant,
            s.surfaceContainerHighest,
          ),
          'onPrimary/primary': (s.onPrimary, s.primary),
          'onPrimaryContainer/primaryContainer': (
            s.onPrimaryContainer,
            s.primaryContainer,
          ),
          'onSecondaryContainer/secondaryContainer': (
            s.onSecondaryContainer,
            s.secondaryContainer,
          ),
          'onError/error': (s.onError, s.error),
          'onErrorContainer/errorContainer': (
            s.onErrorContainer,
            s.errorContainer,
          ),
        };
        pairs.forEach((label, pair) {
          final ratio = contrast(_over(pair.$1, pair.$2), pair.$2);
          expect(ratio, greaterThanOrEqualTo(4.5),
              reason: '$name $label is ${ratio.toStringAsFixed(2)}:1');
        });
      });

      test('a met goal is readable text, not just a pleasant colour ($name)',
          () {
        // goals_panel paints a met goal in this colour as *text*, so it is
        // 1.4.3 at 4.5:1, not 1.4.11 at 3:1.
        final color = goalMetColor(entry.value.brightness);
        final ratio = contrast(_over(color, s.surface), s.surface);
        expect(ratio, greaterThanOrEqualTo(4.5),
            reason: '$name met-goal text is ${ratio.toStringAsFixed(2)}:1 '
                'on the surface');
      });
    }
  });

  group('WCAG 1.4.11: controls and meters', () {
    for (final entry in themes.entries) {
      final name = entry.key;
      final s = entry.value.colorScheme;
      test('every gauge reading stands out from its track ($name)', () {
        // The bar is a meter: its fill must be distinguishable from the track
        // behind it at every value it can take, not only at the ends.
        for (var v = 0; v <= 100; v += 5) {
          final fill = indicatorBarColor(
            v.toDouble(),
            dark: entry.value.brightness == Brightness.dark,
          );
          final ratio = contrast(
            _over(fill, s.surfaceContainerHighest),
            s.surfaceContainerHighest,
          );
          expect(ratio, greaterThanOrEqualTo(3.0),
              reason: '$name gauge at $v is ${ratio.toStringAsFixed(2)}:1 '
                  'against its track');
        }
      });
    }
  });
}
