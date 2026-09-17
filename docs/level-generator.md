# Building a level from open data

Code: `tools/level_from_landcover.py`. Task T-303.

A level map is 24 × 24 or so hectares of Germany, and Germany is mapped. This
turns an open land-cover dataset into the `map` of a level JSON, so a scenario
can be a place that exists rather than a shape someone drew.

## What it needs

A GeoPackage or GeoJSON of land-cover polygons **in a metric CRS**. The tool
works in the data's own coordinates and never reprojects: one cell is 100 m in
whatever the file uses, which is right for UTM (EPSG:25832, what German open
data ships) and for LAEA (EPSG:3035, what Copernicus ships), and wrong for
degrees. It reads a GeoPackage with Python's own `sqlite3` — a GeoPackage is a
SQLite database and its geometry is WKB behind a short header — so there is no
GDAL, fiona or geopandas to install. `shapely` is used if it happens to be
importable and a pure-Python ray-caster stands in when it is not.

**Raw data never enters the repository.** It belongs in
`/mnt/storage/code/stadtbau/data` (see `CLAUDE.md`). What the repository gets
is the generated level, a few kilobytes of JSON, carrying the source notice
its licence requires.

## The dataset used so far

**LBM-DE2021**, the federal land-cover model (Landbedeckungsmodell für
Deutschland, BKG). 2 GB zipped, one 5.9 GB GeoPackage covering Germany:

```
https://daten.gdz.bkg.bund.de/produkte/dlm/lbm-de_2021/aktuell/lbm-de2021.utm32s.gpkg.zip
```

It is **CC BY 4.0**, which is on the allowed data-licence list in
`CONTRIBUTING.md`. The licence terms that ship with it
(`dokumentation/nutzungsbedingungen_lbm-de2021.pdf`) require a visible source
notice *and* a notice of modification, so the generator writes both into the
level's `attribution` field:

> © BKG (2026) CC BY 4.0 — Landbedeckungsmodell LBM-DE2021, sampled onto a
> 1 ha grid and reduced to 16 tile types by Hectopolis. Datenquellen:
> https://sgx.geodatenzentrum.de/web_public/gdz/datenquellen/datenquellen_lbm-de2021.pdf

Sampling a 1 ha grid out of polygons and collapsing a 44-class nomenclature
into 16 tile types is plainly a modification, which is why it is stated rather
than implied. The notice appears wherever the level appears: the level select
screen shows it under the scenario, and the About screen lists the dataset.
The terms also ask that, on a web page, "BKG" link to
<https://www.bkg.bund.de> and "CC BY 4.0" to
<https://creativecommons.org/licenses/by/4.0/>; this page is that web page.

Copernicus Urban Atlas is the other obvious candidate and needs a CLMS login,
so it is not wired up; its 2018 nomenclature would work through
`--class-field code_2018 --mapping <file>`.

## How a class becomes a tile

Everything below is in the `lbm-de2021` profile in the script, with the
documentation section it comes from.

**Base: the CLC21 code** (CORINE Land Cover level 3, Anlage 2 of the product
documentation). Forest classes become forest, 411 Sümpfe and 412 Torfmoore
become wetland, 511/512 become water, 211 Ackerland becomes cropland, 231
Wiesen und Weiden becomes meadow, 141 and 142 become park.

**CLC 121 is split by `LN_AKT`** (Anlage 1). CLC puts industry, retail,
services and public institutions in one class; the game has separate tiles.
`N120 Produktion` becomes industry, `N121 Öffentlichkeit` (Handel &
Dienstleistung) becomes commercial, harbour and airport become industry.

**CLC 112 is split by `SIE_AKT`**, the sealed share from satellite
classification. `tiles.json` puts `housing_low` at 0.45 sealed and
`housing_high` at 0.75, so the cut is the midpoint, 60 %. In this dataset
CLC 112 runs 0–80 % with a mean of 43 %, so most of it stays low density,
which is what "nicht durchgängig städtische Prägung" means.

**`ZUS_AKT` containing `S` becomes solar_field.** The column is a
comma-separated list with a trailing comma (`"O,"`, `"F,O,"`, `"M,W,"`), not a
single flag, so it has to be split — an equality test against `"S"` matches
none of the 7 277 solar polygons in the dataset and fails silently. Without
this rule they would all be industry, since they are CLC 121 with `LN_AKT`
`N120`.

**Three tiles are not derivable and are placed by hand**: `tram_stop`,
`cycle_path` and `mixed_use`. Land cover records what the ground is, not
whether a tram stops on it, and CLC has no mixed-use class. `school` is not
separable either: it falls under `N121` with every other public institution.

## Cells, not points

A cell is decided by the majority of a 5 × 5 subgrid (20 m samples), not by
its centre. Two covers need more than a majority:

