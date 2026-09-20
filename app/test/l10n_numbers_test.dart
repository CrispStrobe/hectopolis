// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stadtbau_sim/stadtbau_sim.dart';

/// The `indicatorFormula` copy quotes parameter values, and copy does not
/// recompile when a parameter changes. T-103 moved the climate zero point from
/// 2.5 t to 5.0 t per resident-or-job and both translations kept telling the
/// player 2.5 for two days, on the one screen that exists to explain how the
/// score is computed. This pins the numbers the copy quotes to the table they
/// came from.
void main() {
  final p = SimParams.defaults();

  Map<String, String> arb(String locale) {
    final raw = jsonDecode(
      File('lib/l10n/app_$locale.arb').readAsStringSync(),
    ) as Map<String, dynamic>;
    return {
      for (final e in raw.entries)
        if (!e.key.startsWith('@')) e.key: '${e.value}',
    };
  }

  /// `5.0` in English, `5,0` in German: the copy is localised and so is the
  /// decimal separator, so the expectation has to be too.
  String number(double v, String locale, {int digits = 1}) {
    final s = v.toStringAsFixed(digits);
    return locale == 'de' ? s.replaceAll('.', ',') : s;
  }

  for (final locale in ['en', 'de']) {
    test('$locale indicatorFormula quotes the parameters it claims to', () {
      final formula = arb(locale)['indicatorFormula']!;
      // Only the values that actually come from `data/params`. The 65 dB in
      // the noise branch and the 20 km in the commuting one are constants in
      // `indicators.dart`, not table entries, so pinning them here would
      // assert against the wrong source.
      final expected = <String, String>{
        'climate': number(p.climate.zeroScoreTonsPerPerson, locale),
      };
      for (final e in expected.entries) {
        final branch = RegExp('${e.key}\\{([^}]*)\\}').firstMatch(formula);
        expect(branch, isNotNull, reason: 'no ${e.key} branch');
        expect(branch!.group(1), contains(e.value),
            reason: '${e.key} copy does not quote ${e.value}');
      }
    });
  }

  test('the flood formula names the design storm, not the alarm threshold', () {
    // Two millimetre figures live in `water`, and the indicator uses the
    // larger one. Copy that quoted 10 mm would describe a different score.
    expect(p.water.designStormMm, greaterThan(p.water.floodRiskMm));
    for (final locale in ['en', 'de']) {
      final flood = RegExp(r'flood\{([^}]*)\}')
          .firstMatch(arb(locale)['indicatorFormula']!)!
          .group(1)!;
      expect(flood.toLowerCase(), contains(locale == 'de' ? 'regen' : 'storm'));
    }
  });
}
