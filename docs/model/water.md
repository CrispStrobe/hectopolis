# Water and runoff

Code: `packages/stadtbau_sim/lib/src/model/water.dart`. Parameters: `water.*`
and `tiles.*.perviousCurveNumber`, `tiles.*.sealing`. Task T-503.

## Model

The SCS (NRCS) curve number method, in millimetres.

Each cell has a sealed fraction (`sealing`) and an unsealed one with its own
curve number (`perviousCurveNumber`). They compose the way TR-55 does for
connected impervious area:

`CN = CN_pervious + sealing · (98 − CN_pervious)`

then the classical runoff equation:

```
S  = 25400 / CN − 254           maximum retention, mm
Ia = 0.2 · S                    initial abstraction
Q  = (P − Ia)² / (P − Ia + S)   for P > Ia, else Q = 0
```

`P` is the design storm, 22.1 mm.

## Where the numbers come from

Every one is from a published table, not chosen to feel right.

| Tile | Pervious CN | TR-55 Table 2-2 row, hydrologic soil group B |
|---|---|---|
| forest | 55 | woods, good condition |
| meadow | 58 | meadow, continuous grass, protected from grazing |
| park | 61 | open space, lawns, grass cover > 75 %, good condition |
| cropland | 78 | row crops, straight row, good condition |
| built tiles and road | 61 | the unsealed part is lawn in good condition; the sealed part is `sealing` |
| connected impervious | 98 | TR-55 connected impervious area |

The design storm is **22.1 mm**: KOSTRA-DWD-2020, grid field Spalte 118 /
Zeile 81 (`INDEX_RC 081118`), duration 60 min, return period 5 a. A five-year
hour is the ordinary heavy shower a drainage system is expected to cope with,
not a disaster — which is the right question for a planning game. The same
table gives 14.4 mm for a yearly hour and 40.2 mm for a hundred-year one, so a
scenario can pick its own severity through `paramOverrides`.

That choice of storm is why woodland barely responds: at CN 55 the initial
abstraction is close to 22 mm, so almost nothing leaves the surface. Sealing
the same ground is what creates runoff, and that is the lesson the tile is
there to teach.

## Retention

Open water takes runoff rather than shedding it. Each water cell distributes
`retentionMmPerCell` among the runoff-producing cells within
`retentionRadiusTiles`, in equal shares.

This is **storage, not routing**. Nothing here knows which way the ground
slopes, so water does not flow downhill, does not accumulate along a path, and
a pond helps its neighbours regardless of whether they are above or below it.
A real model would need a flow direction per cell and an accumulation pass.

## Reported, not scored

`meanRunoffMm` and `floodRiskCells` are on the fields, and the tile inspector
can show a cell's runoff. There is deliberately **no 0–100 flood indicator
yet**: adding an eleventh indicator changes every level's goal set and the
scoring surface, which should be a deliberate design decision rather than a
side effect of landing the model. The same call was made for night noise.

## Limits and next steps

- One design storm, one soil group (B). No per-level soil, no antecedent
  moisture condition, no seasonal variation — a frozen or saturated ground
  behaves like a dry one.
- Storage without routing, as above.
- Wetland is listed in T-502 and does not exist yet; when it does it belongs in
  the retention set beside water.
- No damage or cost: runoff is reported as depth, not as euros.

## References

- USDA NRCS, *Urban Hydrology for Small Watersheds*, Technical Release 55
  (TR-55), 2nd ed. 1986 — Table 2-2 curve numbers, the connected impervious
  composite, and the runoff equation. US government work, public domain.
- USACE HEC-HMS Technical Reference Manual, CN tables (the tabulation checked
  against here)
- KOSTRA-DWD-2020, Deutscher Wetterdienst — design rainfall depths
  (doi:10.5676/DWD/KOSTRA-DWD-2020)
