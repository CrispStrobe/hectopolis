// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:math' as math;

import 'package:stadtbau_sim/stadtbau_sim.dart';
import 'package:test/test.dart';

/// The SCS equation written out independently of the implementation, so the
/// test would notice the implementation drifting from the published method.
double _scsRunoff(double rain, double cn, double iaRatio) {
  final s = 25400 / cn - 254;
  final ia = iaRatio * s;
  if (rain <= ia) return 0;
  return math.pow(rain - ia, 2) / (rain - ia + s);
}

void main() {
  final params = SimParams.defaults();
  final wp = params.water;

  test('runoff matches the published SCS equation for a sealed tile', () {
    final sim = Simulation.sandbox();
    sim.apply(const PlaceTile(8, 8, TileType.road));
    final road = params.tile(TileType.road);
    final cn =
        road.perviousCurveNumber.value +
        road.sealing.value *
            (wp.imperviousCurveNumber - road.perviousCurveNumber.value);
    expect(
      sim.fields.runoffMm[sim.state.index(8, 8)],
      closeTo(
        _scsRunoff(wp.designStormMm, cn, wp.initialAbstractionRatio),
        1e-9,
      ),
    );
  });

  test('sealing the ground is what makes water run off it', () {
    final sim = Simulation.sandbox();
    double runoffOf(TileType t, int x, int y) {
      sim.apply(PlaceTile(x, y, t));
      return sim.fields.runoffMm[sim.state.index(x, y)];
    }

    // Forest sheds least, road most, and the order follows sealing.
    final forest = runoffOf(TileType.forest, 2, 2);
    final lowHousing = runoffOf(TileType.housingLow, 4, 2);
    final industry = runoffOf(TileType.industry, 6, 2);
    final road = runoffOf(TileType.road, 8, 2);
    expect(forest, lessThan(lowHousing));
    expect(lowHousing, lessThan(industry));
    expect(industry, lessThan(road));
  });

  test('a five-year hour barely troubles woodland', () {
    final sim = Simulation.sandbox();
    sim.apply(const PlaceTile(8, 8, TileType.forest));
    // CN 55 on group B soil: 22.1 mm is close to the initial abstraction, so
    // almost nothing leaves the surface. That is the point of the number.
    expect(sim.fields.runoffMm[sim.state.index(8, 8)], lessThan(1.0));
  });

  test('water retains runoff from its surroundings', () {
    // Road, not industry: the flood threshold is 10 mm and an industrial
    // hectare sheds 9.6 mm of the design storm, so a block of industry has no
    // cell at risk to take away. T-103 moved industry sealing from 0.90 to the
    // measured 0.88 and that margin closed; the test had been resting on it.
    final sealed = Simulation.sandbox();
    for (var x = 4; x < 11; x++) {
      for (var y = 4; y < 11; y++) {
        sealed.apply(PlaceTile(x, y, TileType.road));
      }
    }
    final before = sealed.fields.meanRunoffMm;
    final riskBefore = sealed.fields.floodRiskCells;

    sealed.apply(const PlaceTile(7, 7, TileType.water));
    expect(sealed.fields.meanRunoffMm, lessThan(before));
    expect(sealed.fields.floodRiskCells, lessThan(riskBefore));
  });

  test('wetland retains like open water', () {
    double meanRunoffWith(TileType retention) {
      final sim = Simulation.sandbox();
      for (var x = 4; x < 11; x++) {
        for (var y = 4; y < 11; y++) {
          sim.apply(PlaceTile(x, y, TileType.industry));
        }
      }
      final sealed = sim.fields.meanRunoffMm;
      sim.apply(PlaceTile(7, 7, retention));
      expect(sim.fields.meanRunoffMm, lessThan(sealed), reason: retention.id);
      return sim.fields.meanRunoffMm;
    }

    // Both hold a storm back, and by the same capacity parameter.
    expect(
      meanRunoffWith(TileType.wetland),
      closeTo(meanRunoffWith(TileType.water), 1e-12),
    );
  });

  test('a bare map shows no flood risk', () {
    final sim = Simulation.sandbox();
    expect(sim.fields.floodRiskCells, 0);
    expect(sim.fields.meanRunoffMm, lessThan(wp.floodRiskMm));
  });
}