- A main road is about 20 m wide and a river about 30 m, so **neither ever
  wins a hectare on area** and both come out as disconnected specks. A cell
  that is at least `--linear-share` (default 0.12) road, or that much water,
  becomes that tile regardless. On the Tübingen extract this moved water from
  1.3 % to 5.0 % of cells and turned the Neckar from flecks into a channel.
- This overstates their area on purpose. `tiles.road` already models a 100 m
  segment with its verges; a river that does not connect drains nothing; and
  connectivity is what the traffic and runoff models actually read. Road wins
  over water where both qualify, which is a bridge.

A class the profile does not know is **not** quietly turned into meadow: the
tool lists the unmapped classes with sample counts and exits non-zero.

## Cost of a large map

The simulation is superlinear in cells, measured on the `tuebingen` extract:

| Grid | Cells | Per tick |
|---|---|---|
| 16 × 16 (the hand-built levels) | 256 | 3.3 ms |
| 24 × 24 (`tuebingen`) | 576 | 10–12 ms |
| 32 × 32 | 1024 | 22–26 ms |

At 10× speed a tick has about 100 ms, so 24 × 24 is comfortable and 32 × 32 is
not, on a phone. The shipped level is 24 × 24 for that reason, not because the
generator cannot do more.

## Recipe

```bash
# 1. the extract, once, outside the repository
cd /mnt/storage/code/stadtbau/data/lbm-de
curl -O https://daten.gdz.bkg.bund.de/produkte/dlm/lbm-de_2021/aktuell/lbm-de2021.utm32s.gpkg.zip
curl -O https://daten.gdz.bkg.bund.de/produkte/dlm/lbm-de_2021/aktuell/lbm-de2021.utm32s.gpkg.zip.md5
md5sum -c lbm-de2021.utm32s.gpkg.zip.md5
unzip lbm-de2021.utm32s.gpkg.zip

# 2. look at a window before committing to it (--origin is the south-west
#    corner in EPSG:25832 metres; epsg.io converts a place to it)
tools/level_from_landcover.py --input .../LBMDE.gpkg --profile lbm-de2021 \
    --origin 503053,5373078 --size 24x24 --id mytown --preview

# 3. write it
tools/level_from_landcover.py --input .../LBMDE.gpkg --profile lbm-de2021 \
    --origin 503053,5373078 --size 24x24 --id mytown --order 7 \
    --budget 34000 --months 120 --out data/levels/07_mytown.json
```

Then do the part the tool cannot:

1. **Author the goals.** The generated file gets one population goal derived
   from the housing the extract contains, which is a placeholder: on a town
   that already exists it is met at month 0. Run the level, read the starting
   indicators, and set goals that ask for a change.
2. **Set the budget against the tile allowance**, not by feel. The `tuebingen`
   allowance costs 28 950 k€ at the build costs in `tiles.json`, so a smaller
   budget would make the level about waiting for tax revenue.
3. **Add a solution to `level_solutions_test.dart`.** Every built-in level
   must be winnable with three stars by a written plan. This is not a
   formality: the first goal set for `tuebingen` asked for biodiversity 50,
   and the full green allowance reaches 39 — the level was unwinnable and only
   the test said so.
4. **Name it in both ARB files** (`levelTitle`, `levelDescription`). ICU
   `select` has no exhaustiveness check, so a missing branch shows as the
   fallback rather than an error.
5. Regenerate the mirror: `dart run tools/gen_params.dart`.

## What the model rewards, which is not what you would guess

Worth knowing before authoring goals. Three plans were measured on the same
level with the same allowance of 40 park, 40 forest, 15 wetland:

| Plan | Biodiversity | Recreation | Climate |
|---|---|---|---|
| Green over the industrial estate and sealed cells near homes | 39 | 93 | 87 |
| One large connected wood grown from the existing forest | 49 | 75 | 79 |
| A corridor along the river as a compromise | 37 | 78 | 78 |

Biodiversity responds most to **what is removed**, because industry and roads
are threat sources in the InVEST habitat-quality term, and connectivity
(effective mesh size) rewards one block over scattered patches. Recreation and
heat respond to green being **near people**. The two pull in opposite
directions, and the compromise shape is worse at both than either specialist —
which is the lesson this level is for.

## References

- Landbedeckungsmodell für Deutschland LBM-DE2021, Bundesamt für Kartographie
  und Geodäsie, CC BY 4.0. Product documentation, Anlage 1 (LB/LN classes),
  Anlage 2 (CLC classes), Tabelle 2 (attributes).
- Nutzungsbedingungen und Quellenvermerk LBM-DE2021 (the CC BY 4.0 terms and
  the prescribed notice).
- CORINE Land Cover nomenclature, level 3.
- OGC GeoPackage Encoding Standard 12-128r19, §2.1.3 (the geometry header).
