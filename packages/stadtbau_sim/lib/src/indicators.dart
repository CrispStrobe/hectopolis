// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:math' as math;

import 'fields.dart';
import 'geometry.dart';
import 'params.dart';
import 'world.dart';

/// The ten player-facing indicators. Scores are 0–100; raw values carry units.
enum Indicator {
  biodiversity,
  air,
  noise,
  housing,
  economy,
  shopping,
  recreation,
  commuting,
  climate,
  budget,
}

class IndicatorSnapshot {
  IndicatorSnapshot({
    required this.tick,
    required this.scores,
    required this.population,
    required this.housingCapacity,
    required this.jobsCapacity,
    required this.jobsFilled,
    required this.budgetKEur,
    required this.budgetDeltaKEur,
    required this.meanNoiseDb,
    required this.meanNightNoiseDb,
    required this.shareAboveNightGuideline,
    required this.shareAboveNightHighRisk,
    required this.meanAirIndex,
    required this.meanCommuteKm,
    required this.carShare,
    required this.co2TonsPerYear,
    required this.meanHeatDeltaC,
    required this.habitatAreaEff,
    required this.habitatConnectivity,
  });

  final int tick;
  final Map<Indicator, double> scores;
  final double population;
  final double housingCapacity;
  final double jobsCapacity;
  final double jobsFilled;
  final double budgetKEur;
  final double budgetDeltaKEur;
  final double meanNoiseDb;

  /// Resident-weighted mean night level, dB L_night.
  final double meanNightNoiseDb;

  /// Share of residents whose night level exceeds the WHO 2018 road-traffic
  /// recommendation of 45 dB, and the WHO 2009 interim target of 55 dB above
  /// which cardiovascular effects dominate. Reported, not scored: see
  /// docs/model/noise.md.
  final double shareAboveNightGuideline;
  final double shareAboveNightHighRisk;
  final double meanAirIndex;
  final double meanCommuteKm;
  final double carShare;
  final double co2TonsPerYear;
  final double meanHeatDeltaC;
  final double habitatAreaEff;
  final double habitatConnectivity;

  double score(Indicator i) => scores[i] ?? 0;

  Map<String, dynamic> toJson() => {
        'tick': tick,
        'scores': {for (final e in scores.entries) e.key.name: e.value},
        'population': population,
        'housingCapacity': housingCapacity,
        'jobsCapacity': jobsCapacity,
        'jobsFilled': jobsFilled,
        'budgetKEur': budgetKEur,
        'budgetDeltaKEur': budgetDeltaKEur,
        'meanNoiseDb': meanNoiseDb,
        'meanNightNoiseDb': meanNightNoiseDb,
        'shareAboveNightGuideline': shareAboveNightGuideline,
        'shareAboveNightHighRisk': shareAboveNightHighRisk,
        'meanAirIndex': meanAirIndex,
        'meanCommuteKm': meanCommuteKm,
        'carShare': carShare,
        'co2TonsPerYear': co2TonsPerYear,
        'meanHeatDeltaC': meanHeatDeltaC,
        'habitatAreaEff': habitatAreaEff,
        'habitatConnectivity': habitatConnectivity,
      };
}

