// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'generated/default_params.dart';
import 'tile_type.dart';

/// A single sourced number from `data/params/tiles.json`.
class Param {
  const Param(this.value, this.source, [this.note]);

  final double value;
  final String source;
  final String? note;

  static Param fromJson(Object? json, String path) {
    if (json is Map<String, dynamic>) {
      final v = json['value'];
      if (v is! num) throw FormatException('$path.value must be a number');
      final s = json['source'];
      return Param(v.toDouble(), s is String ? s : '', json['note'] as String?);
    }
    if (json is num) return Param(json.toDouble(), '');
    throw FormatException('$path must be {value, source}');
  }
}

Map<String, dynamic> _map(Object? json, String path) {
  if (json is Map<String, dynamic>) return json;
  throw FormatException('$path must be an object');
}

Param _p(Map<String, dynamic> m, String key, String path, [double? fallback]) {
  final v = m[key];
  if (v == null) {
    if (fallback != null) return Param(fallback, 'default');
    throw FormatException('missing $path.$key');
  }
  return Param.fromJson(v, '$path.$key');
}

/// Per-tile-type coefficients. All "per ha" values refer to one grid cell.
class TileParams {
  TileParams({
    required this.type,
    required this.category,
    required this.residentsPerHa,
    required this.jobsPerHa,
    required this.sealing,
    required this.biotopeValue,
    required this.biotopeStart,
    required this.recoveryMonths,
    required this.noiseEmissionDb,
    required this.noiseNightReductionDb,
    required this.perviousCurveNumber,
    required this.airEmission,
    required this.airSink,
    required this.shade,
    required this.albedo,
    required this.eti,
    required this.greenWeight,
    required this.co2PerHaYear,
    required this.buildCostKEur,
    required this.maintenanceKEurYear,
    required this.retailFloorM2,
  });

  final TileType type;
  final TileCategory category;
  final Param residentsPerHa;
  final Param jobsPerHa;
  final Param sealing;

  /// BKompV Anlage 2 biotope value, 0–24.
  final Param biotopeValue;

  /// Fraction of [biotopeValue] a freshly placed tile starts with.
  final Param biotopeStart;

  /// Months until the tile reaches its full biotope value.
  final Param recoveryMonths;

  /// L_eq in dB(A) at the reference distance; 0 = silent.
  final Param noiseEmissionDb;

  /// How much quieter this tile is between 22:00 and 06:00.
  final Param noiseNightReductionDb;

  /// SCS runoff curve number of the tile's *unsealed* part. The sealed part is
  /// [sealing], and the two compose by TR-55 (docs/model/water.md).
  final Param perviousCurveNumber;
  final Param airEmission;
  final Param airSink;
  final Param shade;
  final Param albedo;
  final Param eti;
  final Param greenWeight;
  final Param co2PerHaYear;
  final Param buildCostKEur;
  final Param maintenanceKEurYear;
  final Param retailFloorM2;

  bool get isResidential => category == TileCategory.residential;
  bool get isHabitat => category.isGreen;

  static TileParams fromJson(TileType type, Map<String, dynamic> m) {
    final path = 'tiles.${type.id}';
    return TileParams(
      type: type,
      category: TileCategory.fromId(m['category'] as String? ?? ''),
      residentsPerHa: _p(m, 'residentsPerHa', path),
      jobsPerHa: _p(m, 'jobsPerHa', path),
      sealing: _p(m, 'sealing', path),
      biotopeValue: _p(m, 'biotopeValue', path),
      biotopeStart: _p(m, 'biotopeStart', path, 1),
      recoveryMonths: _p(m, 'recoveryMonths', path, 1),
      noiseEmissionDb: _p(m, 'noiseEmissionDb', path, 0),
      noiseNightReductionDb: _p(m, 'noiseNightReductionDb', path, 0),
      perviousCurveNumber: _p(m, 'perviousCurveNumber', path, 61),
      airEmission: _p(m, 'airEmission', path, 0),
      airSink: _p(m, 'airSink', path, 0),
      shade: _p(m, 'shade', path),
      albedo: _p(m, 'albedo', path),
      eti: _p(m, 'eti', path),
      greenWeight: _p(m, 'greenWeight', path, 0),
      co2PerHaYear: _p(m, 'co2PerHaYear', path, 0),
      buildCostKEur: _p(m, 'buildCostKEur', path),
      maintenanceKEurYear: _p(m, 'maintenanceKEurYear', path, 0),
      retailFloorM2: _p(m, 'retailFloorM2', path, 0),
    );
  }
}

