// SPDX-License-Identifier: AGPL-3.0-or-later
// T-703: renders docs/ into a static site, and generates the "Quellen" page
// from the `source` fields in data/params/*.json so the list of datasets and
// laws cannot drift from the parameters that cite them.
//
// Deliberately dependency-free:
//   * no markdown package, so `dart run` works with nothing fetched and CI
//     needs no extra toolchain. The renderer covers exactly the subset the
//     docs use and *fails* on anything else (see _unsupported) rather than
//     emitting literal markdown that nobody would notice.
//   * no KaTeX/MathJax from a CDN. Every first-load request must come from
//     our own origin (T-702), and a maths renderer would be the one
//     third-party request left in the project. Formulas are typeset from the
//     backticked source the docs already use.
//
// Usage: dart run tools/build_docs_site.dart [--out <dir>] [--check]
//   --check  build into a temporary directory and only report; writes nothing.
import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  var out = 'docs/_site';
  final check = args.contains('--check');
  final i = args.indexOf('--out');
  if (i >= 0) {
    if (i + 1 >= args.length) _die('--out needs a directory');
    out = args[i + 1];
  }
  if (check) {
    out = Directory.systemTemp.createTempSync('hectopolis-docs').path;
  }

  final site = SiteBuilder(out);
  site.build();
  if (check) {
    Directory(out).deleteSync(recursive: true);
    stdout.writeln('== docs site: check only, nothing written');
  } else {
    stdout.writeln('== docs site: ${site.written} files in $out');
  }
}

Never _die(String message) {
  stderr.writeln('build_docs_site: $message');
  exit(1);
}

// ---------------------------------------------------------------------------
// The pages, in navigation order. A doc under docs/ that is missing here is a
// hard failure: adding a model doc should not silently leave it unpublished.
// docs/release/ is intentionally excluded -- it is release plumbing for us
// (store listings, an App Review appeal), not documentation of the model.

class PageSpec {
  const PageSpec(this.source, this.output, this.section, {this.navTitle});
  final String source; // path relative to the repository root
  final String output; // path relative to the site root
  final String section;
  final String? navTitle;
}

const _section1 = 'Overview';
const _sectionModel = 'The model';
const _sectionProject = 'The project';

const _pages = <PageSpec>[
  PageSpec('docs/model/README.md', 'model/index.html', _section1,
      navTitle: 'Model overview'),
  PageSpec('docs/model/tiles.md', 'model/tiles.html', _sectionModel),
  PageSpec('docs/model/noise.md', 'model/noise.html', _sectionModel),
  PageSpec('docs/model/air.md', 'model/air.html', _sectionModel),
  PageSpec('docs/model/heat.md', 'model/heat.html', _sectionModel),
  PageSpec('docs/model/water.md', 'model/water.html', _sectionModel),
  PageSpec('docs/model/access.md', 'model/access.html', _sectionModel),
  PageSpec('docs/model/biodiversity.md', 'model/biodiversity.html',
      _sectionModel),
  PageSpec('docs/model/commute.md', 'model/commute.html', _sectionModel),
  PageSpec('docs/model/economy.md', 'model/economy.html', _sectionModel),
  PageSpec('docs/model/seasons.md', 'model/seasons.html', _sectionModel),
  PageSpec('docs/model/loops.md', 'model/loops.html', _sectionModel),
  PageSpec('docs/model/indicators.md', 'model/indicators.html', _sectionModel),
  PageSpec('docs/model/calibration.md', 'model/calibration.html',
      _sectionModel),
  PageSpec('docs/adding-a-tile-type.md', 'adding-a-tile-type.html',
      _sectionProject),
  PageSpec('docs/level-generator.md', 'level-generator.html', _sectionProject),
  PageSpec('docs/multiplayer.md', 'multiplayer.html', _sectionProject),
  PageSpec('docs/privacy.md', 'privacy.html', _sectionProject),
];

const _excludedDirs = <String>{'docs/release', 'docs/_site'};

// ---------------------------------------------------------------------------

class SiteBuilder {
  SiteBuilder(this.outDir);
  final String outDir;
  int written = 0;

  /// Maps a markdown path (as it appears in a link) to its site-relative page.
  late final Map<String, String> _pageOf = {
    for (final p in _pages) p.source: p.output,
  };

  void build() {
    _assertEveryDocIsPublished();
    final sources = SourceIndex.read();

    final nav = <String, List<_NavEntry>>{};
    void add(String section, String title, String href) =>
        (nav[section] ??= []).add(_NavEntry(title, href));

    add(_section1, 'Start', 'index.html');
    for (final p in _pages) {
      final doc = MarkdownDoc.parse(p.source);
      add(p.section, p.navTitle ?? doc.title, p.output);
    }
    add('Sources', 'Quellen', 'quellen.html');

    for (final p in _pages) {
      final doc = MarkdownDoc.parse(p.source);
      _write(
        p.output,
        _layout(
          title: doc.title,
          here: p.output,
          nav: nav,
          body: doc.render(depthOf(p.output), _pageOf),
          footerSource: p.source,
        ),
      );
    }

    _write(
      'quellen.html',
      _layout(
        title: 'Quellen',
        here: 'quellen.html',
        nav: nav,
        body: sources.renderPage(),
        footerSource: 'data/params/tiles.json + the References sections',
      ),
    );
    _write(
      'index.html',
      _layout(
        title: 'The Hectopolis model',
        here: 'index.html',
        nav: nav,
        body: _landing(sources),
        footerSource: null,
      ),
    );
    _write('style.css', _css);
  }

