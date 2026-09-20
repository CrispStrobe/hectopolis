// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:stadtbau_sim/stadtbau_sim.dart';

import '../l10n/generated/app_localizations.dart';

/// What to call a tile type in this level (T-502).
///
/// A level may declare that one of its tile types stands for a named
/// sub-type -- that `housing_low` here is terraced houses rather than the
/// middle of the class. The parameters then come from that sub-type, and the
/// name has to follow them: a panel that says "Detached housing" over the
/// numbers for a Gründerzeit block is worse than no sub-type at all, because
/// the player has no way to tell.
///
/// [level] may be null (the sandbox), and a level that names no sub-type for
/// this type falls through to the class name.
String tileDisplayName(AppLocalizations l10n, Level? level, TileType type) {
  final subtype = level?.subtypes[type.id];
  return subtype == null
      ? l10n.tileName(type.id)
      : l10n.tileSubtypeName(subtype);
}

/// The one-line description of a tile type in this level, following the same
/// rule as [tileDisplayName].
String tileDisplayDescription(
  AppLocalizations l10n,
  Level? level,
  TileType type,
) {
  final subtype = level?.subtypes[type.id];
  return subtype == null
      ? l10n.tileDescription(type.id)
      : l10n.tileSubtypeDescription(subtype);
}
