// SPDX-License-Identifier: AGPL-3.0-or-later
// Mirrors data/params/tiles.json and data/levels/*.json into Dart constants
// so the pure-Dart sim package (and the web build) can load them without
// file I/O.
// Usage: dart run tools/gen_params.dart   (from the repository root)
import 'dart:convert';
import 'dart:io';

void main() {
  final src = File('data/params/tiles.json');
  final out = File('packages/stadtbau_sim/lib/src/generated/default_params.dart');
  final rawWithSources = src.readAsStringSync();
  // Validate that it is JSON before embedding, and drop the prose while doing
  // it. Every parameter carries a `source` (and sometimes a `note`) because
  // that is the point of the table, but nothing at run time reads either one:
  // `Param` parses them into fields no widget touches, and the Quellen page is
  // generated from the JSON on disk at build time. Shipping them put 50 KB of
  // citations — 15 KB gzipped, most of it German — into every first load, and
  // the run that added the T-103 citations grew it by a third.
  final raw = _withoutProse(jsonDecode(rawWithSources));
  if (raw.contains("'''")) {
    stderr.writeln('tiles.json must not contain triple quotes');
    exit(1);
  }
  final buffer = StringBuffer()
    ..writeln('// SPDX-License-Identifier: AGPL-3.0-or-later')
    ..writeln('// GENERATED FILE - do not edit. Source: data/params/tiles.json')
    ..writeln('// Regenerate with: dart run tools/gen_params.dart')
    ..writeln()
    ..writeln('/// Default simulation parameters as JSON.')
    ///
    ..writeln('///')
    ..writeln('/// Values only: the `source` and `note` fields of')
    ..writeln('/// data/params/tiles.json are stripped here, because nothing')
    ..writeln('/// reads them at run time and they are 15 KB gzipped of every')
    ..writeln('/// first load. The citations live in the JSON, and the')
    ..writeln('/// generated Quellen page renders them from it.')
    ..writeln("const String defaultParamsJson = r'''")
    ..write(raw)
    ..writeln("''';");
  out.writeAsStringSync(buffer.toString());
  stdout.writeln(
    'wrote ${out.path} (${raw.length} bytes, '
    '${rawWithSources.length - raw.length} of prose left behind)',
  );

  final levelFiles = Directory('data/levels')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  final levels = StringBuffer()
    ..writeln('// SPDX-License-Identifier: AGPL-3.0-or-later')
    ..writeln('// GENERATED FILE - do not edit. Source: data/levels/*.json')
    ..writeln('// Regenerate with: dart run tools/gen_params.dart')
    ..writeln()
    ..writeln('/// Built-in levels as JSON, in file order (mirror of data/levels/).')
    ..writeln('const List<String> defaultLevelsJson = [');
  for (final f in levelFiles) {
    final text = f.readAsStringSync();
    jsonDecode(text);
    if (text.contains("'''")) {
      stderr.writeln('${f.path} must not contain triple quotes');
      exit(1);
    }
    levels
      ..writeln("  r'''")
      ..write(text)
      ..writeln("''',");
  }
  levels.writeln('];');
  final levelsOut = File('packages/stadtbau_sim/lib/src/generated/default_levels.dart');
  levelsOut.writeAsStringSync(levels.toString());
  stdout.writeln('wrote ${levelsOut.path} (${levelFiles.length} levels)');
}

/// The parameter tree with every `source` and `note` removed, as compact JSON.
Object? _stripProse(Object? node) {
  if (node is Map<String, dynamic>) {
    return {
      for (final entry in node.entries)
        if (entry.key != 'source' && entry.key != 'note')
          entry.key: _stripProse(entry.value),
    };
  }
  if (node is List) return [for (final item in node) _stripProse(item)];
  return node;
}

String _withoutProse(Object? json) =>
    const JsonEncoder.withIndent('  ').convert(_stripProse(json));