class NoiseParams {
  NoiseParams(Map<String, dynamic> m)
      : areaReferenceDistanceM = _p(m, 'areaReferenceDistanceM', 'noise').value,
        areaDecayDbPerDecade = _p(m, 'areaDecayDbPerDecade', 'noise').value,
        foliageAttenuationDbPerTile = _p(m, 'foliageAttenuationDbPerTile', 'noise').value,
        buildingScreeningDbPerTile = _p(m, 'buildingScreeningDbPerTile', 'noise').value,
        maxPathAttenuationDb = _p(m, 'maxPathAttenuationDb', 'noise').value,
        backgroundDb = _p(m, 'backgroundDb', 'noise').value,
        radiusTiles = _p(m, 'radiusTiles', 'noise').value.round(),
        trafficReferenceVehiclesPerDay = _p(m, 'trafficReferenceVehiclesPerDay', 'noise').value,
        baselineThroughTraffic = _p(m, 'baselineThroughTraffic', 'noise').value,
        limitDayDb = _p(m, 'limitDayDb', 'noise').value,
        limitBadDb = _p(m, 'limitBadDb', 'noise').value,
        nightGuidelineDb = _p(m, 'nightGuidelineDb', 'noise').value,
        nightLoaelDb = _p(m, 'nightLoaelDb', 'noise').value,
        nightHighRiskDb = _p(m, 'nightHighRiskDb', 'noise').value;

  final double areaReferenceDistanceM;
  final double areaDecayDbPerDecade;
  final double foliageAttenuationDbPerTile;
  final double buildingScreeningDbPerTile;
  final double maxPathAttenuationDb;
  final double backgroundDb;
  final int radiusTiles;
  final double trafficReferenceVehiclesPerDay;
  final double baselineThroughTraffic;
  final double limitDayDb;
  final double limitBadDb;

  /// WHO 2018 road-traffic night recommendation, dB L_night.
  final double nightGuidelineDb;

  /// WHO 2009 night guideline and lowest observed adverse effect level.
  final double nightLoaelDb;

  /// WHO 2009 interim target, above which cardiovascular effects dominate.
  final double nightHighRiskDb;
}

/// Rainfall and runoff (docs/model/water.md).
class WaterParams {
  WaterParams(Map<String, dynamic> m)
    : designStormMm = _p(m, 'designStormMm', 'water').value,
      imperviousCurveNumber = _p(m, 'imperviousCurveNumber', 'water').value,
      initialAbstractionRatio = _p(m, 'initialAbstractionRatio', 'water').value,
      retentionRadiusTiles = _p(
        m,
        'retentionRadiusTiles',
        'water',
      ).value.round(),
      retentionMmPerCell = _p(m, 'retentionMmPerCell', 'water').value,
      floodRiskMm = _p(m, 'floodRiskMm', 'water').value;

  /// Rain depth of the design storm, mm.
  final double designStormMm;

  /// Curve number of connected impervious area.
  final double imperviousCurveNumber;

  /// Initial abstraction as a fraction of the maximum retention S.
  final double initialAbstractionRatio;

  final int retentionRadiusTiles;

  /// Depth one water cell can take from its neighbourhood, mm.
  final double retentionMmPerCell;

  /// Runoff depth above which a cell is reported as at risk, mm.
  final double floodRiskMm;
}

/// The yearly cycle (docs/model/seasons.md).
///
/// Both factor series average exactly 1.0 over the twelve months, so a season
/// redistributes within a year rather than shifting the annual total: a run
/// measured over whole years lands where it did before seasons existed.
class SeasonParams {
  SeasonParams(Map<String, dynamic> m)
    : amplitude = _p(m, 'amplitude', 'seasons').value,
      growth = _monthly(m, 'growth'),
      heat = _monthly(m, 'heat');

  static List<double> _monthly(Map<String, dynamic> m, String key) {
    final section = _map(m[key], 'seasons.$key');
    final values = (section['monthly'] as List<dynamic>? ?? const [])
        .map((v) => (v as num).toDouble())
        .toList();
    if (values.length != 12) {
      throw FormatException('seasons.$key.monthly needs 12 values');
    }
    return List.unmodifiable(values);
  }

