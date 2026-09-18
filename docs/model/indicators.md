# Indicators

Code: `packages/stadtbau_sim/lib/src/indicators.dart`. All scores are 0–100.
"Resident-weighted" means weighted by residents per cell, falling back to
housing capacity (new, empty housing) and then to a plain map mean.

| Indicator | Formula |
|---|---|
| Biodiversity | `B` from `biodiversity.md` |
| Air quality | resident-weighted air index |
| Quiet (noise) | resident-weighted `clamp((65 − L) / 10)` × 100 |
| Housing | `100 · min(1, capacity / (jobs / 0.52)) · (0.5 + 0.5 · occupancy)`; 0 without housing |
| Economy | `100 · (0.6 · min(1, jobs / workers) + 0.4 · trend)`, trend 1 if the last month was positive, else `clamp(1 + Δbudget / 500 k€)` |
| Shopping | resident-weighted retail access × 100 |
| Recreation | resident-weighted `0.7 · green access + 0.3 · (1 − ΔT / UHI_max(month))` × 100 |
| Commuting | `100 · (0.5 · (1 − min(1, d̄ / 20 km)) + 0.5 · (1 − car share))` (20 km ≈ MiD 2017 mean commute plus margin) |
| Climate | `100 · (0.7 · clamp(1 − CO₂ per person / climate.zeroScoreTonsPerPerson) + 0.3 · (1 − ΔT̄ / UHI_max(month)))`, persons = residents + jobs, floored at cells / 10 |
| Budget | `clamp(budget / starting budget) × 100` |

Raw values shown alongside: population, capacity, jobs, budget and monthly
delta, mean noise dB(A), mean air index, mean commute km, car share, CO₂ t/a,
mean ΔT, effective habitat area and connectivity.

## `UHI_max(month)`, not `UHI_max`

Both heat terms divide by `fields.uhiMaxNowC` — the parameter `heat.uhiMaxC`
times the month's heat factor — and not by the parameter alone. Dividing by the
annual parameter clamped every summer score to zero and stopped the indicator
discriminating exactly when heat matters. The whole argument is in `heat.md`;
`seasons_test.dart` pins it.

## The climate zero point (changed in T-103)

`climate.zeroScoreTonsPerPerson` is **5.0 t** of CO₂ per resident-or-job. It
was 2.5, hard-coded, with no source.

The number is Germany's own: 650 Mt CO₂-eq in 2024 (UBA, finale Daten) over
83.5 M residents and 46.1 M Erwerbstätige (Destatis) — 5.0 t per
resident-or-job, using the same denominator the indicator uses. So **a city
that emits like Germany does today scores zero on the CO₂ half of the climate
indicator, and a city in net balance scores one hundred.**

It had to move because T-103 corrected the per-hectare CO₂ of the four built
tiles, which had been roughly a third of their real values (see `tiles.md`).
Against a scale calibrated to the old, too-small table, correct emissions would
have scored every city zero. Both halves are now the same physics: real tonnes
against the real national figure.

## References

- UBA, finale Daten für 2024: https://www.umweltbundesamt.de/themen/finale-daten-fuer-2024-emissionen-um-drei-prozent
- Destatis, Erwerbstätige 2024: https://www.destatis.de/DE/Presse/Pressemitteilungen/2025/01/PD25_001_13321.html
