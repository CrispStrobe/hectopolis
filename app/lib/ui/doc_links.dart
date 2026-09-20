// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:stadtbau_sim/stadtbau_sim.dart';

/// Where the documentation the app links to actually lives (T-703).
///
/// Three screens used to carry their own copy of a
/// `github.com/CrispStrobe/stadtbau/blob/main/docs/model/...` URL. That repository
/// has since been renamed, so those links only resolved through GitHub's
/// rename redirect and showed raw markdown when they did. The docs are now
/// rendered by `tools/build_docs_site.dart` and deployed beside the game, so
/// there is one base URL and one place to change it.
const docsSiteUrl = 'https://crispstrobe.github.io/hectopolis/docs/';

/// The repository itself, for the About screen.
const repositoryUrl = 'https://github.com/CrispStrobe/hectopolis';

/// The model overview: one page per component.
const modelDocsUrl = '${docsSiteUrl}model/';

/// The generated list of every law, standard and dataset the model uses.
const sourcesDocUrl = '${docsSiteUrl}quellen.html';

/// The page of the model documentation that explains each indicator.
const indicatorDocPage = <Indicator, String>{
  Indicator.biodiversity: 'biodiversity.html',
  Indicator.air: 'air.html',
  Indicator.noise: 'noise.html',
  Indicator.housing: 'economy.html',
  Indicator.economy: 'economy.html',
  Indicator.shopping: 'access.html',
  Indicator.recreation: 'access.html',
  Indicator.commuting: 'commute.html',
  Indicator.climate: 'heat.html',
  Indicator.flood: 'water.html',
  Indicator.budget: 'economy.html',
};

/// The documentation URL for [indicator].
String indicatorDocUrl(Indicator indicator) =>
    '$modelDocsUrl${indicatorDocPage[indicator]!}';
