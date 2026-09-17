# Seasons

Code: `packages/stadtbau_sim/lib/src/params.dart` (`SeasonParams`) and
`model/heat.dart`. Parameters: `seasons.*` in `data/params/tiles.json`.
Task T-506.

## Model

A tick is one month and tick 0 is January, so the month is `tick % 12` and the
cycle needs no state of its own — the simulation stays deterministic and a
replay lands in the same season it did before.

Two monthly factor series, each twelve values:

| Series | Acts on | Why it is seasonal |
|---|---|---|
| `growth` | the ETI term of cooling capacity | vegetation transpires through the growing season and barely at all in winter |
| `heat` | `uhiMaxC` | the urban heat island is a summer phenomenon |

`amplitude` scales the **departure from the annual mean**, not the factor:

`factor(month) = 1 + (monthly[month] − 1) · amplitude`

So `amplitude = 0` gives 1.0 in every month and reproduces the season-free
model exactly, and a scenario can damp the year through `paramOverrides`
without flattening the world to nothing.

## Both series average exactly 1.0

This is the property that let seasons ship without re-tuning a single
scenario. A season **redistributes within a year**; it does not add or remove
warmth over one. Every level goal is evaluated after whole years of play, so
the totals land where they did before seasons existed — and all five level
solution tests passed unchanged.

The monthly numbers are normalised to make that exact rather than approximate.
A first draft averaged 0.900 and 0.908 while its `source` field claimed 1.0; a
test now asserts the mean, so the claim and the numbers cannot drift apart.

## What acts, and what does not

Shade and albedo are properties of the surface, so they do not move with the
month — only evapotranspiration does. Noise, air, access and the commute model
are untouched.

**Crop yield** is represented through `growth` acting on cropland's
evapotranspiration, which is what a bare winter field and a standing summer
crop differ by in this model. There is no economic yield term: cropland earns
through `jobsPerHa` like any other tile, and making jobs seasonal would churn
the commute and traffic solution every month for an effect the player cannot
act on. If seasonal farm income is wanted, it belongs in the economy model
with its own source, not here.

## Limits and next steps

- One climate for every scenario. No latitude, no per-level climate, no
  year-to-year variation.
- Heat waves are the summer end of a smooth cycle, not discrete events with
  their own frequency and duration.
- No snow, ice, or frozen ground: water and sealing behave the same all year.
- The visual side of the year — a seasonal tint on vegetation — is not wired
  up yet, though `growthAt(tick)` is what it should read.

## References

- DWD (Deutscher Wetterdienst): vegetation period in Germany, roughly April to
  October, and monthly climate normals
- DWD Klimareport and the urban heat island literature: UHI intensity peaks in
  summer and is weak in winter
- InVEST Urban Cooling model (see `heat.md`) for the ETI term this scales