  void _assertEveryDocIsPublished() {
    final found = <String>[];
    for (final e in Directory('docs').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.md')) continue;
      final rel = e.path.replaceAll('\\', '/');
      if (_excludedDirs.any((d) => rel.startsWith('$d/'))) continue;
      found.add(rel);
    }
    final missing = found.where((f) => !_pageOf.containsKey(f)).toList()..sort();
    if (missing.isNotEmpty) {
      _die('these docs are not in the site navigation, add them to _pages in '
          'tools/build_docs_site.dart:\n  ${missing.join('\n  ')}');
    }
    final gone = _pages.where((p) => !File(p.source).existsSync()).toList();
    if (gone.isNotEmpty) {
      _die('these pages point at files that do not exist:\n  '
          '${gone.map((p) => p.source).join('\n  ')}');
    }
  }

  void _write(String rel, String content) {
    final f = File('$outDir/$rel');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(content);
    written++;
  }

  static int depthOf(String output) => output.split('/').length - 1;

  String _layout({
    required String title,
    required String here,
    required Map<String, List<_NavEntry>> nav,
    required String body,
    required String? footerSource,
  }) {
    final up = '../' * depthOf(here);
    final navHtml = StringBuffer();
    nav.forEach((section, entries) {
      navHtml.writeln('<h2>${esc(section)}</h2>\n<ul>');
      for (final e in entries) {
        final current = e.href == here;
        navHtml.writeln('<li${current ? ' class="here"' : ''}>'
            '<a href="$up${e.href}"'
            '${current ? ' aria-current="page"' : ''}>${esc(e.title)}</a></li>');
      }
      navHtml.writeln('</ul>');
    });
    final footer = footerSource == null
        ? ''
        : '<p class="src">Source: <code>${esc(footerSource)}</code></p>';
    return '''<!doctype html>
<html lang="en">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)} — Hectopolis model</title>
<link rel="stylesheet" href="${up}style.css">
<body>
<a class="skip" href="#content">Skip to content</a>
<nav aria-label="Documentation">
  <p class="brand"><a href="${up}index.html">Hectopolis</a><span>model documentation</span></p>
  $navHtml
  <p class="back"><a href="$up../">&larr; Play the game</a></p>
</nav>
<main id="content">
$body
$footer
<p class="lic">Hectopolis is free software under the
<a href="https://www.gnu.org/licenses/agpl-3.0.html">GNU AGPL v3 or later</a>,
with an additional app-store permission. This documentation is part of the
program's source.</p>
</main>
</body>
</html>
''';
  }

  String _landing(SourceIndex s) {
    final cards = StringBuffer();
    for (final p in _pages.where((p) => p.section == _sectionModel)) {
      final doc = MarkdownDoc.parse(p.source);
      final code = doc.codePath;
      // Every model file sits under the same package directory; repeating the
      // prefix on sixteen cards only pushed the useful half out of the box.
      final short = code?.replaceFirst('packages/stadtbau_sim/lib/src/', '');
      cards.writeln('<li><a href="${p.output}"><strong>${esc(doc.title)}</strong>'
          '${short == null ? '' : '<code>${esc(short)}</code>'}'
          '</a></li>');
    }
    return '''
<h1>The Hectopolis model</h1>
<p class="lead">Hectopolis is a city-building game whose simulation is built
out of published models, not out of feel. Every field it computes &mdash; noise,
air, heat, runoff, access, habitat, commuting &mdash; follows a formula from a
standard or a paper, and every number that formula reads carries a citation in
<code>data/params/tiles.json</code>.</p>
<p>These pages are that documentation, rendered from the
<a href="https://github.com/CrispStrobe/hectopolis/tree/main/docs">docs
directory of the repository</a>. Each one states the formula as implemented,
the parameters it reads, what it is calibrated against, and &mdash; the part
most models leave out &mdash; what it does <em>not</em> model.</p>
<h2>Components</h2>
<ul class="cards">
$cards</ul>
<h2>Where the numbers come from</h2>
<p>${s.coverageSentence()}
The <a href="quellen.html">Quellen page</a> lists every law, standard and
dataset the simulation relies on, with the parameters that cite each one, and
it is generated from the parameter file itself &mdash; so a number added
without a source shows up there rather than hiding.</p>
''';
  }
}

class _NavEntry {
  const _NavEntry(this.title, this.href);
  final String title;
  final String href;
}

// ---------------------------------------------------------------------------
// Markdown: the subset the docs use, and a loud failure for everything else.

class MarkdownDoc {
  MarkdownDoc(this.path, this.lines);
  final String path;
  final List<String> lines;

  static final _cache = <String, MarkdownDoc>{};
  static MarkdownDoc parse(String path) => _cache.putIfAbsent(
      path, () => MarkdownDoc(path, File(path).readAsLinesSync()));

  String get title {
    for (final l in lines) {
      if (l.startsWith('# ')) return l.substring(2).trim();
    }
    _die('$path has no level-1 heading');
  }

  /// The implementation file the doc names in its opening `Code:` line, if any.
  String? get codePath {
    for (final l in lines.take(8)) {
      final m = RegExp(r'^Code: `([^`]+)`').firstMatch(l);
      if (m != null) return m.group(1);
    }
    return null;
  }

