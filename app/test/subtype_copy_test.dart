// SPDX-License-Identifier: AGPL-3.0-or-later
// T-502: every sub-type the parameter table offers must have copy.
//
// `tileSubtypeName` and `tileSubtypeDescription` are ICU `select` messages,
// and a `select` has no exhaustiveness check: a sub-type with no branch does
// not fail to build, it silently renders the `other` branch. For a name that
// means a level quietly calls its housing "Unknown", and for a description it
// means an empty line. So the branches are checked against the table that
// defines the sub-types, in both languages.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Set<String> _subtypeIds() {
  final table =
      jsonDecode(File('../data/params/tiles.json').readAsStringSync())
          as Map<String, dynamic>;
  final subtypes = table['subtypes'] as Map<String, dynamic>;
  return {
    for (final tile in subtypes.values)
      ...(tile as Map<String, dynamic>).keys,
  };
}

Set<String> _branches(String locale, String key) {
  final arb = jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
      as Map<String, dynamic>;
  final message = arb[key] as String?;
  expect(message, isNotNull, reason: '$locale is missing $key');
  return RegExp(r'(\w+)\{')
      .allMatches(message!)
      .map((m) => m.group(1)!)
      .where((name) => name != 'select' && name != 'id')
      .toSet();
}

void main() {
  final ids = _subtypeIds();

  test('the table actually defines sub-types', () {
    expect(ids, isNotEmpty);
  });

  for (final locale in ['en', 'de']) {
    for (final key in ['tileSubtypeName', 'tileSubtypeDescription']) {
      test('$locale $key covers every sub-type', () {
        final branches = _branches(locale, key);
        expect(branches, containsAll(ids),
            reason: 'no branch for ${ids.difference(branches)} in $locale '
                '$key -- it would render the "other" branch silently');
        expect(branches.difference({...ids, 'other'}), isEmpty,
            reason: 'branch for a sub-type the table does not define');
      });
    }
  }

  test('a name is never empty, in either language', () {
    // The description may legitimately fall back to nothing; a name may not.
    for (final locale in ['en', 'de']) {
      final arb = jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
          as Map<String, dynamic>;
      final message = arb['tileSubtypeName'] as String;
      for (final id in ids) {
        final match = RegExp('$id\\{([^}]*)\\}').firstMatch(message);
        expect(match?.group(1)?.trim(), isNotEmpty,
            reason: '$locale has an empty name for $id');
      }
    }
  });
}
