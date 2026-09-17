// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:typed_data';

/// Spatial fields derived from the world state, one value per cell.
/// Recomputed every tick; never serialised.
class Fields {
  Fields(int n)
      : noiseDb = Float64List(n),
        noiseNightDb = Float64List(n),
        airConcentration = Float64List(n),
        airIndex = Float64List(n),
        coolingCapacity = Float64List(n),
        heatDeltaC = Float64List(n),
        greenAccess = Float64List(n),
        retailAccess = Float64List(n),
        jobAccess = Float64List(n),
        habitatQuality = Float64List(n),
        habitatThreat = Float64List(n),
        traffic = Float64List(n),
        meanCommuteKm = Float64List(n),
        carShare = Float64List(n),
        transitAccess = Float64List(n),
        cycleAccess = Float64List(n),
        attractiveness = Float64List(n),
        connected = Uint8List(n),
        runoffMm = Float64List(n);

  /// L_den-like day level in dB(A) at the cell centre.
  final Float64List noiseDb;

  /// L_night-like night level in dB(A), from the same sources with their
  /// night emissions (docs/model/noise.md).
  final Float64List noiseNightDb;

  /// Relative pollutant concentration (unitless, see docs/model/air.md).
  final Float64List airConcentration;

  /// 0–100, 100 = clean.
  final Float64List airIndex;

  /// InVEST cooling capacity 0–1 per cell (own land cover).
  final Float64List coolingCapacity;

  /// Air temperature excess over rural reference, °C.
  final Float64List heatDeltaC;

  /// 0–1 recreation access score (green within 300 m).
  final Float64List greenAccess;

  /// 0–1 Huff retail accessibility score.
  final Float64List retailAccess;

  /// 0–1 gravity job accessibility score.
  final Float64List jobAccess;

  /// 0–1 InVEST-style habitat quality (0 for non-habitat cells).
  final Float64List habitatQuality;

  /// 0–1 threat degradation for habitat cells.
  final Float64List habitatThreat;

  /// Vehicles per day on road cells (0 elsewhere).
  final Float64List traffic;

  /// Mean one-way commute distance for residents of the cell, km.
  final Float64List meanCommuteKm;

  /// Car share of commutes starting in the cell, 0–1.
  final Float64List carShare;

  /// 0–1 reach of a tram stop and of a cycle route from the cell, falling off
  /// to zero at the radius (docs/model/commute.md).
  final Float64List transitAccess;
  final Float64List cycleAccess;

  /// 0–1 residential attractiveness (0 for non-residential cells).
  final Float64List attractiveness;

  /// 1 if a main road is within reach, else 0.
  final Uint8List connected;

  /// Runoff depth from the design storm, mm (docs/model/water.md).
  final Float64List runoffMm;

  /// Overwrite every field and aggregate with [other]'s, which must describe a
  /// grid of the same size.
  ///
  /// Copying derived state is several thousand times cheaper than deriving it
  /// again, so a snapshot of an up-to-date simulation clones the fields rather
  /// than recomputing them.
  void copyFrom(Fields other) {
    noiseDb.setAll(0, other.noiseDb);
    noiseNightDb.setAll(0, other.noiseNightDb);
    airConcentration.setAll(0, other.airConcentration);
    airIndex.setAll(0, other.airIndex);
    coolingCapacity.setAll(0, other.coolingCapacity);
    heatDeltaC.setAll(0, other.heatDeltaC);
    greenAccess.setAll(0, other.greenAccess);
    retailAccess.setAll(0, other.retailAccess);
    jobAccess.setAll(0, other.jobAccess);
    habitatQuality.setAll(0, other.habitatQuality);
    habitatThreat.setAll(0, other.habitatThreat);
    traffic.setAll(0, other.traffic);
    meanCommuteKm.setAll(0, other.meanCommuteKm);
    carShare.setAll(0, other.carShare);
    transitAccess.setAll(0, other.transitAccess);
    cycleAccess.setAll(0, other.cycleAccess);
    attractiveness.setAll(0, other.attractiveness);
    connected.setAll(0, other.connected);
    runoffMm.setAll(0, other.runoffMm);
    totalCarKmPerDay = other.totalCarKmPerDay;
    revenueKEur = other.revenueKEur;
    maintenanceKEur = other.maintenanceKEur;
    workers = other.workers;
    jobsCapacity = other.jobsCapacity;
    inCommuters = other.inCommuters;
    outCommuters = other.outCommuters;
    biodiversityIndex = other.biodiversityIndex;
    habitatAreaEff = other.habitatAreaEff;
    habitatConnectivity = other.habitatConnectivity;
    meanRunoffMm = other.meanRunoffMm;
    floodRiskCells = other.floodRiskCells;
  }

  /// Aggregates produced while computing the fields.
  double totalCarKmPerDay = 0;

  /// Monthly municipal income and upkeep from the most recent tick. Flows, not
  /// stocks: they stay put while tiles are placed and refresh on the next tick.
  double revenueKEur = 0;
  double maintenanceKEur = 0;
  double workers = 0;
  double jobsCapacity = 0;
  double inCommuters = 0;
  double outCommuters = 0;
  double biodiversityIndex = 0;
  double habitatAreaEff = 0;
  double habitatConnectivity = 0;

  /// Mean runoff depth over the map, mm, and how many cells shed more than
  /// the flood-risk threshold.
  double meanRunoffMm = 0;
  int floodRiskCells = 0;
}