  String render(int depth, Map<String, String> pageOf) {
    final b = StringBuffer();
    final ids = <String>{};
    var i = 0;

    void flushParagraph(List<String> para) {
      if (para.isEmpty) return;
      final joined = para.map((l) => l.trim()).join(' ');
      // A paragraph that is nothing but one code span is a display formula.
      if (RegExp(r'^`[^`]+`$').hasMatch(joined)) {
        b.writeln('<p class="formula">'
            '<code>${esc(joined.substring(1, joined.length - 1))}</code></p>');
      } else {
        b.writeln('<p>${_inline(joined, depth, pageOf, path)}</p>');
      }
      para.clear();
    }

    final para = <String>[];
    while (i < lines.length) {
      final line = lines[i];
      _unsupported(path, i + 1, line);

      if (line.trim().isEmpty) {
        flushParagraph(para);
        i++;
        continue;
      }

      // Fenced code: verbatim, and treated as a formula block when it has no
      // code punctuation -- which is how the model docs write derivations.
      if (line.startsWith('```')) {
        flushParagraph(para);
        final body = <String>[];
        i++;
        while (i < lines.length && !lines[i].startsWith('```')) {
          body.add(lines[i]);
          i++;
        }
        if (i >= lines.length) _die('$path: unterminated code fence');
        i++;
        final isFormula = body.every((l) => !l.contains(';') && !l.contains('{'));
        b.writeln('<pre class="${isFormula ? 'formula-block' : 'code'}">'
            '${esc(body.join('\n'))}</pre>');
        continue;
      }

      if (line.startsWith('>')) {
        flushParagraph(para);
        final quoted = <String>[];
        while (i < lines.length && lines[i].startsWith('>')) {
          quoted.add(lines[i].replaceFirst(RegExp(r'^> ?'), '').trim());
          i++;
        }
        b.writeln('<blockquote><p>'
            '${_inline(quoted.join(' '), depth, pageOf, path)}</p></blockquote>');
        continue;
      }

      final heading = RegExp(r'^(#{1,4}) +(.*)$').firstMatch(line);
      if (heading != null) {
        flushParagraph(para);
        final level = heading.group(1)!.length;
        final text = heading.group(2)!.trim();
        var id = _slug(text);
        var n = 2;
        while (!ids.add(id)) {
          id = '${_slug(text)}-$n';
          n++;
        }
        final inner = _inline(text, depth, pageOf, path);
        b.writeln(level == 1
            ? '<h1>$inner</h1>'
            : '<h$level id="$id"><a class="anchor" href="#$id">$inner</a></h$level>');
        i++;
        continue;
      }

      if (line.startsWith('|')) {
        flushParagraph(para);
        final rows = <String>[];
        while (i < lines.length && lines[i].startsWith('|')) {
          rows.add(lines[i]);
          i++;
        }
        b.writeln(_table(rows, depth, pageOf, path));
        continue;
      }

      final bullet = RegExp(r'^(-|\d+\.) +(.*)$').firstMatch(line);
      if (bullet != null) {
        flushParagraph(para);
        final ordered = bullet.group(1) != '-';
        final items = <String>[];
        while (i < lines.length) {
          final m = RegExp(r'^(-|\d+\.) +(.*)$').firstMatch(lines[i]);
          if (m != null) {
            items.add(m.group(2)!.trim());
            i++;
          } else if (lines[i].startsWith('  ') && items.isNotEmpty) {
            items[items.length - 1] += ' ${lines[i].trim()}'; // continuation
            i++;
          } else {
            break;
          }
        }
        final tag = ordered ? 'ol' : 'ul';
        b.writeln('<$tag>');
        for (final it in items) {
          b.writeln('<li>${_inline(it, depth, pageOf, path)}</li>');
        }
        b.writeln('</$tag>');
        continue;
      }

      para.add(line);
      i++;
    }
    flushParagraph(para);
    return b.toString();
  }

  String _table(
      List<String> rows, int depth, Map<String, String> pageOf, String path) {
    List<String> cells(String row) {
      var r = row.trim();
      if (r.startsWith('|')) r = r.substring(1);
      if (r.endsWith('|')) r = r.substring(0, r.length - 1);
      return r.split('|').map((c) => c.trim()).toList();
    }

    if (rows.length < 2) _die('$path: table needs a header and a delimiter row');
    final header = cells(rows[0]);
    if (!RegExp(r'^[\s\-:|]+$').hasMatch(rows[1])) {
      _die('$path: table header is not followed by a delimiter row: ${rows[1]}');
    }
    final b = StringBuffer('<div class="tablewrap"><table>\n<thead><tr>');
    for (final h in header) {
      b.write('<th>${_inline(h, depth, pageOf, path)}</th>');
    }
    b.writeln('</tr></thead>\n<tbody>');
    for (final row in rows.skip(2)) {
      b.write('<tr>');
      for (final c in cells(row)) {
        b.write('<td>${_inline(c, depth, pageOf, path)}</td>');
      }
      b.writeln('</tr>');
    }
    b.writeln('</tbody></table></div>');
    return b.toString();
  }
}

/// Markdown we do not implement. Emitting it literally would look like a typo
/// on the page and nobody would trace it back to here, so stop instead.
void _unsupported(String path, int line, String text) {
  final bad = <RegExp, String>{
    RegExp(r'!\['): 'images',
    RegExp(r'^\s{2,}[-*+] '): 'nested lists',
    // An autolink at the start of a line is not raw HTML; _spans handles it.
    RegExp(r'^\s*<(?!https?://)[a-zA-Z/]'): 'raw HTML',
    RegExp(r'^\s*[-*+] {2,}\S'): 'indented list markers',
    RegExp(r'\]\[')  : 'reference links',
    RegExp(r'^={3,}$'): 'setext headings',
  };
  for (final e in bad.entries) {
    if (e.key.hasMatch(text)) {
      _die('$path:$line uses ${e.value}, which this renderer does not '
          'implement. Either rewrite the line or extend '
          'tools/build_docs_site.dart:\n  $text');
    }
  }
}

String esc(String s) => const HtmlEscape(HtmlEscapeMode.element).convert(s);

