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
   jobs via exp(−d/2 km).
6. **Habitat**: BKompV biotope value × maturity, InVEST Habitat Quality
   threat degradation, effective mesh size (Jaeger 2000) for connectivity,
   species-area exponent 0.3.
7. **Stocks**: population per cell moves toward capacity at a rate set by
   attractiveness (noise, air, green, retail, jobs, heat); municipal budget
   from Destatis per-resident and per-job tax averages minus maintenance;
   CO₂ from land use and car-km.
