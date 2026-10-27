# Stocks: population, budget, CO₂

Code: `packages/stadtbau_sim/lib/src/model/stocks.dart`. Parameters: `economy.*`,
`tiles.*.buildCostKEur`, `maintenanceKEurYear`, `co2PerHaYear`.

## Attractiveness

Per residential cell, from the fields (weights in `economy.attractivenessWeights`):

`a_i = 0.25 · noise + 0.20 · air + 0.15 · green + 0.15 · retail + 0.15 · jobs + 0.10 · heat`

with noise score `clamp((65 − L_i) / 10)`, air `AQI_i / 100`, heat
`1 − ΔT_i / UHI_max`, the three access scores as computed. Cells without a
main road within 300 m: × 0.7.

## Population (per month)

`P_i ← P_i + (cap_i − P_i) · a_i · 0.08 − P_i · (1 − a_i) · 0.03`

New housing fills within about two years at high attractiveness; unattractive
housing empties slowly.

## Municipal budget (per month, k€)

Revenue = residents × (550 + 180) / 12 + filled jobs × 2 100 / 12, in €:

- 550 €/resident/a: Gemeindeanteil Einkommensteuer 46.1 bn € (2024) ÷ 83.6 M
  (Destatis PM 126/2025).
- 180 €/resident/a: Grundsteuer B 15.1 bn € (2023) ÷ 84 M (Destatis PM N006/2025).
- 2 100 €/job/a: Gewerbesteuer 75.1 bn € (2023) ÷ ≈ 35 M sozialversicherungs-
  pflichtig Beschäftigte (Destatis PM 356/2024).

Costs = Σ maintenance per tile / 12 (road 10 k€/ha/a: 1.5–3 €/m² Fahrbahn plus
Beleuchtung, Reinigung, Winterdienst; park 20; others 0–4) plus
one-off build and demolition costs at placement (demolition 250 k€ per built
hectare, from the funding cap of Saxony's FRL Städtebauliche Erneuerung,
110 €/m² of living space; see `tiles.json`). Starting budget 25 M€.

## CO₂ balance (t/a)

Σ tile `co2PerHaYear` (residential scaled by occupancy) + car-km × 0.15 kg.
See `tiles.md` for the per-tile values.

## References

- Destatis Pressemitteilungen 356/2024 (Gewerbesteuer), N006/2025
  (Grundsteuer), 126/2025 (kommunale Finanzen 2024)
- Destatis, Fachserie 14 Reihe 10.1 (Realsteuervergleich)