/// Compute indicators from the current state and fields.
/// Resident-weighted means fall back to capacity weights (empty new housing)
/// and then to plain map means (no housing at all).
IndicatorSnapshot computeIndicators(
  WorldState w,
  SimParams p,
  Fields f, {
  required double budgetDeltaKEur,
  required double co2TonsPerYear,
}) {
  final n = w.cellCount;
  final np = p.noise;
  var population = 0.0;
  var capacity = 0.0;
  for (var i = 0; i < n; i++) {
    population += w.population[i];
    capacity += p.tile(w.tiles[i]).residentsPerHa.value;
  }

  double weightOf(int i) {
    if (population > 0) return w.population[i];
    if (capacity > 0) return p.tile(w.tiles[i]).residentsPerHa.value;
    return 1;
  }

  var wsum = 0.0;
  var noiseScore = 0.0;
  var noiseDb = 0.0;
  var nightDb = 0.0;
  var aboveGuideline = 0.0;
  var aboveHighRisk = 0.0;
  var air = 0.0;
  var green = 0.0;
  var retail = 0.0;
  var heat = 0.0;
  var heatScore = 0.0;
  var commuteKm = 0.0;
  var carShare = 0.0;
  var commuteWeight = 0.0;
  for (var i = 0; i < n; i++) {
    final wt = weightOf(i);
    if (wt <= 0) continue;
    wsum += wt;
    noiseScore += wt * clamp01((np.limitBadDb - f.noiseDb[i]) / (np.limitBadDb - np.limitDayDb));
    noiseDb += wt * f.noiseDb[i];
    nightDb += wt * f.noiseNightDb[i];
    if (f.noiseNightDb[i] > np.nightGuidelineDb) aboveGuideline += wt;
    if (f.noiseNightDb[i] > np.nightHighRiskDb) aboveHighRisk += wt;
    air += wt * f.airIndex[i];
    green += wt * f.greenAccess[i];
    retail += wt * f.retailAccess[i];
    heat += wt * f.heatDeltaC[i];
    heatScore += wt * (1 - clamp01(f.heatDeltaC[i] / p.heat.uhiMaxC));
    if (w.population[i] > 0) {
      commuteWeight += w.population[i];
      commuteKm += w.population[i] * f.meanCommuteKm[i];
      carShare += w.population[i] * f.carShare[i];
    }
  }
  if (wsum > 0) {
    noiseScore /= wsum;
    noiseDb /= wsum;
    nightDb /= wsum;
    aboveGuideline /= wsum;
    aboveHighRisk /= wsum;
    air /= wsum;
    green /= wsum;
    retail /= wsum;
    heat /= wsum;
    heatScore /= wsum;
  }
  if (commuteWeight > 0) {
    commuteKm /= commuteWeight;
    carShare /= commuteWeight;
  }

  final hasResidents = population > 0;
  final workers = population * p.commute.labourParticipation;
  final jobsFilled = math.min(f.jobsCapacity, workers);

  // Housing: capacity relative to what local jobs would demand, times occupancy.
  double housing;
  if (capacity <= 0) {
    housing = 0;
  } else {
    final demand = f.jobsCapacity / p.commute.labourParticipation;
    final supply = demand > 0 ? math.min(1.0, capacity / demand) : 1.0;
    final occupancy = population / capacity;
    housing = 100 * supply * (0.5 + 0.5 * occupancy);
  }

  // Economy: jobs for residents and budget trend.
  double economy;
  if (workers <= 0 && f.jobsCapacity <= 0) {
    economy = 0;
  } else {
    final jobsRatio = workers > 0 ? math.min(1.0, f.jobsCapacity / workers) : 0.5;
    final trend = budgetDeltaKEur >= 0 ? 1.0 : clamp01(1 + budgetDeltaKEur / 500);
    economy = 100 * (0.6 * jobsRatio + 0.4 * trend);
  }

  final commuting = hasResidents
      ? 100 * (0.5 * (1 - clamp01(commuteKm / p.commute.referenceCommuteKm)) + 0.5 * (1 - carShare))
      : 0.0;

  // CO₂ per person (residents + jobs), floored at a tenth of the cell count
  // so that empty maps are judged by their absolute balance. 2.5 t/person/a
  // scores zero; a net sink scores one.
  final people = math.max(population + f.jobsCapacity, n / 10);
  final co2Score = clamp01(1 - (co2TonsPerYear / people) / 2.5);
  final climate = 100 * (0.7 * co2Score + 0.3 * (1 - clamp01(heat / p.heat.uhiMaxC)));

  final scores = <Indicator, double>{
    Indicator.biodiversity: f.biodiversityIndex,
    Indicator.air: air,
    Indicator.noise: 100 * noiseScore,
    Indicator.housing: housing,
    Indicator.economy: economy,
    Indicator.shopping: 100 * retail,
    Indicator.recreation: 100 * (0.7 * green + 0.3 * heatScore),
    Indicator.commuting: commuting,
    Indicator.climate: climate,
    Indicator.budget: clamp01(w.budgetKEur / p.economy.startBudgetKEur) * 100,
  };

  return IndicatorSnapshot(
    tick: w.tick,
    scores: scores,
    population: population,
    housingCapacity: capacity,
    jobsCapacity: f.jobsCapacity,
    jobsFilled: jobsFilled,
    budgetKEur: w.budgetKEur,
    budgetDeltaKEur: budgetDeltaKEur,
    meanNoiseDb: noiseDb,
    meanNightNoiseDb: nightDb,
    shareAboveNightGuideline: aboveGuideline,
    shareAboveNightHighRisk: aboveHighRisk,
    meanAirIndex: air,
    meanCommuteKm: commuteKm,
    carShare: carShare,
    co2TonsPerYear: co2TonsPerYear,
    meanHeatDeltaC: heat,
    habitatAreaEff: f.habitatAreaEff,
    habitatConnectivity: f.habitatConnectivity,
  );
}
