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

## Limits and next steps

- Day level only; night (L_night, WHO 40 dB) is task T-505.
- No wind, no ground effect, no reflections.
- Traffic depends on the commute model (`commute.md`).

## References

- Directive (EU) 2015/996 (CNOSSOS-EU), Annex II
- RLS-19 (Richtlinien für den Lärmschutz an Straßen), veröffentlicht als
  Verwaltungsvorschrift (BayMBl. 2021 Nr. 255)
- ISO 9613-2, Attenuation of sound during propagation outdoors
- TA Lärm (Technische Anleitung zum Schutz gegen Lärm), Nr. 6.1
