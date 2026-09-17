// SPDX-License-Identifier: AGPL-3.0-or-later

/// Coarse land-use category of a tile type.
enum TileCategory {
  nature('nature'),
  greenUrban('green_urban'),
  residential('residential'),
  work('work'),
  infrastructure('infrastructure');

  const TileCategory(this.id);

  /// Stable identifier used in `data/params/tiles.json`.
  final String id;

  static TileCategory fromId(String id) =>
      values.firstWhere((c) => c.id == id, orElse: () => throw ArgumentError('Unknown category $id'));

  /// Nature and urban green count as habitat and as recreational green.
  bool get isGreen => this == nature || this == greenUrban;

  /// Built tiles cost demolition money to remove.
  bool get isBuilt => this == residential || this == work || this == infrastructure;
}

/// The tile types of the model. Ids match `data/params/tiles.json` and the ARB
/// keys `tile_<id>` in the app.
///
/// Order is palette order, so related tiles sit together: nature, then urban
/// green, then places people live and work, then the ways they move.
enum TileType {
  meadow('meadow'),
  cropland('cropland'),
  forest('forest'),
  water('water'),
  wetland('wetland'),
  park('park'),
  housingLow('housing_low'),
  housingHigh('housing_high'),
  mixedUse('mixed_use'),
  commercial('commercial'),
  industry('industry'),
  school('school'),
  solarField('solar_field'),
  road('road'),
  tramStop('tram_stop'),
  cyclePath('cycle_path');

  const TileType(this.id);

  /// Stable identifier used in params, levels, save games and network messages.
  final String id;

  static final Map<String, TileType> _byId = {for (final t in values) t.id: t};

  static TileType fromId(String id) {
    final t = _byId[id];
    if (t == null) throw ArgumentError('Unknown tile type $id');
    return t;
  }

  /// The base terrain a removed tile reverts to.
  static const TileType terrain = TileType.meadow;
}