String _slug(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[`*_]'), '')
    .replaceAll(RegExp(r'[^a-z0-9äöüß]+'), '-')
    .replaceAll(RegExp(r'^-|-$'), '');

/// Inline spans. Code spans are lifted out to placeholders first, so their
/// contents are never reinterpreted as emphasis (a `**` inside a formula is
/// not bold) -- but emphasis around them still closes, which splitting the
/// string on backticks would have broken: `**Respect `_lowDetail`**`.
String _inline(String text, int depth, Map<String, String> pageOf, String path) {
  final codes = <String>[];
  final buf = StringBuffer();
  var rest = text;
  while (true) {
    final open = rest.indexOf('`');
    if (open < 0) {
      buf.write(rest);
      break;
    }
    final close = rest.indexOf('`', open + 1);
    if (close < 0) _die('$path: unbalanced backtick in: $text');
    buf.write(rest.substring(0, open));
    buf.write('\u0001${codes.length}\u0001');
    codes.add(rest.substring(open + 1, close));
    rest = rest.substring(close + 1);
  }
  var html = _spans(buf.toString(), depth, pageOf, path);
  for (var i = 0; i < codes.length; i++) {
    html = html.replaceAll('\u0001$i\u0001', '<code>${esc(codes[i])}</code>');
  }
  if (html.contains('\u0001')) _die('$path: code placeholder survived in: $text');
  return html;
}

String _spans(String text, int depth, Map<String, String> pageOf, String path) {
  var s = esc(text);
  s = s.replaceAllMapped(
      RegExp(r'\*\*([^*]+)\*\*'), (m) => '<strong>${m.group(1)}</strong>');
  s = s.replaceAllMapped(
      RegExp(r'(?<![\w*])\*([^*]+)\*(?![\w*])'), (m) => '<em>${m.group(1)}</em>');
  // Autolinks: <https://example.org>. esc() has already turned the angle
  // brackets into entities, which is why the pattern matches those.
  s = s.replaceAllMapped(RegExp(r'&lt;(https?://[^&\s]+)&gt;'),
      (m) => '<a href="${m.group(1)}">${m.group(1)}</a>');
  s = s.replaceAllMapped(RegExp(r'\[([^\]]+)\]\(([^)]+)\)'), (m) {
    final label = m.group(1)!;
    final href = _rewriteLink(m.group(2)!, depth, pageOf, path);
    return '<a href="$href">$label</a>';
  });
  return s;
}

String _rewriteLink(
    String href, int depth, Map<String, String> pageOf, String path) {
  if (href.startsWith('http') || href.startsWith('#') ||
      href.startsWith('mailto:')) {
    return href;
  }
  final target = href.split('#').first;
  final fragment = href.contains('#') ? '#${href.split('#').last}' : '';
  // Links in the docs are written relative to the repository root.
  for (final candidate in [target, 'docs/$target', 'docs/model/$target']) {
    final page = pageOf[candidate];
    if (page != null) return '${'../' * depth}$page$fragment';
  }
  if (target.endsWith('/')) {
    // A directory link (docs/model/) points at that section's index.
    final page = pageOf['${target}README.md'];
    if (page != null) return '${'../' * depth}$page$fragment';
  }
  _die('$path links to "$href", which is not a page of this site. Publish it '
      'in _pages, or make the link absolute.');
}

// ---------------------------------------------------------------------------
// Quellen: every dataset and law, read out of the parameter file.

/// An authority we recognise in a `source` string, with what it actually is.
/// A string matching none of these is still published, under "Further
/// citations" -- unknown must mean visible, never dropped.
class Authority {
  const Authority(this.id, this.pattern, this.name, this.what);
  final String id;
  final String pattern;
  final String name;
  final String what;
}

