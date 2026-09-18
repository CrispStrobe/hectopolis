# Calibration

Harness: `packages/stadtbau_sim/tool/calibrate.dart` (`dart run tool/calibrate.dart
[--json]`). It builds seven 16×16 archetypes, pre-populates housing to 90 %,
runs 60 months and prints indicators and raw values. Coefficients are adjusted
only in `data/params/tiles.json`.

## Plausibility ranges and results (2026-09-05)

| Archetype | Quantity | Expected | Result |
|---|---|---|---|
| forest | biodiversity | 85–100 | 92 |
| forest | ΔT | 0 °C | 0.00 |
| meadow | ΔT (rural reference) | 0 °C | 0.00 |
| cropland | air index | > 90 | 96 |
| village (EFH, one shop) | share of residents > 55 dB(A) | < 10 % | 4 % |
| village | mean commute | 3–6 km | 4.2 |
| village | car share | 0.35–0.6 | 0.44 |
| suburb (EFH grid, arterials) | car share | 0.5–0.8 | 0.55 |
| suburb | biodiversity | 30–50 | 40 |
| dense quarter (MFH, 4 arterials) | population | 15 000–25 000 | 21 400 |
| dense quarter | residents > 55 dB(A) | 50–80 % | 67 % |
| dense quarter | air index | 60–85 | 80 |
| dense quarter | ΔT (annual mean) | 1–2.5 °C | 1.71 |
| dense quarter | max road traffic | 3 000–10 000 | 4 000 |
| all levels | solvable with three stars by the plans in `test/level_solutions_test.dart` | yes | yes |
| industrial park with housing | residents > 55 dB(A) | > 40 % | 43 % (was 63 % before T-103) |
| industrial park | housing score | < 30 (jobs without homes) | 15 |
| mixed town | shopping | > 70 | 84 |
| mixed town | budget delta | positive | +765 k€/month |

## Performance (T-115)

Dense 24×24 map, 18 700 residents, 16 300 jobs: 38 ms per tick on a heavily
loaded 4-core VPS (load average ≈ 17), down from 180 ms before routing trips
per road pair, pruning noise paths and computing fields once per tick.
Commute (22 ms) and noise (7 ms) dominate; see `benchmark/tick_benchmark.dart`.

## Open calibration questions

- Road traffic on arterials stays below real-world 10–20 000 vehicles/day
  because a 2.5 km² map has no through-traffic beyond the 2 000 baseline. A
  level-level "regional traffic" parameter could scale the baseline.
- Budget surpluses are large once a quarter is full; costs of schools, social
  infrastructure and transport are not modelled (Phase 5).
- Noise exposure in the dense quarter is dominated by the sum of many 50 dB
  building sources; verify apartment-block emission against TA Lärm practice.

## Re-run 2026-09-18 (T-103, then the heat fix)

The harness was re-run after T-103 changed sealing, the CO₂ table, the climate
zero point and the industry noise emission, and again after the heat scoring
fix. Everything holds. Two rows are worth reading twice:

**industrial park, residents above 55 dB(A): 63 % → 43 %.** This is the
industry noise emission moving from 65 to 63 dB(A), the value DIN 18005-1's
area-related sound power level actually gives (`tiles.md`). Two decibels is a
factor of 1.6 in sound energy, and it moves a lot of dwellings across the 55 dB
line. The expectation was a plausibility judgement made against the overstated
emission, so the expectation is what changed, not the model: an industrial park
where two in five residents are above 55 dB(A) is still an industrial park with
a noise problem.

**dense quarter ΔT: the 0.18 K this harness used to print was a January
reading, not a regression.** 60 ticks is a whole number of years and tick 0 is
January, so the snapshot landed in the coldest month of the cycle. The annual
mean is 1.71 K, which is the 1.6 K this file recorded from the season-free
model. The harness now sweeps the twelve months after the warm-up and reports
`heatDeltaCYearMean` and `heatDeltaCSummerPeak` alongside the snapshot, so a
seasonal quantity can no longer be read as if it were an annual one.

### Seasonal columns (2026-09-18)

| Archetype | ΔT annual mean | ΔT July peak | recreation over the year | climate over the year |
|---|---|---|---|---|
| forest | 0.00 | 0.00 | 100 | 100 |
| meadow | 0.00 | 0.00 | 86 | 100 |
| cropland | 0.97 | 1.73 | 54 (51–56) | 56 (53–58) |
| village | 0.62 | 1.57 | 89 (85–93) | 82 (78–86) |
| suburb | 0.84 | 2.14 | 62 (57–68) | 80 (75–86) |
| dense quarter | 1.71 | 3.72 | 34 (30–42) | 72 (67–80) |
| industrial park | 0.78 | 1.89 | 84 (79–89) | 25 (20–30) |
| mixed town | 0.92 | 2.12 | 75 (71–79) | 43 (39–48) |

The spreads in brackets are the range over the twelve months. Before the heat
fix the climate spread was not a spread at all in summer: every dense quarter
scored the same 53.8 in July whether it had sixteen hectares of park or none,
because a 4.1 K ΔT over a 3.0 K denominator clamps. See `heat.md`.
