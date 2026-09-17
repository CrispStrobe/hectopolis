// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// A data source the simulation model is built on, shown on the About screen
/// and registered on the license page. Keep in sync with `PLAN.md` §8.
class DataSource {
  const DataSource(this.title, this.license, this.url);

  final String title;
  final String license;
  final String url;
}

const dataSources = <DataSource>[
  DataSource('Bundeskompensationsverordnung (BKompV) Anlage 2, Biotopwerte', 'Bundesrecht, gemeinfrei (§ 5 UrhG)',
      'https://www.gesetze-im-internet.de/bkompv/anlage_2.html'),
  DataSource('InVEST User Guide (Natural Capital Project): Urban Cooling, Habitat Quality', 'Apache-2.0',
      'https://storage.googleapis.com/releases.naturalcapitalproject.org/invest-userguide/latest/en/index.html'),
  DataSource('CNOSSOS-EU, Richtlinie (EU) 2015/996 Anhang II; TA Lärm', 'EU-Recht / Verwaltungsvorschrift',
      'https://eur-lex.europa.eu/eli/dir/2015/996/oj'),
  DataSource('EMEP/EEA air pollutant emission inventory guidebook', 'EEA, freie Weiterverwendung mit Quellenangabe',
      'https://www.eea.europa.eu/publications/emep-eea-guidebook-2023'),
  DataSource('Nowak, Crane, Stevens (2006): Air pollution removal by urban trees', 'Wissenschaftliche Veröffentlichung (nur Werte)',
      'https://doi.org/10.1016/j.ufug.2006.01.007'),
  DataSource('Mobilität in Deutschland 2017 (BMVI / infas)', 'Öffentlicher Ergebnisbericht',
      'https://www.mobilitaet-in-deutschland.de/'),
  DataSource('Statistisches Bundesamt (Destatis): Wohnfläche, Erwerbstätige, kommunale Finanzen', 'dl-de/by-2.0',
      'https://www.destatis.de/'),
  DataSource('Zensus 2022, 100-m-Gitter', 'dl-de/by-2.0', 'https://www.zensus2022.de/'),
  DataSource('BauNVO § 17 (Obergrenzen GRZ/GFZ)', 'Bundesrecht, gemeinfrei (§ 5 UrhG)',
      'https://www.gesetze-im-internet.de/baunvo/__17.html'),
  DataSource('WHO Regional Office for Europe (2016): Urban green spaces and health; 3-30-300 rule (Konijnendijk 2021)',
      'Öffentliche Berichte (nur Werte)', 'https://www.who.int/europe/'),
  DataSource('Huff (1963): A probabilistic analysis of shopping center trade areas', 'Wissenschaftliche Methode',
      'https://doi.org/10.2307/3144521'),
  DataSource('Jaeger (2000): Landscape division, splitting index, and effective mesh size', 'Wissenschaftliche Methode',
      'https://doi.org/10.1023/A:1008129329289'),
  DataSource('HDE Zahlenspiegel (Verkaufsfläche je Einwohner); BBSR Nahversorgung', 'Öffentliche Berichte (nur Werte)',
      'https://einzelhandel.de/'),
  // Used by the level generator (T-303) and therefore shipped inside the
  // `tuebingen` level. CC BY 4.0 obliges us to carry the source notice and to
  // say that the data was changed; the level's own `attribution` field does
  // that where the level is played, and this is the same notice on the About
  // screen. The complete, generated list of everything the model cites is the
  // Quellen page linked above.
  DataSource('Landbedeckungsmodell LBM-DE2021 (BKG)',
      'CC BY 4.0 — © BKG (2026), bearbeitet: 1-ha-Raster, 16 Kachelarten', 'https://gdz.bkg.bund.de/'),
  DataSource('KOSTRA-DWD-2020 (Deutscher Wetterdienst), design rainfall', 'DWD, free re-use with attribution',
      'https://doi.org/10.5676/DWD/KOSTRA-DWD-2020'),
  DataSource('Copernicus Imperviousness (HRL), sealed share per land cover', 'Copernicus, free with attribution',
      'https://land.copernicus.eu/'),
  DataSource('Material Symbols (Google)', 'Apache-2.0', 'https://fonts.google.com/icons'),
  DataSource('Roboto (Google), bundled so that no text is fetched from a third party at runtime', 'Apache-2.0',
      'https://fonts.google.com/specimen/Roboto'),
];

bool _registered = false;

/// Register the app's own license (AGPL-3.0-or-later plus the app-store
/// exception) and the data-source attributions with Flutter's
/// `LicenseRegistry`, so `showLicensePage` lists them next to the pub packages.
/// Idempotent.
void ensureCustomLicensesRegistered() {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(() async* {
    try {
      final agpl = await rootBundle.loadString('assets/licenses/AGPL-3.0.txt');
      final exception = await rootBundle.loadString('assets/licenses/APP-STORE-EXCEPTION.md');
      yield LicenseEntryWithLineBreaks(const ['Hectopolis'], '$exception\n\n$agpl');
      // Apache-2.0 requires the licence to travel with the binaries, and the
      // Roboto files are redistributed inside the app.
      final roboto = await rootBundle.loadString('assets/licenses/Roboto-Apache-2.0.txt');
      yield LicenseEntryWithLineBreaks(const ['Roboto'], roboto);
    } on Object catch (e) {
      debugPrint('custom_licenses: could not load bundled license texts: $e');
    }
    final buffer = StringBuffer('The simulation model is built on the following public sources. '
        'Only values, formulas and law texts are used; no protected text, artwork or data tables are copied.\n\n');
    for (final s in dataSources) {
      buffer.writeln('${s.title}\n  ${s.license}\n  ${s.url}\n');
    }
    yield LicenseEntryWithLineBreaks(const ['Hectopolis model data sources'], buffer.toString());
  });
}
