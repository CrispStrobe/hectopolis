# Noise

Code: `packages/stadtbau_sim/lib/src/model/noise.dart`. Parameters: `noise.*` and
`tiles.*.noiseEmissionDb` in `data/params/tiles.json`.

## Model

1. **Sources.** Every tile with `noiseEmissionDb > 0` is a point/area source
   with level `E` at the tile boundary (50 m from the centre). Roads are the
   100 m segments that CNOSSOS-EU uses to discretise a line source; their
   emission scales with traffic:

   `E_road = E_ref + 10 · log10(Q / Q_ref)`, `Q_ref = 10 000 vehicles/day`
   (RLS-19: emission ∝ 10·log10 of the traffic volume).

2. **Geometric divergence.** `L(d) = E − 20 · log10(max(d, 50 m) / 50 m)`,
   i.e. −6 dB per doubling (ISO 9613-2 point source). The energetic sum of
   consecutive road segments reproduces the −3 dB per doubling of a line.

3. **Path attenuation.** Cells strictly between source and receiver on the
   Bresenham line attenuate: forest or park −2 dB per cell (ISO 9613-2 Table
   A.2 foliage attenuation, ≈ 10 dB over 200 m), dense buildings (apartment
   blocks, commercial, industry) −5 dB per cell (screening, CNOSSOS-EU
   diffraction order of magnitude), capped at 20 dB.

   The path is **reciprocal**: the cells between two tiles are the same
   whichever of them is the source, so a screening wall attenuates equally in
   both directions. Bresenham breaks ties towards its start point and so
   disagrees with itself on 56 of the 196 offsets within the 8-tile radius;
   `Offsets.pathOffsets` therefore traces each path from the canonical end of
   its axis and mirrors it for the other. Before 2026-09-15 the two directions
   could differ by up to ≈ 0.7 dB behind a dense screen.

4. **Summation.** `L_i = 10 · log10(10^(L_bg/10) + Σ_s 10^(L_s,i/10))` with a
   rural background of 35 dB(A). Sources beyond 8 tiles (800 m) are ignored.

## Calibration

A straight road with 10 000 vehicles/day gives ≈ 58 dB(A) at 100 m and
≈ 55 dB(A) at 200 m, matching the RLS-19 order of magnitude for 50 km/h urban
roads. TA Lärm daytime limits: WA 55, MI 60, GE 65, GI 70 dB(A). Scoring maps
55 → 1 and 65 → 0 per resident.

## Night level (T-505)

The same sources, the same geometry and the same path attenuation are run a
second time with a night emission, in one pass — only the source term differs,
so the expensive half of the work is shared:

`E_night = E_day − tiles.*.noiseNightReductionDb`

Roads drop 6.5 dB. That is derived, not assumed: German urban roads carry about
10% of their daily traffic in the 8 night hours against 90% in the 16 day
hours, so the hourly rate at night is 0.22 of the day rate and
`10·log10(0.22) ≈ −6.5 dB`. The other reductions are design values, labelled as
such in the parameter file: shops 8 dB (closed, no deliveries), homes 5 dB,
industry 5 dB (a compliant plant throttles at night rather than stopping,
because TA Lärm regulates night separately).

### What counts as too loud

Two different WHO documents are involved, and they are often conflated:

| Source | Value | What it is |
|---|---|---|
| WHO *Night Noise Guidelines for Europe* (2009) | **40 dB** L_night | guideline value, and the lowest observed adverse effect level |
| WHO *Night Noise Guidelines for Europe* (2009) | **55 dB** L_night | interim target; above it cardiovascular effects become the major public health concern |
| WHO *Environmental Noise Guidelines for the European Region* (2018) | **45 dB** L_night | strong recommendation for **road traffic** (L_den 53 dB) |

The 2018 guidelines' 40 dB figure is for **aircraft**, not road traffic; rail
is 44 dB. Since this game's night noise is overwhelmingly road traffic, the
45 dB road-traffic recommendation is the one the indicators use, with the 2009
figures kept as the lower and upper anchors.

### Reported, not scored

`meanNightNoiseDb` and the resident-weighted shares above 45 dB and 55 dB are
on the indicator snapshot, but the 0–100 noise indicator still scores the day
level alone. Folding night into the score would have silently rebalanced every
existing scenario and goal; the night figures are shown instead, where the
player can act on them.

An exposure-response curve for percent highly sleep disturbed (%HSD) was
deliberately **not** implemented. The WHO 2018 polynomial exists, but every
number in this project carries a citation, and the coefficients could not be
read from a primary source here — the journal pages are behind a CAPTCHA and
the WHO PDF did not extract. A share above a published threshold is verifiable
from the guideline text itself; a polynomial from memory is not.

## Limits and next steps

- L_night is derived from the same emission model rather than measured
  separately: no night-specific speed limits, no HGV share, no rail.
- No %HSD or annoyance curve (see above).
- Health effects are reported as exposure shares, not modelled outcomes.
- No wind, no ground effect, no reflections.
- Traffic depends on the commute model (`commute.md`).

## References

- WHO, *Environmental Noise Guidelines for the European Region* (2018)
- WHO, *Night Noise Guidelines for Europe* (2009)
- Directive (EU) 2015/996 (CNOSSOS-EU), Annex II
- RLS-19 (Richtlinien für den Lärmschutz an Straßen), veröffentlicht als
  Verwaltungsvorschrift (BayMBl. 2021 Nr. 255)
- ISO 9613-2, Attenuation of sound during propagation outdoors
- TA Lärm (Technische Anleitung zum Schutz gegen Lärm), Nr. 6.1