  /// 0 disables the cycle and reproduces the season-free model exactly.
  final double amplitude;

  /// Vegetation activity by month, index 0 = January.
  final List<double> growth;

  /// Urban heat island intensity by month.
  final List<double> heat;

  bool get active => amplitude > 0;

  double _at(List<double> monthly, int tick) {
    final factor = monthly[((tick % 12) + 12) % 12];
    // Amplitude scales the departure from the annual mean, so turning it down
    // flattens the year towards 1.0 rather than towards zero.
    return 1 + (factor - 1) * amplitude;
  }

  /// Vegetation activity for the month at [tick], where tick 0 is January.
  double growthAt(int tick) => _at(growth, tick);

  /// Heat island intensity for the month at [tick].
  double heatAt(int tick) => _at(heat, tick);
}

class AirParams {
  AirParams(Map<String, dynamic> m)
      : decayLengthM = _p(m, 'decayLengthM', 'air').value,
        radiusTiles = _p(m, 'radiusTiles', 'air').value.round(),
        sinkRadiusTiles = _p(m, 'sinkRadiusTiles', 'air').value.round(),
        indexScale = _p(m, 'indexScale', 'air').value,
        trafficReferenceVehiclesPerDay = _p(m, 'trafficReferenceVehiclesPerDay', 'air').value,
        windFromDegrees = _p(m, 'windFromDegrees', 'air').value,
        windSpeedMs = _p(m, 'windSpeedMs', 'air').value,
        windStretchPerMs = _p(m, 'windStretchPerMs', 'air').value;

  final double decayLengthM;
  final int radiusTiles;
  final int sinkRadiusTiles;
  final double indexScale;
  final double trafficReferenceVehiclesPerDay;

  /// Where the wind comes from, meteorological convention: 0 = north,
  /// 90 = east. Only matters when [windSpeedMs] is above zero.
  final double windFromDegrees;

  /// Mean wind speed. Zero is calm, and calm is exactly the isotropic model.
  final double windSpeedMs;

  /// How much a metre per second stretches the plume downwind.
  final double windStretchPerMs;

  /// How far the plume reaches downwind relative to calm: 1 is calm.
  double get windStretch => 1 + windSpeedMs * windStretchPerMs;

  bool get hasWind => windSpeedMs > 0 && windStretch > 1;
}

class HeatParams {
  HeatParams(Map<String, dynamic> m)
      : shadeWeight = _p(m, 'shadeWeight', 'heat').value,
        albedoWeight = _p(m, 'albedoWeight', 'heat').value,
        etiWeight = _p(m, 'etiWeight', 'heat').value,
        uhiMaxC = _p(m, 'uhiMaxC', 'heat').value,
        greenPatchMinHa = _p(m, 'greenPatchMinHa', 'heat').value,
        coolingDistanceTiles = _p(m, 'coolingDistanceTiles', 'heat').value.round();

  final double shadeWeight;
  final double albedoWeight;
  final double etiWeight;
  final double uhiMaxC;
  final double greenPatchMinHa;
  final int coolingDistanceTiles;
}

class AccessParams {
  AccessParams(Map<String, dynamic> m)
      : greenRadiusTiles = _p(m, 'greenRadiusTiles', 'access').value.round(),
        greenVarietyBonus = _p(m, 'greenVarietyBonus', 'access').value,
        greenVarietyMinTiles = _p(m, 'greenVarietyMinTiles', 'access').value.round(),
        retailRadiusTiles = _p(m, 'retailRadiusTiles', 'access').value.round(),
        huffLambda = _p(m, 'huffLambda', 'access').value,
        retailM2PerResident = _p(m, 'retailM2PerResident', 'access').value,
        retailReferenceSupply = _p(m, 'retailReferenceSupply', 'access').value,
        jobDecayM = _p(m, 'jobDecayM', 'access').value,
        jobReferenceJobs = _p(m, 'jobReferenceJobs', 'access', 400).value;

  final int greenRadiusTiles;
  final double greenVarietyBonus;
  final int greenVarietyMinTiles;
  final int retailRadiusTiles;
  final double huffLambda;
  final double retailM2PerResident;
  final double retailReferenceSupply;
  final double jobDecayM;
  final double jobReferenceJobs;
}