const _authorities = <Authority>[
  Authority('roadzone', r'Forman|Reijnen', 'Road-effect zone (Forman & Deblinger 2000; Reijnen & Foppen)',
      'How far a road disturbs the life beside it. A four-lane highway averages '
          'about 600 m; species-specific disturbance distances derived from '
          'traffic noise run from tens of metres to over a kilometre. Sets the '
          'road threat distance in habitat quality.'),
  Authority('invest', r'InVEST', 'InVEST (Natural Capital Project)',
      'Open-source ecosystem-service models. Hectopolis follows the Urban '
          'Cooling and Habitat Quality modules, including their example '
          'biophysical tables.'),
  Authority('bkompv', r'BKompV', 'BKompV Anlage 2',
      'Bundeskompensationsverordnung, the German federal compensation '
          'regulation. Its Anlage 2 assigns a biotope value (0–24) to every '
          'biotope type; those values are the habitat scores of the tiles.'),
  Authority('tr55', r'TR-55|NRCS', 'USDA NRCS TR-55',
      'Urban Hydrology for Small Watersheds (1986), the curve-number runoff '
          'method and its Table 2-2 curve numbers. US government work, public '
          'domain.'),
  Authority('kostra', r'KOSTRA', 'KOSTRA-DWD-2020',
      'The DWD design-rainfall atlas for Germany '
          '(doi:10.5676/DWD/KOSTRA-DWD-2020). Supplies the design storm.'),
  Authority('talarm', r'TA L[äa]rm', 'TA Lärm',
      'Technische Anleitung zum Schutz gegen Lärm, the German immission '
          'guidance whose area-type limits (55 dB(A) day in a general '
          'residential area) the noise score uses.'),
  Authority('din18005', r'DIN 18005', 'DIN 18005-1 area-related sound power',
      'Ziffer 5.2.3 sets the flächenbezogener Schallleistungspegel a '
          'commercial (60 dB(A)/m²) or industrial (65) hectare may radiate. '
          'Spread over a hectare and taken to the 50 m tile reference, it is '
          'the emission of those two tiles.'),
  Authority('rls19', r'RLS-19', 'RLS-19',
      'Richtlinien für den Lärmschutz an Straßen, published as an '
          'administrative regulation (BayMBl. 2021 Nr. 255). Road emission '
          'scales with 10·log10(Q).'),
  Authority('iso9613', r'ISO 9613', 'ISO 9613-2',
      'Attenuation of sound during propagation outdoors: geometric '
          'divergence, foliage attenuation (Table A.2) and the practical caps.'),
  Authority('cnossos', r'CNOSSOS', 'CNOSSOS-EU (Directive (EU) 2015/996)',
      'The EU common noise assessment methods. Roads are segmented into '
          '100 m point sources whose energetic sum gives line-source decay.'),
  Authority('who', r'\bWHO\b', 'World Health Organization',
      'Environmental Noise Guidelines for the European Region (2018), Night '
          'Noise Guidelines for Europe (2009) and Urban green spaces (2016), '
          'with the 3-30-300 rule (Konijnendijk 2021).'),
  Authority('mid', r'MiD 2017', 'MiD 2017 (Mobilität in Deutschland)',
      'The national travel survey (BMVI/infas): modal split by trip distance, '
          'mean commute length, and the cycling analyses.'),
  Authority('poeplau', r'Poeplau', 'Poeplau & Don 2013 / Poeplau et al. 2017',
      'European meta-analyses of soil organic carbon after land-use change. '
          'Converting cropland to grassland builds about 0.8 t C/ha/yr, with '
          'the 2017 paper cautioning that highly productive arable land is a '
          'poor candidate.'),
  Authority('peat', r'Greifswald', 'Greifswald Mire Centre',
      'Rewetting drained peat saves at least 20 t CO₂-eq per hectare and '
          'year against drained grassland, and a rewetted fen turns from '
          'source to sink over roughly 15 years. Sets the wetland tile.'),
  Authority('destatis', r'Destatis|Zensus 2022', 'Destatis / Zensus 2022',
      'Federal Statistical Office. The 100 m population grid sets the cell '
          'size (1 ha), and the tax press releases set per-resident and '
          'per-job municipal revenue.'),
  Authority('uba', r'\bUBA\b', 'Umweltbundesamt',
      'German Environment Agency: fleet CO₂ per car-km, the grid emission '
          'factor, per-resident heating emissions and soil carbon sinks.'),
  Authority('emep', r'EMEP/EEA', 'EMEP/EEA Air Pollutant Emission Inventory '
      'Guidebook',
      'The European emission-factor reference. Sets the relative NOx/PM '
          'emission strengths of roads, industry, commerce and housing.'),
  Authority('copernicus', r'Copernicus', 'Copernicus Imperviousness',
      'The pan-European high-resolution imperviousness layer, used for the '
          'sealed fraction of each land cover.'),
  Authority('umweltatlas', r'Umweltatlas', 'Umweltatlas Berlin 01.02 Versiegelung',
      'Berlin measures the sealed fraction of every block from satellite '
          'imagery, building outlines and street-survey data, and publishes '
          'the mean per land-use type. It is the only German dataset that '
          'measures sealing by use rather than assuming it, so the built '
          'tiles take their sealed fraction from it '
          '(dl-de/zero-2.0).'),
  Authority('baunvo', r'BauNVO', 'BauNVO',
      'Baunutzungsverordnung: the site-occupancy (GRZ) and floor-area (GFZ) '
          'ceilings from which residents and jobs per hectare are derived.'),
  Authority('gifpro', r'GIFPRO', 'GIFPRO Flächenkennziffern',
      'The standard German method for forecasting commercial land demand, in '
          'square metres of net building land per employee. Inverted, it '
          'gives jobs per hectare: 225 m² on the standard model, 250 for '
          'manufacturing, 100 for business services.'),
  Authority('bbsr', r'BBSR', 'BBSR',
      'Bundesinstitut für Bau-, Stadt- und Raumforschung: employment density '
          'per hectare by use, walking catchments for local supply, and '
          'residential-satisfaction weights.'),
  Authority('hde', r'\bHDE\b', 'HDE Zahlenspiegel',
      'Handelsverband Deutschland: retail floor space per resident '
          '(~1.4 m²/EW), which calibrates the Huff shopping model.'),
  Authority('nowak', r'Nowak', 'Nowak et al. 2006 (i-Tree)',
      'Air-pollutant removal by urban trees, the basis for the deposition '
          'term in the air model.'),
  Authority('thuenen', r'Th[üu]nen', 'Thünen-Institut',
      'Bundeswaldinventur and soil-carbon work: the net CO₂ sink of growing '
          'forest and of grassland.'),
  Authority('bfn', r'BfN', 'BfN-Schriften',
      'Bundesamt für Naturschutz: how long compensation measures take to '
          'develop, which sets biotope recovery times.'),
  Authority('dwd', r'\bDWD\b', 'Deutscher Wetterdienst',
      'Prevailing wind direction and speed, the vegetation period, and the '
          '2–4 K urban heat island intensity of German mid-size cities.'),
  Authority('galk', r'GALK', 'GALK green-space benchmarks',
      'The Deutsche Gartenamtsleiterkonferenz collects what municipal parks '
          'departments actually spend: park lawn about €0.40/m² a year for '
          'mowing alone, a park tree about €52 a year. Sets park and meadow '
          'upkeep.'),
  Authority('difu', r'Difu|KfW', 'Difu / KfW Kommunalpanel',
      'Municipal infrastructure maintenance backlogs, used for road upkeep '
          'per 100 m section.'),
  Authority('huff', r'Huff 19', 'Huff (1963)',
      'The gravity model of retail catchments, with a walking-distance '
          'exponent of about 2.'),
  Authority('species', r'Arrhenius|MacArthur', 'Arrhenius / MacArthur–Wilson',
      'The species–area relationship; z ≈ 0.25–0.35 for habitat islands.'),
  Authority('plume', r'Pasquill|Gaussian plume', 'Pasquill–Gifford',
      'The Gaussian-plume dispersion framework the air model approximates in '
          'the near field.'),
];

