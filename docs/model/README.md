# Model documentation

These pages are published at <https://crispstrobe.github.io/hectopolis/docs/>
(`tools/build_docs_site.dart`), with a generated
[Quellen page](https://crispstrobe.github.io/hectopolis/docs/quellen.html)
listing every law, standard and dataset the model uses.

One file per model component. Each file states the formula as implemented in
`packages/stadtbau_sim/lib/src/model/`, the parameters it reads from
`data/params/tiles.json`, and the sources for both. Values marked
"initial estimate" in the params file are open for verification (task T-103).

| Component | Code | Doc | Status |
|---|---|---|---|
| Tile types and per-hectare parameters | `params.dart` | `tiles.md` | written (T-103); recovery times and costs still estimates |
| Noise | `model/noise.dart` | `noise.md` | written (T-105) |
| Air pollution | `model/air.dart` | `air.md` | written (T-106) |
| Urban heat | `model/heat.dart` | `heat.md` | written (T-107) |
| Access (green, retail, jobs) | `model/access.dart` | `access.md` | written (T-108) |
| Habitat and biodiversity | `model/habitat.dart` | `biodiversity.md` | written (T-109) |
| Commuting and traffic | `model/commute.dart` | `commute.md` | written (T-110) |
| Stocks, budget, CO₂ | `model/stocks.dart` | `economy.md` | written (T-111) |
| Indicators | `indicators.dart` | `indicators.md` | written (T-112) |
| Calibration ranges | `tool/calibrate.dart` | `calibration.md` | written (T-114) |

## Summary of model v1

The grid cell is 1 ha (100 m × 100 m), matching the Zensus 2022 100 m grid.
Each tick is one month.

1. **Commuting** distributes workers to jobs with a gravity kernel, derives
   mode shares by distance (MiD 2017) and assigns car trips to road cells.
2. **Noise**: every emitting tile is a point source at −20 dB per distance
   decade from its boundary; roads are 100 m segments whose energetic sum
   yields the line-source behaviour of CNOSSOS-EU. Car trips are routed over
   the road network (shortest road path). Traffic scales road
   emission by 10·log10(Q/Q_ref). Forest/park cells on the path attenuate
   2 dB each, building rows 5 dB, capped at 20 dB. TA Lärm 55 dB(A) is the
   residential daytime limit used for scoring.
3. **Air**: emissions spread with a normalised exp(−d/300 m) kernel;
   vegetation in a 300 m neighbourhood removes a share (deposition after
   Nowak et al.).
4. **Heat**: InVEST Urban Cooling capacity CC = 0.6·shade + 0.2·albedo +
   0.2·ETI; green patches ≥ 2 ha cool within 300 m; ΔT rescaled so that
   meadow is the rural reference (0 °C) and road reaches UHI_max.
5. **Access**: green within 300 m (WHO), retail via Huff (λ = 2, 700 m),
   jobs via exp(−d/2 km) (local access; commuters choose jobs over
   exp(−d/10 km)).
6. **Habitat**: BKompV biotope value × maturity, InVEST Habitat Quality
   threat degradation, effective mesh size (Jaeger 2000) for connectivity,
   species-area exponent 0.3.
7. **Stocks**: population per cell moves toward capacity at a rate set by
   attractiveness (noise, air, green, retail, jobs, heat); municipal budget
   from Destatis per-resident and per-job tax averages minus maintenance;
   CO₂ from land use and car-km.

## Tracing a reading to its sources

`Simulation.sources(field, x, y)` takes one cell's reading apart into what
each source cell contributes, in the field's own terms and **before** any
cap. The map uses it to draw lines from the strongest sources to a selected
cell. It adds no model: each function sits next to the loop that computes the
field and repeats that loop for one receiving cell. `test/sources_test.dart`
rebuilds every field from its sources on every cell of every shipped level, in
January and in July.

| Field | A source's value | The reading, rebuilt |
|---|---|---|
| noise | sound energy 10^(L/10) after divergence and screening | 10·log10(background + Σ) |
| air | concentration before deposition | Σ, times the cell's deposition factor |
| heat | cooling capacity × distance weight, green patches ≥ 2 ha, where it beats the cell's own capacity | ΔT from max(own CC, best source) |
| green | green weight in reach | best + variety bonus, capped |
| retail | Huff-weighted floor area | Σ / reference supply, capped |
| jobs | jobs × exp(−d / 2 km) | Σ / reference jobs, capped |
| habitat | w_r · (1 − d / d_max) for each threat | Σ / 4, capped |

Before the cap is the point. Job access in a town is often at 1.0, and there
removing any single workplace changes nothing, because the others still fill
the reading. Comparing the field with and without each tile therefore cannot
tell an industrial estate from the houses next door; the uncapped
contributions can.

Traffic and attractiveness are not traceable this way. Traffic is routed
through the road network, and attractiveness is a weighted mix of the other
readings. For those two, the app removes each of the nearest sources in turn
and recomputes. That is a fair test only because neither field is capped in
practice.