class ThreatParams {
  const ThreatParams(this.weight, this.maxDistanceM);
  final double weight;
  final double maxDistanceM;
}

class HabitatParams {
  HabitatParams(Map<String, dynamic> m)
      : halfSaturation = _p(m, 'halfSaturation', 'habitat').value,
        scalingZ = _p(m, 'scalingZ', 'habitat').value,
        speciesAreaZ = _p(m, 'speciesAreaZ', 'habitat').value,
        threats = {
          for (final e in _map(m['threats'], 'habitat.threats').entries)
            TileType.fromId(e.key): ThreatParams(
              _p(_map(e.value, 'habitat.threats.${e.key}'), 'weight', 'habitat.threats.${e.key}').value,
              _p(_map(e.value, 'habitat.threats.${e.key}'), 'maxDistanceM', 'habitat.threats.${e.key}').value,
            ),
        };

  final double halfSaturation;
  final double scalingZ;
  final double speciesAreaZ;
  final Map<TileType, ThreatParams> threats;
}

class ModeShareBin {
  const ModeShareBin(this.maxKm, this.walk, this.bike, this.car);
  final double maxKm;
  final double walk;
  final double bike;
  final double car;
}

class CommuteParams {
  CommuteParams(Map<String, dynamic> m)
      : labourParticipation = _p(m, 'labourParticipation', 'commute').value,
        roadSearchRadiusTiles = _p(m, 'roadSearchRadiusTiles', 'commute').value.round(),
        externalCommuteKm = _p(m, 'externalCommuteKm', 'commute').value,
        externalCarShare = _p(m, 'externalCarShare', 'commute').value,
        carKgCo2PerKm = _p(m, 'carKgCo2PerKm', 'commute').value,
        workingDaysPerMonth = _p(m, 'workingDaysPerMonth', 'commute').value,
        referenceCommuteKm = _p(m, 'referenceCommuteKm', 'commute', 20).value,
        transitWalkRadiusTiles = _p(
          m,
          'transitWalkRadiusTiles',
          'commute',
        ).value.round(),
        transitCarReduction = _p(m, 'transitCarReduction', 'commute').value,
        cyclePathRadiusTiles = _p(
          m,
          'cyclePathRadiusTiles',
          'commute',
        ).value.round(),
        cycleCarReduction = _p(m, 'cycleCarReduction', 'commute').value,
        cycleCompetitiveKm = _p(m, 'cycleCompetitiveKm', 'commute').value,
        minCarShareFactor = _p(m, 'minCarShareFactor', 'commute').value,
        modeShareBins = [
          for (final b in (_map(m['modeShareByDistance'], 'commute.modeShareByDistance')['bins'] as List<dynamic>)
              .cast<Map<String, dynamic>>())
            ModeShareBin(
              (b['maxKm'] as num).toDouble(),
              (b['walk'] as num).toDouble(),
              (b['bike'] as num).toDouble(),
              (b['car'] as num).toDouble(),
            ),
        ];

  final double labourParticipation;
  final int roadSearchRadiusTiles;
  final double externalCommuteKm;
  final double externalCarShare;
  final double carKgCo2PerKm;
  final double workingDaysPerMonth;
  final double referenceCommuteKm;
  final List<ModeShareBin> modeShareBins;

  /// Walking catchment of a tram stop, in tiles.
  final int transitWalkRadiusTiles;

  /// Share of a cell's car trips a stop in reach can take, at most.
  final double transitCarReduction;

  /// How far a cycle route counts as reachable, in tiles.
  final int cyclePathRadiusTiles;

  /// Share of a cell's car trips a route in reach can take, at most.
  final double cycleCarReduction;

  /// Distance beyond which cycling stops competing with the car, km.
  final double cycleCompetitiveKm;

  /// Floor on the combined shift, so some car trips always remain.
  final double minCarShareFactor;

  /// Car share for a one-way commute of [km].
  double carShare(double km) {
    for (final b in modeShareBins) {
      if (km <= b.maxKm) return b.car;
    }
    return modeShareBins.last.car;
  }
}

class AttractivenessWeights {
  const AttractivenessWeights({
    required this.noise,
    required this.air,
    required this.green,
    required this.retail,
    required this.jobs,
    required this.heat,
  });

  final double noise;
  final double air;
  final double green;
  final double retail;
  final double jobs;
  final double heat;