/// Why a parameter carries no external citation. These are the markers the
/// params file already uses; they are reported, not hidden.
enum Internal {
  design('Design decision',
      'Chosen for the game and reasoned against the other tiles, with no '
          'single external figure to cite.'),
  derived('Derived from cited figures',
      'Arithmetic on numbers that are themselves cited above.'),
  calibration('Calibrated (T-114)',
      'Set so that a described situation produces a described score; the '
          'calibration run is documented in calibration.md.'),
  estimate('Initial estimate',
      'A placeholder awaiting verification (task T-103).'),
  reasoned('Reasoned, no external source',
      'A short justification in place of a citation, usually because the '
          'parameter is structural.'),
  notApplicable('Not applicable',
      'The parameter does not apply to this tile, so there is nothing to '
          'cite.');

  const Internal(this.label, this.what);
  final String label;
  final String what;
}

class ParamSource {
  ParamSource(this.path, this.text, this.authority, this.internal,
      {required this.provisional});
  final String path;
  final String text;
  final Authority? authority;
  final Internal? internal;
  final bool provisional;
}

class SourceIndex {
  SourceIndex(this.entries, this.docReferences);
  final List<ParamSource> entries;

  /// Doc path -> the bullet lines of its `## References` section. Prose cites
  /// things no parameter mentions (a directive, a 2000 paper), so the page
  /// carries those too.
  final Map<String, List<String>> docReferences;

  static SourceIndex read() {
    final entries = <ParamSource>[];
    final files = Directory('data/params')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    if (files.isEmpty) _die('no parameter files in data/params');
    for (final f in files) {
      final json = jsonDecode(f.readAsStringSync());
      _walk(json, '', entries);
    }
    if (entries.isEmpty) _die('no `source` fields found in data/params');

    final refs = <String, List<String>>{};
    for (final p in _pages) {
      final lines = MarkdownDoc.parse(p.source).lines;
      var inRefs = false;
      final bullets = <String>[];
      for (final l in lines) {
        if (RegExp(r'^#{1,3} +References').hasMatch(l)) {
          inRefs = true;
          continue;
        }
        if (inRefs && l.startsWith('#')) break;
        if (!inRefs) continue;
        if (l.startsWith('- ')) {
          bullets.add(l.substring(2).trim());
        } else if (l.startsWith('  ') && bullets.isNotEmpty) {
          bullets[bullets.length - 1] += ' ${l.trim()}';
        }
      }
      if (bullets.isNotEmpty) refs[p.source] = bullets;
    }
    return SourceIndex(entries, refs);
  }

  static void _walk(Object? node, String path, List<ParamSource> out) {
    if (node is Map) {
      for (final e in node.entries) {
        final key = e.key as String;
        if (key == 'source') {
          if (e.value is! String) _die('non-string source at $path');
          out.add(_classify(path, e.value as String));
        } else {
          _walk(e.value, path.isEmpty ? key : '$path.$key', out);
        }
      }
    } else if (node is List) {
      for (var i = 0; i < node.length; i++) {
        _walk(node[i], '$path[$i]', out);
      }
    }
  }

  static ParamSource _classify(String path, String text) {
    final provisional = text.contains('initial estimate');
    // An authority anywhere in the string wins: "design, anchored on MiD 2017"
    // does rest on MiD 2017, and saying so is more honest than filing it as a
    // bare design decision. The design/estimate markers are kept alongside.
    for (final a in _authorities) {
      if (RegExp(a.pattern).hasMatch(text)) {
        return ParamSource(path, text, a, null, provisional: provisional);
      }
    }
    final lower = text.toLowerCase();
    Internal internal;
    if (lower == 'n/a' ||
        lower.startsWith('n/a:') ||
        lower == 'no source' ||
        lower.startsWith('no night emission') ||
        lower == 'neutral in v1' ||
        lower.startsWith('traffic co2 is computed')) {
      internal = Internal.notApplicable;
    } else if (lower.startsWith('derived')) {
      internal = Internal.derived;
    } else if (lower.startsWith('calibration')) {
      internal = Internal.calibration;
    } else if (lower == 'design' ||
        lower.startsWith('design:') ||
        lower.startsWith('design,') ||
        lower.startsWith('design;') ||
        lower == 'convention') {
      internal = Internal.design;
    } else if (lower == 'initial estimate') {
      internal = Internal.estimate;
    } else {
      internal = provisional ? Internal.estimate : Internal.reasoned;
    }
    return ParamSource(path, text, null, internal, provisional: provisional);
  }

  List<ParamSource> get cited =>
      entries.where((e) => e.authority != null).toList();

  String coverageSentence() {
    final n = cited.length;
    final total = entries.length;
    final pct = (100 * n / total).round();
    final firm = cited.where((e) => !e.provisional).length;
    return 'Of the $total parameters in <code>data/params/</code>, $n ($pct %) '
        'cite a law, standard, dataset or paper; $firm of those are settled '
        'figures and ${n - firm} are still marked as initial estimates. The '
        'rest are design decisions, derivations or calibrations, each with its '
        'reasoning recorded in the same field.';
  }

