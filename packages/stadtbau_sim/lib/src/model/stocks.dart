// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:math' as math;

import '../fields.dart';
import '../geometry.dart';
import '../params.dart';
import '../world.dart';

/// Per-cell residential attractiveness from the spatial fields (0–1).
/// Weights from `economy.attractivenessWeights`. Cells without a main road
/// within reach are penalised.
void computeAttractiveness(WorldState w, SimParams p, Fields f) {
  final ep = p.economy;
  final aw = ep.attractiveness;
  final np = p.noise;
  for (var i = 0; i < w.cellCount; i++) {
    if (!p.tile(w.tiles[i]).isResidential) {
      f.attractiveness[i] = 0;
      continue;
    }
    final noiseScore = clamp01((np.limitBadDb - f.noiseDb[i]) / (np.limitBadDb - np.limitDayDb));
    final airScore = f.airIndex[i] / 100;
    final heatScore = f.heatScoreOf(f.heatDeltaC[i]);
    var a = (aw.noise * noiseScore +
            aw.air * airScore +
            aw.green * f.greenAccess[i] +
            aw.retail * f.retailAccess[i] +
            aw.jobs * f.jobAccess[i] +
            aw.heat * heatScore) /
        aw.sum;
    if (f.connected[i] == 0) a *= ep.unconnectedAttractivenessFactor;
    f.attractiveness[i] = clamp01(a);
  }
}

/// Result of one month of stock updates.
class StockDelta {
  StockDelta({
    required this.revenueKEur,
    required this.maintenanceKEur,
    required this.co2TonsPerYear,
    required this.jobsFilled,
  });

  final double revenueKEur;
  final double maintenanceKEur;
  final double co2TonsPerYear;
  final double jobsFilled;

  double get netKEur => revenueKEur - maintenanceKEur;
}

/// Advance population, budget and derived stocks by one month.
/// Population moves towards capacity at a rate set by attractiveness
/// (docs/model/economy.md). Taxes and maintenance are annual figures ÷ 12.
StockDelta advanceStocks(WorldState w, SimParams p, Fields f) {
  final ep = p.economy;
  final cp = p.commute;
  var population = 0.0;
  var maintenance = 0.0;
  var co2 = 0.0;
  for (var i = 0; i < w.cellCount; i++) {
    final tp = p.tile(w.tiles[i]);
    w.tileAge[i] += 1;
    maintenance += tp.maintenanceKEurYear.value;
    if (tp.isResidential) {
      final cap = tp.residentsPerHa.value;
      final a = f.attractiveness[i];
      var pop = w.population[i];
      pop += (cap - pop) * a * ep.immigrationRate;
      pop -= pop * (1 - a) * ep.emigrationRate;
      pop = math.max(0, math.min(cap, pop));
      w.population[i] = pop;
      population += pop;
      co2 += tp.co2PerHaYear.value * (cap > 0 ? pop / cap : 0);
    } else {
      w.population[i] = 0;
      co2 += tp.co2PerHaYear.value;
    }
  }
  final workers = population * cp.labourParticipation;
  final jobsFilled = math.min(f.jobsCapacity, workers);
  final revenueYear = population * (ep.incomeTaxPerResidentYear + ep.propertyTaxPerResidentYear) +
      jobsFilled * ep.businessTaxPerJobYear;
  final revenueKEur = revenueYear / 12 / 1000;
  final maintenanceKEur = maintenance / 12;
  f.revenueKEur = revenueKEur;
  f.maintenanceKEur = maintenanceKEur;
  w.budgetKEur += revenueKEur - maintenanceKEur;
  w.tick += 1;

  // Traffic CO2: car-km per weekday × working days × 12 months.
  co2 += f.totalCarKmPerDay * cp.workingDaysPerMonth * 12 * cp.carKgCo2PerKm / 1000;

  return StockDelta(
    revenueKEur: revenueKEur,
    maintenanceKEur: maintenanceKEur,
    co2TonsPerYear: co2,
    jobsFilled: jobsFilled,
  );
}

/// CO₂ balance without advancing the state (for the initial snapshot).
double estimateCo2(WorldState w, SimParams p, Fields f) {
  var co2 = 0.0;
  for (var i = 0; i < w.cellCount; i++) {
    final tp = p.tile(w.tiles[i]);
    if (tp.isResidential) {
      final cap = tp.residentsPerHa.value;
      co2 += tp.co2PerHaYear.value * (cap > 0 ? w.population[i] / cap : 0);
    } else {
      co2 += tp.co2PerHaYear.value;
    }
  }
  final cp = p.commute;
  return co2 + f.totalCarKmPerDay * cp.workingDaysPerMonth * 12 * cp.carKgCo2PerKm / 1000;
}