  double get sum => noise + air + green + retail + jobs + heat;
}

class EconomyParams {
  EconomyParams(Map<String, dynamic> m)
      : incomeTaxPerResidentYear = _p(m, 'incomeTaxPerResidentYear', 'economy').value,
        propertyTaxPerResidentYear = _p(m, 'propertyTaxPerResidentYear', 'economy').value,
        businessTaxPerJobYear = _p(m, 'businessTaxPerJobYear', 'economy').value,
        startBudgetKEur = _p(m, 'startBudgetKEur', 'economy').value,
        demolitionCostKEur = _p(m, 'demolitionCostKEur', 'economy').value,
        immigrationRate = _p(m, 'immigrationRate', 'economy').value,
        emigrationRate = _p(m, 'emigrationRate', 'economy').value,
        unconnectedAttractivenessFactor = _p(m, 'unconnectedAttractivenessFactor', 'economy').value,
        attractiveness = _weights(_map(m['attractivenessWeights'], 'economy.attractivenessWeights'));

  static AttractivenessWeights _weights(Map<String, dynamic> w) => AttractivenessWeights(
        noise: (w['noise'] as num).toDouble(),
        air: (w['air'] as num).toDouble(),
        green: (w['green'] as num).toDouble(),
        retail: (w['retail'] as num).toDouble(),
        jobs: (w['jobs'] as num).toDouble(),
        heat: (w['heat'] as num).toDouble(),
      );

  final double incomeTaxPerResidentYear;
  final double propertyTaxPerResidentYear;
  final double businessTaxPerJobYear;
  final double startBudgetKEur;
  final double demolitionCostKEur;
  final double immigrationRate;
  final double emigrationRate;
  final double unconnectedAttractivenessFactor;
  final AttractivenessWeights attractiveness;
}

/// All simulation parameters, loaded from JSON. Immutable once built.
class SimParams {
  SimParams._({
    required this.schemaVersion,
    required this.cellSizeM,
    required this.tiles,
    required this.noise,
    required this.air,
    required this.heat,
    required this.access,
    required this.habitat,
    required this.commute,
    required this.economy,
    required this.seasons,
    required this.water,
  });

  final int schemaVersion;
  final double cellSizeM;
  final Map<TileType, TileParams> tiles;
  final NoiseParams noise;
  final AirParams air;
  final HeatParams heat;
  final AccessParams access;
  final HabitatParams habitat;
  final CommuteParams commute;
  final EconomyParams economy;
  final SeasonParams seasons;
  final WaterParams water;

  TileParams tile(TileType t) => tiles[t]!;

  static SimParams? _defaults;

  /// The parameters shipped with the game (`data/params/tiles.json`).
  static SimParams defaults() => _defaults ??= fromJsonString(defaultParamsJson);

  static SimParams fromJsonString(String json) => fromJson(jsonDecode(json) as Map<String, dynamic>);

  static SimParams fromJson(Map<String, dynamic> root) {
    final tilesJson = _map(root['tiles'], 'tiles');
    final tiles = <TileType, TileParams>{};
    for (final t in TileType.values) {
      final m = tilesJson[t.id];
      if (m == null) throw FormatException('tiles.json is missing tile ${t.id}');
      tiles[t] = TileParams.fromJson(t, _map(m, 'tiles.${t.id}'));
    }
    for (final key in tilesJson.keys) {
      TileType.fromId(key); // throws on unknown ids
    }
    final grid = _map(root['grid'], 'grid');
    return SimParams._(
      schemaVersion: (root['schemaVersion'] as num?)?.toInt() ?? 1,
      cellSizeM: _p(grid, 'cellSizeM', 'grid').value,
      tiles: tiles,
      noise: NoiseParams(_map(root['noise'], 'noise')),
      air: AirParams(_map(root['air'], 'air')),
      heat: HeatParams(_map(root['heat'], 'heat')),
      access: AccessParams(_map(root['access'], 'access')),
      habitat: HabitatParams(_map(root['habitat'], 'habitat')),
      commute: CommuteParams(_map(root['commute'], 'commute')),
      seasons: SeasonParams(_map(root['seasons'], 'seasons')),
      water: WaterParams(_map(root['water'], 'water')),
      economy: EconomyParams(_map(root['economy'], 'economy')),
    );
  }
}