  String renderPage() {
    final b = StringBuffer();
    b.writeln('<h1>Quellen</h1>');
    b.writeln('<p class="lead">Every law, standard, dataset and paper the '
        'simulation rests on, and the parameters that cite each one. This page '
        'is generated from the <code>source</code> field that '
        '<code>data/params/tiles.json</code> carries on every number, plus the '
        'References sections of the model documentation, so it cannot drift '
        'away from what the code actually reads.</p>');
    b.writeln('<p>${coverageSentence()}</p>');

    // Grouped by authority, most-cited first.
    final byAuthority = <String, List<ParamSource>>{};
    for (final e in cited) {
      (byAuthority[e.authority!.id] ??= []).add(e);
    }
    final ordered = _authorities.where((a) => byAuthority.containsKey(a.id)).toList()
      ..sort((a, b) =>
          byAuthority[b.id]!.length.compareTo(byAuthority[a.id]!.length));

    b.writeln('<h2 id="datasets"><a class="anchor" href="#datasets">Laws, '
        'standards and datasets</a></h2>');
    b.writeln('<div class="tablewrap"><table>\n<thead><tr>'
        '<th>Source</th><th>What it is</th><th>Parameters</th>'
        '</tr></thead>\n<tbody>');
    for (final a in ordered) {
      b.writeln('<tr><td><a href="#src-${a.id}">${esc(a.name)}</a></td>'
          '<td>${esc(a.what)}</td>'
          '<td class="num">${byAuthority[a.id]!.length}</td></tr>');
    }
    b.writeln('</tbody></table></div>');

    for (final a in ordered) {
      final group = byAuthority[a.id]!;
      b.writeln('<h3 id="src-${a.id}"><a class="anchor" href="#src-${a.id}">'
          '${esc(a.name)}</a></h3>');
      b.writeln('<p>${esc(a.what)}</p>');
      final byText = <String, List<ParamSource>>{};
      for (final e in group) {
        (byText[e.text] ??= []).add(e);
      }
      final texts = byText.keys.toList()..sort();
      b.writeln('<details><summary>${group.length} parameters, '
          '${texts.length} distinct citations</summary><ul class="cites">');
      for (final t in texts) {
        final ps = byText[t]!;
        final tags = <String>[
          if (ps.first.provisional) '<span class="tag est">initial estimate</span>',
          if (t.toLowerCase().startsWith('design'))
            '<span class="tag des">design, anchored on this source</span>',
        ].join(' ');
        b.writeln('<li><span class="cite">${esc(t)}</span> $tags'
            '<br><span class="paths">${ps.map((p) => '<code>${esc(p.path)}</code>').join(', ')}</span></li>');
      }
      b.writeln('</ul></details>');
    }

    // Prose citations from the docs.
    b.writeln('<h2 id="in-docs"><a class="anchor" href="#in-docs">Cited in the '
        'model documentation</a></h2>');
    b.writeln('<p>The References section of each model page, collected. These '
        'include works the prose relies on for a formula rather than for a '
        'single number.</p>');
    for (final e in docReferences.entries) {
      final doc = MarkdownDoc.parse(e.key);
      final page = _pages.firstWhere((p) => p.source == e.key);
      b.writeln('<h3>${esc(doc.title)} '
          '<a class="seealso" href="${page.output}">read the page</a></h3><ul>');
      for (final bullet in e.value) {
        b.writeln('<li>${_inline(bullet, 0, {
              for (final p in _pages) p.source: p.output,
            }, e.key)}</li>');
      }
      b.writeln('</ul>');
    }

    // Everything without an external citation, by reason.
    b.writeln('<h2 id="no-source"><a class="anchor" href="#no-source">'
        'Parameters without an external source</a></h2>');
    b.writeln('<p>Not every number in a game can be looked up, and pretending '
        'otherwise would be the more dishonest option. These carry a stated '
        'reason instead of a citation.</p>');
    final byInternal = <Internal, List<ParamSource>>{};
    for (final e in entries.where((e) => e.internal != null)) {
      (byInternal[e.internal!] ??= []).add(e);
    }
    b.writeln('<div class="tablewrap"><table>\n<thead><tr><th>Reason</th>'
        '<th>What it means</th><th>Parameters</th></tr></thead>\n<tbody>');
    for (final k in Internal.values.where(byInternal.containsKey)) {
      b.writeln('<tr><td>${esc(k.label)}</td><td>${esc(k.what)}</td>'
          '<td class="num">${byInternal[k]!.length}</td></tr>');
    }
    b.writeln('</tbody></table></div>');
    for (final k in Internal.values.where(byInternal.containsKey)) {
      final group = byInternal[k]!..sort((a, b) => a.path.compareTo(b.path));
      b.writeln('<details><summary>${esc(k.label)} '
          '(${group.length})</summary><ul class="cites">');
      for (final e in group) {
        b.writeln('<li><code>${esc(e.path)}</code> — '
            '<span class="cite">${esc(e.text)}</span></li>');
      }
      b.writeln('</ul></details>');
    }

    final counted = cited.length + byInternal.values.fold(0, (a, b) => a + b.length);
    if (counted != entries.length) {
      _die('Quellen page accounts for $counted of ${entries.length} '
          'parameters; every one must appear exactly once.');
    }
    return b.toString();
  }
}

// ---------------------------------------------------------------------------

