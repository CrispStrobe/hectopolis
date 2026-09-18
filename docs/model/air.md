# Air pollution

Code: `packages/stadtbau_sim/lib/src/model/air.dart`. Parameters: `air.*` and
`tiles.*.airEmission`, `tiles.*.airSink`.

## Model

Relative emission rates `E` per tile (road 1.0 at 10 000 vehicles/day, industry
3.0, commercial 0.6, apartment blocks 0.3, detached housing 0.15, cropland 0.05).
Road emission scales linearly with traffic (EMEP/EEA road transport emissions ∝
vehicle-km).

Concentration at cell `i`:

`C_i = Σ_s E_s · k(d_si) / K`, `k(d) = exp(−d / 300 m)`, `K = Σ_k k(d_k)` over the
6-tile neighbourhood including the centre.

The normalisation `K` makes a uniform field of emitters produce `C = E`, and a
single emitter dilute with distance.

## Wind (T-501)

With `air.windSpeedMs = 0` the kernel is isotropic and everything above holds
unchanged. That is the shipped default, so a scenario opts into wind through
`paramOverrides` — the way `04_budget` does, with the prevailing
south-westerly of the German lowlands.

With wind, the same exponential is applied to a distance measured in a
stretched frame. For an offset `d` from source to receiver, with unit vector
`ŵ` pointing the way the wind blows:

- along-wind `a = d · ŵ`, crosswind `c = |d × ŵ|`
- `s = 1 + windSpeedMs · windStretchPerMs` (the downwind stretch)
- `a' = a / s` downwind (`a ≥ 0`), `a' = a · s` upwind
- `c' = c · √s`
- `k = exp(−√(a'² + c'²) / L)`

So the plume reaches further downwind, dies quickly upwind, and narrows
across. `K` is recomputed for the same kernel, so the wind redistributes the
emission rather than adding or removing any: a uniform field of emitters still
gives `C = E`, and the total over a single plume changes only by what the
stretch pushes past the 6-tile radius.

**This is a stand-in for a Gaussian plume, not a solution of one.** A real
Gaussian plume has σ_y and σ_z growing with downwind distance under a Pasquill
stability class, a release height, and a ground-reflection term; concentration
falls as `1/(u·σ_y·σ_z)` rather than exponentially. What is kept here is the
part that changes decisions on a 100 m grid: put the dirty thing downwind of
the homes and the homes stay cleaner. `windStretchPerMs = 0.35` puts a 3 m/s
wind at roughly twice the downwind reach of calm, which is the order of
magnitude a screening plume gives over a few hundred metres.

Direction follows the meteorological convention — `windFromDegrees` is where
the wind comes **from**, 0 = north, 90 = east — so the value can be read
straight off a wind rose. The plume travels the opposite way.

### Limits

- One direction, constant. No wind rose with a frequency distribution, no
  calm-hours fraction, no seasonal variation.
- No stability class, no plume rise, no building downwash: a tall stack and a
  ground-level road disperse identically.
- The 6-tile cut-off is unchanged, so a strong wind loses a little material
  off the downwind edge of the kernel.

Deposition: `C_i ← C_i · (1 − mean sink of the 3-tile neighbourhood)`, with sink
coefficients forest 0.20, park 0.10, meadow 0.05 (magnitudes after Nowak et al.
2006, i-Tree: urban trees remove a few percent of local PM and NO₂; the game
uses a larger local effect for legibility).

Index: `AQI_i = 100 · exp(−C_i / 1.0)`.

## Where the emission numbers come from (T-103)

They are relative, with a main road at 10 000 vehicles a day fixed at 1.0, so
what has to hold is the *ordering and the ratios*, not an absolute rate. UBA's
2024 emission data sets them:

- **NOx 810 kt**, of which transport is almost 36 % — by far the largest single
  source — and energy plus industry together about 42 %.
- **PM2.5 74 kt**, of which nearly 60 % is combustion, with the largest shares
  from households and small consumers and from road traffic including
  abrasion.

So road first, household heating a real but smaller term, agriculture small per
hectare because it is spread over 11.66 M ha. That is the shape the table has.

**industry 3.0 is deliberately below what the inventory implies.** Per hectare,
national industry emissions against 45 jobs would put an industrial hectare
around ten times a road hectare, not three. The reason it is not modelled that
way is in the Limits above: **this model has no stack height and no plume
rise**, so a tall chimney and a kerbside exhaust disperse identically. Giving
industry its inventory strength at ground level would poison its neighbours in
a way real industrial estates, whose emissions leave at 30–80 m, do not. 3.0 is
the ground-level equivalent, and the calibration run confirms it: the
industrial-park archetype lands at an air index of 87.

The deposition coefficients are design values anchored on Nowak et al. 2006,
and the amplification is deliberate and already stated above: real urban trees
remove a few percent of local PM and NO₂, and the game uses a larger local
effect so that planting a wood is visible on a 100 m grid. They are labelled
`design, anchored on…` rather than "initial estimate", because no further
reading will settle a number the game has chosen to exaggerate on purpose.

`air.decayLengthM = 300` and `air.sinkRadiusTiles = 3` are the same kind of
value: the decay length says a source is at 37 % after 300 m and 14 % after
600 m, which on a 100 m grid is the decision that matters — three cells of
distance more than halve the load twice over.

## Calibration (T-114)

| Archetype | Mean resident index |
|---|---|
| village | ≈ 92 |
| suburb | ≈ 89 |
| dense quarter | ≈ 80 |
| mixed town with industry | ≈ 73 |
| inside an industrial area | ≈ 5 |

## References

- UBA, Stickstoffoxid-Emissionen: https://www.umweltbundesamt.de/daten/luft/luftschadstoff-emissionen-in-deutschland/stickstoffoxid-emissionen
- UBA, Emission von Feinstaub PM2,5: https://www.umweltbundesamt.de/daten/umweltzustand-trends/luft/luftschadstoff-emissionen-in-deutschland/emission-von-feinstaub-der-partikelgroesse-pm25
- EMEP/EEA air pollutant emission inventory guidebook 2023, chapters 1.A.3.b
  (road transport), 1.A.4 (small combustion), 2 (industrial processes)
- Nowak, Crane, Stevens (2006): Air pollution removal by urban trees and shrubs
  in the United States. Urban Forestry & Urban Greening 4, 115–123.
- Umweltbundesamt, Luftschadstoff-Emissionen in Deutschland
- Pasquill (1961); Gifford (1961): plume dispersion coefficients by stability class
- Stockie (2011), *The mathematics of atmospheric dispersion modeling*, SIAM Review 53(2)
