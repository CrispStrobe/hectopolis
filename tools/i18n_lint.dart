// SPDX-License-Identifier: AGPL-3.0-or-later
// i18n lint (task T-004):
//  1. every key in app_en.arb exists in app_de.arb and vice versa;
//  2. every key is actually used — `l10n.<key>` somewhere under app/lib or
//     app/test. A key nobody reads is copy two translators maintain and
//     nobody sees; eight had accumulated. `// i18n-unused: <key> <why>`
//     anywhere under app/ keeps one deliberately.
//  3. no translatable string literal is passed directly to Text(...) or to
//     `tooltip:` / `message:` / `label:` / `title:` / `hintText:` /
//     `semanticLabel:` named arguments inside app/lib (generated code
//     excluded). Literals that only interpolate values ('$count', '$a · $b')
//     are allowed. Lines containing `// i18n-ignore` are skipped.
// Usage: dart run tools/i18n_lint.dart   (from the repository root)
import 'dart:convert';
import 'dart:io';

int main() {
  var failures = 0;

  final en = _readArb('app/lib/l10n/app_en.arb');
  final de = _readArb('app/lib/l10n/app_de.arb');
  for (final k in en.difference(de)) {
    stderr.writeln('missing in app_de.arb: $k');
    failures++;
  }
  for (final k in de.difference(en)) {
    stderr.writeln('missing in app_en.arb: $k');
    failures++;
  }

  // Keys nothing reads. The generated localizations are excluded, since they
  // define every key by construction and would make the check vacuous.
  final dartSources = <String>[];
  for (final root in ['app/lib', 'app/test']) {
    final dir = Directory(root);
    if (!dir.existsSync()) continue;
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.contains('/l10n/generated/')) continue;
      dartSources.add(entity.readAsStringSync());
    }
  }
  final allDart = dartSources.join('\n');
  final keptKeys = RegExp(r'// i18n-unused:\s*(\w+)')
      .allMatches(allDart)
      .map((m) => m.group(1)!)
      .toSet();
  for (final key in en) {
    if (keptKeys.contains(key)) continue;
    if (RegExp('\\.${RegExp.escape(key)}\\b').hasMatch(allDart)) continue;
    stderr.writeln(
      'unused key "$key": nothing under app/ reads it. Remove it from both '
      'ARB files, or mark it with a `// i18n-unused: $key <why>` comment.',
    );
    failures++;
  }

  final literalText = RegExp(r'''Text\(\s*(['"])''');
  final literalNamed = RegExp(r'''\b(?:tooltip|message|label|title|hintText|semanticLabel)\s*:\s*(['"])''');
  final dir = Directory('app/lib');
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    if (entity.path.contains('/l10n/generated/')) continue;
    final lines = entity.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.contains('// i18n-ignore')) continue;
      final match = literalText.firstMatch(line) ?? literalNamed.firstMatch(line);
      if (match == null) continue;
      if (_hasTranslatableText(line.substring(match.end - 1))) {
        stderr.writeln('${entity.path}:${i + 1}: hard-coded user-facing string: ${line.trim()}');
        failures++;
      }
    }
  }

  if (failures == 0) {
    stdout.writeln('i18n lint: ok (${en.length} keys in both languages)');
    return 0;
  }
  stderr.writeln('i18n lint: $failures problem(s)');
  exitCode = 1;
  return 1;
}

/// A literal that only interpolates values carries no translatable words;
/// anything with letters left over after removing interpolations does.
bool _hasTranslatableText(String fromQuote) {
  final quote = fromQuote[0];
  final end = fromQuote.indexOf(quote, 1);
  if (end < 0) return true;
  var literal = fromQuote.substring(1, end);
  literal = literal.replaceAll(RegExp(r'\\.'), '');
  literal = literal.replaceAll(RegExp(r'\$\{[^}]*\}'), '');
  literal = literal.replaceAll(RegExp(r'\$[A-Za-z_][A-Za-z0-9_]*'), '');
  return RegExp('[A-Za-z]').hasMatch(literal);
}

Set<String> _readArb(String path) {
  final json = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  return json.keys.where((k) => !k.startsWith('@')).toSet();
}
