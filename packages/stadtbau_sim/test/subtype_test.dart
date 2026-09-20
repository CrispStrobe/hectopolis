// SPDX-License-Identifier: AGPL-3.0-or-later
// T-502: sub-types per level.
//
// A game tile is a hectare built out for one use, and a land-use class covers
// a range -- `housing_low` is anything from detached houses to infill. The
// default parameters take the middle of the class from BauNVO floor-area
// ratios; a sub-type replaces them with the measured values for one Berlin
// Flächentyp, so a level can be about sprawl or about densification rather
// than about generic housing.
import 'dart:convert';
import 'dart:io';

import 'package:stadtbau_sim/stadtbau_sim.dart';
import 'package:test/test.dart';

Map<String, dynamic> _tableOnDisk() {
  final file = File('../../data/params/tiles.json');
  expect(file.existsSync(), isTrue, reason: 'run from the package root');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

Level _level({Map<String, String> subtypes = const {}, Map<String, dynamic>? overrides}) =>
    Level(
      id: 'test',
      width: 4,
      height: 4,
      budgetKEur: 1000,
      map: List.filled(16, TileType.meadow),
      tiles: const {TileType.housingLow: 4},
      goals: const [],
      subtypes: subtypes,
      paramOverrides: overrides,
    );

void main() {
  group('the catalogue', () {
    test('every sub-type names a real tile type and real parameters', () {
      final table = _tableOnDisk();
      final subtypes = table['subtypes'] as Map<String, dynamic>;
      final tiles = table['tiles'] as Map<String, dynamic>;
      expect(subtypes, isNotEmpty);
      for (final tile in subtypes.entries) {
        expect(tiles.containsKey(tile.key), isTrue,
            reason: 'sub-types listed for unknown tile "${tile.key}"');
        final known = (tiles[tile.key] as Map<String, dynamic>).keys.toSet();
        for (final variant in (tile.value as Map<String, dynamic>).entries) {
          final params = variant.value as Map<String, dynamic>;
          expect(params, isNotEmpty,
              reason: '${tile.key}/${variant.key} overrides nothing');
          for (final key in params.keys) {
            expect(known, contains(key),
                reason: '${tile.key}/${variant.key} sets "$key", which is not '
                    'a parameter of ${tile.key}');
          }
        }
      }
    });

    test('every sub-type value carries a source', () {
      // The same invariant the whole table has, checked here too because a
      // sub-type is where a level author is most tempted to type a number.
      final subtypes = _tableOnDisk()['subtypes'] as Map<String, dynamic>;
      final missing = <String>[];
      for (final tile in subtypes.entries) {
        for (final variant in (tile.value as Map<String, dynamic>).entries) {
          for (final param
              in (variant.value as Map<String, dynamic>).entries) {
            final entry = param.value as Map<String, dynamic>;
            final source = entry['source'];
            if (source is! String || source.trim().isEmpty) {
              missing.add('${tile.key}/${variant.key}/${param.key}');
            }
          }
        }
      }
      expect(missing, isEmpty);
    });

    test('sub-types of a tile differ from one another', () {
      // A sub-type that matches its neighbours is a copy-paste, not a variant.
      final subtypes = _tableOnDisk()['subtypes'] as Map<String, dynamic>;
      for (final tile in subtypes.entries) {
        final seen = <String, String>{};
        for (final variant in (tile.value as Map<String, dynamic>).entries) {
          final values = {
            for (final p in (variant.value as Map<String, dynamic>).entries)
              p.key: (p.value as Map<String, dynamic>)['value'],
          };
          final fingerprint = jsonEncode(values);
          expect(seen.containsKey(fingerprint), isFalse,
              reason: '${tile.key}/${variant.key} has the same values as '
                  '${tile.key}/${seen[fingerprint]}');
          seen[fingerprint] = variant.key;
        }
      }
    });
  });

  group('a level that names one', () {
    test('gets the sub-type values instead of the class defaults', () {
      final defaults = SimParams.defaults().tile(TileType.housingLow);
      final detached = _level(subtypes: {'housing_low': 'detached'})
          .params()
          .tile(TileType.housingLow);
      final infill = _level(subtypes: {'housing_low': 'infill'})
          .params()
          .tile(TileType.housingLow);

      expect(detached.residentsPerHa.value, 35);
      expect(infill.residentsPerHa.value, 68);
      expect(defaults.residentsPerHa.value,
          inInclusiveRange(detached.residentsPerHa.value,
              infill.residentsPerHa.value));
    });

    test('the class defaults agree with the measurements underneath them', () {
      // The cross-check that matters. A class default comes from BauNVO
      // floor-area ratios and Destatis floor space per person; its sub-types
      // come from Berlin measurements. Two independent derivations landing in
      // the same place is more confidence than either gives alone.
      //
      // The tolerance is 10 % and exists for one known near-miss, which is
      // not a defect: housing_high's 180 sits 3 % below its lightest sub-type
      // (modern_blocks, 185) instead of inside 185-362, because the BauNVO
      // derivation used the §17 ceiling for WA/MI and 1990s blocks are what
      // building at that ceiling produces. The denser sub-types are pre-war
      // forms the current ceiling would not permit. See docs/model/tiles.md.
      final table = _tableOnDisk();
      final subtypes = table['subtypes'] as Map<String, dynamic>;
      for (final tile in subtypes.entries) {
        for (final field in ['residentsPerHa', 'sealing']) {
          final measured = <double>[];
          for (final variant in (tile.value as Map<String, dynamic>).values) {
            final entry = (variant as Map<String, dynamic>)[field];
            if (entry == null) continue;
            measured.add(
                ((entry as Map<String, dynamic>)['value'] as num).toDouble());
          }
          if (measured.isEmpty) continue;
          measured.sort();
          final low = measured.first * 0.9;
          final high = measured.last * 1.1;
          final base = ((table['tiles'] as Map<String, dynamic>)[tile.key]
              as Map<String, dynamic>)[field] as Map<String, dynamic>;
          final value = (base['value'] as num).toDouble();
          expect(value, inInclusiveRange(low, high),
              reason: '${tile.key}.$field default $value is outside the '
                  '$measured its sub-types measure, by more than 10 %');
        }
      }
    });

    test('leaves every other tile type alone', () {
      final p = _level(subtypes: {'housing_low': 'detached'}).params();
      final d = SimParams.defaults();
      for (final t in TileType.values) {
        if (t == TileType.housingLow) continue;
        expect(p.tile(t).sealing.value, d.tile(t).sealing.value,
            reason: '${t.id} changed');
      }
    });

    test('lets an explicit override win over the sub-type', () {
      final p = _level(
        subtypes: {'housing_low': 'detached'},
        overrides: {
          'tiles': {
            'housing_low': {
              'residentsPerHa': {'value': 12, 'source': 'level: test'},
            },
          },
        },
      ).params();
      expect(p.tile(TileType.housingLow).residentsPerHa.value, 12);
      // ...but keeps the parts of the sub-type it did not override.
      expect(p.tile(TileType.housingLow).sealing.value, 0.41);
    });

    test('refuses a sub-type that does not exist, by name', () {
      expect(
        () => _level(subtypes: {'housing_low': 'schrebergarten'}).params(),
        throwsA(isA<FormatException>().having((e) => e.message, 'message',
            allOf(contains('schrebergarten'), contains('housing_low')))),
      );
    });

    test('round-trips through JSON', () {
      final json = {
        'id': 'rt',
        'width': 4,
        'height': 4,
        'budgetKEur': 1000,
        'map': List.filled(4, '....'),
        'tiles': {'housing_low': 4},
        'goals': <dynamic>[],
        'subtypes': {'housing_low': 'terraced'},
      };
      final level = Level.fromJson(json);
      expect(level.subtypes, {'housing_low': 'terraced'});
      expect(level.params().tile(TileType.housingLow).residentsPerHa.value, 56);
    });
  });

  test('every sub-type a shipped level names exists', () {
    for (final level in Level.builtIn()) {
      expect(level.params, returnsNormally, reason: 'level ${level.id}');
    }
  });
}
