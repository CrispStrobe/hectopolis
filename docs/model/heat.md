# Urban heat

Code: `packages/stadtbau_sim/lib/src/model/heat.dart`. Parameters: `heat.*` and
`tiles.*.shade`, `albedo`, `eti`.

## Model (after InVEST Urban Cooling)

Cooling capacity per land cover:

`CC = 0.6 · shade + 0.2 · albedo + 0.2 · ETI`

(shade = canopy fraction ≥ 2 m, albedo = surface albedo, ETI = crop coefficient
scaled 0–1; weights are the InVEST recommended defaults).

Green patches (nature and urban green, 8-connected) of at least 2 ha cool
their surroundings: within `d_cool` (InVEST default 450 m; game: 3 tiles) the
heat mitigation index is

`HM_i = max(CC_i, max_j CC_j · (1 − d_ij / (d_cool + 1)))` over green cells `j`
of qualifying patches.

InVEST then writes `T_i = T_rural + UHI_max · (1 − HM_i)`. Because the rural
reference land cover itself has `HM ≈ 0.2–0.3`, the game rescales so that the
base terrain (meadow) has ΔT = 0 and the least cooling land cover (road) has
ΔT = UHI_max:

`ΔT_i = UHI_max · clamp((CC_meadow − HM_i) / (CC_meadow − CC_min), 0, 1)`

with `UHI_max = 3 °C` (user input in InVEST; DWD reports 2–4 K for German
mid-size cities).

## The ceiling moves with the month, and so must anything that divides by it

`UHI_max` in that formula is not the parameter `heat.uhiMaxC`. It is that
parameter times the month's heat factor (`docs/model/seasons.md`), which runs
from 0.275 in January to 1.927 in July. A dense quarter therefore reaches
about 4.1 K in July against a `uhiMaxC` of 3.0.

**`computeHeat` publishes the ceiling it used as `fields.uhiMaxNowC`, and
everything that turns a ΔT into a 0–1 score divides by that** — the climate and
recreation indicators, and the heat term of residential attractiveness, all
through `fields.heatScoreOf(ΔT)`.

They used to divide by `heat.uhiMaxC` instead, and the consequence was not
subtle: `1 − 4.1/3.0` clamps to zero, so **for three months a year the climate
indicator could not tell a dense quarter with sixteen hectares of park from one
with none** — both scored 53.8 — and the heat term of attractiveness went to
zero for every residential cell regardless of what had been built. With the
month's own ceiling the same comparison reads 64.0 against 62.5, and
recreation 25.7 against 8.7.

Summer still costs a city points, and for the right reason: open country
transpires hardest in the growing season, so a built quarter falls further
behind the rural reference in July than in January. That signal lives in the
`growth` factor, in the numerator, where it belongs. What is gone is the part
that came from measuring a summer number against an annual yardstick.

The map's terrain tint (`_warmth` in `map_view.dart`) is the deliberate
exception: it keeps the absolute scale, because a tint should say "this place
is hot right now" and a July city ought to look hotter than the same city in
January.

## Calibration (T-114, re-run 2026-09-18)

Mean resident ΔT **as an annual mean**: village 0.6 °C, suburb 0.8 °C, dense
quarter 1.7 °C. Forest and water 0 °C. July peaks: village 1.6, suburb 2.1,
dense quarter 3.7 — the top of the DWD 2–4 K band, for a hectare-dense quarter
of apartment blocks.

The older figures in this file (dense quarter 1.6 °C) were recorded before
seasons existed and are annual means, which is why the annual column
reproduces them.

## References

- InVEST User Guide, Urban Cooling Model:
  https://storage.googleapis.com/releases.naturalcapitalproject.org/invest-userguide/latest/en/urban_cooling_model.html
- Zawadzka et al. (2021): A spatially explicit approach to simulate urban heat
  mitigation with InVEST (v3.8.0). Geosci. Model Dev. 14, 3521–3537.
