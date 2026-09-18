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
| dense quarter | ΔT | 1–2.5 °C | **0.18 — out of range, and was already out of range before T-103** |
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

## Re-run 2026-09-18 (T-103)

The harness was re-run after T-103 changed sealing, the CO₂ table, the climate
zero point and the industry noise emission. Everything above still holds except
two rows, both now marked in the table:

**industrial park, residents above 55 dB(A): 63 % → 43 %.** This is the
industry noise emission moving from 65 to 63 dB(A), the value DIN 18005-1's
area-related sound power level actually gives (`tiles.md`). Two decibels is a
factor of 1.6 in sound energy, and it moves a lot of dwellings across the 55 dB
line. The expectation was a plausibility judgement made against the overstated
emission, so the expectation is what changed, not the model: an industrial park
where two in five residents are above 55 dB(A) is still an industrial park with
a noise problem.

**dense quarter ΔT: 1.6 °C recorded, 0.18 °C measured — and this is not T-103's
doing.** The same 0.18 comes out of the harness at `fae9447`, the commit before
this work started, so the heat model or its parameters drifted from the
recorded figure at some point since 2026-09-05 and nobody re-ran the harness.
The row is left in with the discrepancy visible rather than quietly updated,
because it needs a look: either the archetype no longer builds what it used to,
or the cooling model changed and this is a regression. It is not in T-103's
scope.