const _css = r'''
/* SPDX-License-Identifier: AGPL-3.0-or-later
   Served from our own origin: no webfont, no script, no third-party request
   (see docs/privacy.md). Formulas are typeset with the system serif. */
:root {
  --bg: #fbfaf7;
  --panel: #f2efe8;
  --ink: #23201c;
  --dim: #6a6358;
  --rule: #ddd7cb;
  --link: #1f5f3f;
  --accent: #8a5a2b;
  --code: #efece3;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #1a1916;
    --panel: #221f1b;
    --ink: #e8e4db;
    --dim: #a19a8c;
    --rule: #3a352d;
    --link: #8fd0a8;
    --accent: #d9a86a;
    --code: #262320;
  }
}
* { box-sizing: border-box; }
body {
  margin: 0;
  background: var(--bg);
  color: var(--ink);
  font: 16px/1.62 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
  display: grid;
  grid-template-columns: 17rem 1fr;
  min-height: 100vh;
}
a { color: var(--link); }
.skip {
  position: absolute; left: -9999px; top: 0; padding: .5rem 1rem;
  background: var(--panel);
}
.skip:focus { left: 0; z-index: 5; }
nav {
  background: var(--panel);
  border-right: 1px solid var(--rule);
  padding: 1.6rem 1.2rem 2rem;
  font-size: .94rem;
}
nav .brand { margin: 0 0 1.4rem; line-height: 1.3; }
nav .brand a {
  display: block; font-size: 1.22rem; font-weight: 650;
  text-decoration: none; color: var(--ink); letter-spacing: -.01em;
}
nav .brand span { color: var(--dim); font-size: .82rem; }
nav h2 {
  font-size: .72rem; text-transform: uppercase; letter-spacing: .08em;
  color: var(--dim); margin: 1.4rem 0 .4rem; font-weight: 600;
}
nav ul { list-style: none; margin: 0; padding: 0; }
nav li { margin: .1rem 0; }
nav li a {
  display: block; padding: .2rem .5rem; border-radius: 4px;
  text-decoration: none; border-left: 2px solid transparent;
}
nav li a:hover { background: var(--bg); }
nav li.here a {
  background: var(--bg); border-left-color: var(--accent);
  color: var(--ink); font-weight: 600;
}
nav .back { margin-top: 2rem; font-size: .88rem; }
main {
  padding: 2.6rem clamp(1.2rem, 4vw, 3.4rem) 4rem;
  max-width: 54rem;
  min-width: 0;
}
h1 { font-size: 2rem; line-height: 1.2; letter-spacing: -.02em; margin: 0 0 1rem; }
h2 { font-size: 1.32rem; margin: 2.4rem 0 .6rem; letter-spacing: -.01em; }
h3 { font-size: 1.08rem; margin: 1.8rem 0 .4rem; }
h4 { font-size: .98rem; margin: 1.4rem 0 .3rem; color: var(--dim); }
h2, h3 { border-bottom: 1px solid var(--rule); padding-bottom: .3rem; }
a.anchor { color: inherit; text-decoration: none; }
a.anchor:hover::after {
  content: " #"; color: var(--accent); font-weight: 400;
}
p.lead { font-size: 1.1rem; color: var(--ink); }
code {
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  font-size: .88em; background: var(--code); padding: .08em .2em;
  border-radius: 3px;
}
pre {
  background: var(--code); border: 1px solid var(--rule); border-radius: 6px;
  padding: .9rem 1.1rem; overflow-x: auto; line-height: 1.5;
}
pre code { background: none; padding: 0; }
/* Formulas: the docs write them as backticked text, so they are typeset
   rather than rendered -- no maths engine, no external request. */
p.formula { text-align: center; margin: 1.3rem 0; }
p.formula code, pre.formula-block {
  font-family: "Iowan Old Style", "Palatino Linotype", Palatino, Georgia, serif;
  font-size: 1.06rem; font-style: italic; letter-spacing: .01em;
}
p.formula code {
  background: none; border-left: 3px solid var(--accent); padding: .1rem 0 .1rem .8rem;
}
pre.formula-block { font-style: normal; background: var(--panel); }
.tablewrap { overflow-x: auto; margin: 1.1rem 0; }
table { border-collapse: collapse; width: 100%; font-size: .93rem; }
th, td {
  text-align: left; padding: .45rem .7rem; border-bottom: 1px solid var(--rule);
  vertical-align: top;
}
th { font-weight: 620; color: var(--dim); font-size: .82rem;
     text-transform: uppercase; letter-spacing: .04em; }
td.num, th:last-child { white-space: nowrap; }
td.num { text-align: right; font-variant-numeric: tabular-nums; }
tbody tr:hover { background: var(--panel); }
blockquote {
  margin: 1.2rem 0; padding: .1rem 0 .1rem 1rem;
  border-left: 3px solid var(--accent); color: var(--dim);
}
blockquote p { margin: .3rem 0; }
ul.cards { list-style: none; padding: 0; display: grid; gap: .6rem;
           grid-template-columns: repeat(auto-fill, minmax(15rem, 1fr)); }
ul.cards a {
  display: block; padding: .7rem .9rem; background: var(--panel);
  border: 1px solid var(--rule); border-radius: 6px; text-decoration: none;
  color: var(--ink); height: 100%;
}
ul.cards a:hover { border-color: var(--accent); }
ul.cards code { display: block; margin-top: .25rem; background: none;
                padding: 0; color: var(--dim); font-size: .78em;
                overflow-wrap: anywhere; }
details { margin: .6rem 0 1.2rem; }
summary {
  cursor: pointer; color: var(--link); font-size: .93rem; padding: .2rem 0;
}
ul.cites { font-size: .92rem; }
ul.cites li { margin: .5rem 0; }
.cite { color: var(--ink); }
.paths { color: var(--dim); font-size: .85em; }
.paths code { background: none; padding: 0; }
.tag {
  display: inline-block; font-size: .74rem; padding: .05rem .4rem;
  border-radius: 3px; border: 1px solid var(--rule); color: var(--dim);
  white-space: nowrap;
}
.tag.est { border-color: var(--accent); color: var(--accent); }
a.seealso { font-size: .82rem; font-weight: 400; }
p.src, p.lic {
  color: var(--dim); font-size: .85rem; border-top: 1px solid var(--rule);
  padding-top: .8rem; margin-top: 2.4rem;
}
p.lic { border-top: none; margin-top: .6rem; padding-top: 0; }
@media (max-width: 52rem) {
  body { grid-template-columns: 1fr; }
  nav { border-right: none; border-bottom: 1px solid var(--rule);
        padding-bottom: 1rem; }
  nav h2 { margin-top: .9rem; }
  main { padding-top: 1.6rem; }
}
''';
