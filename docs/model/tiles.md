# Tile types and per-hectare parameters

Source of truth: `data/params/tiles.json` (every entry carries its own `source`).
This page explains the derivations and lists the primary references.

One tile is 1 ha (100 m × 100 m), the cell size of the Zensus 2022 grid.

## Biotope values (BKompV Anlage 2)

The Bundeskompensationsverordnung (BKompV, 2020) rates biotope types on a 0–24
scale (Anlage 2, column 3). The text is federal law and therefore public domain
(§ 5 UrhG). Codes used:

| Tile | BKompV code and type | Points | Game value / start |
|---|---|---|---|
| meadow | 34.08a.01 Intensiv genutztes frisches Dauergrünland → 34.07a.02 Artenreiche frische (Mäh-)Weide | 8 → 18 | 18, starts at 0.45 (≈ 8), reaches 18 after 120 months |
| cropland | 33.0x.03 Acker mit stark verarmter oder fehlender Segetalvegetation | 6 | 6 |
| forest | 43.07.05M Buchen(misch)wald frischer, basenreicher Standorte (mittlere Ausprägung) 16; 43.07.02M Eichen-Hainbuchenwald (mittlere Ausprägung) 20 | 16–20 | 18, starts at 0.4 (≈ 7, below 42.03.02 Vorwald = 13), reaches 18 after 240 months |
| water | 24.03b Sonstige natürliche mesotrophe Gewässer 19 | 19 | 16 for a constructed pond, starts at 0.5 |
| park | 51.06a.03 Intensiv gepflegte Parkanlage mit altem Baumbestand (51.06a.02.01 extensiv gepflegt = 16) | 13 | 13, starts at 0.5, reaches 13 after 240 months |
| housing_low | 53.01.03b Lockeres Einzelhausgebiet | 5 | 5 |
| housing_high | 53.01.16a.02 Sonstige Blockbebauung | 4 | 4 |
| commercial, industry | 53.01.14a Industrie- und Gewerbefläche inkl. typischen Freiräumen | 2 | 2 |
| road | 52.01.01a Versiegelter Verkehrs- und Betriebsweg | 0 | 0 |

Maturation: `value × (start + (1 − start) · min(1, age / recoveryMonths))`. The
BKompV distinguishes junge/mittlere/alte Ausprägung of woods; the recovery
times are estimates from compensation practice (BfN-Schriften 721) and should
be refined (open in T-103).

## Residents and jobs per hectare

- Living space per resident: 49.2 m² (Destatis, Fortschreibung des
  Wohngebäude- und Wohnungsbestands, Ende 2024).
- Floor-area ratios: BauNVO § 17 caps GFZ at 1.2 for WA/MI; detached-house
  areas are typically built at GFZ ≈ 0.4.
- housing_high: 1.2 × 10 000 m² × 0.8 (net of walls and stairs) = 9 600 m² ÷
  49.2 ≈ 195 residents per net hectare; ≈ 180 gross including local streets.
- housing_low: 0.4 × 10 000 × 0.8 = 3 200 m² ÷ 49.2 ≈ 65 net; × 0.7 gross ≈ 45.
- Jobs: commercial 100/ha and industry 45/ha follow BBSR Flächenkennwerte
  ranges (office/retail 80–150, manufacturing 30–60 employees per ha);
  ground-floor services in apartment blocks 15/ha. Initial estimates.

## Sealing, cooling parameters

Sealing follows Copernicus Imperviousness typical values per land use.
Shade, albedo and ETI are the InVEST Urban Cooling biophysical inputs
(canopy fraction, surface albedo, crop coefficient scaled 0–1); see
`heat.md`.

## Noise emission

See `noise.md`. Tile values are L_eq at the tile boundary (50 m from the
centre): road 60 dB(A) per 100 m segment at 10 000 vehicles/day, industry 65,
commercial 58, apartment blocks 50, detached housing 45. The TA Lärm daytime
limits (WA 55, MI 60, GE 65, GI 70 dB(A)) anchor the scale.

## Costs and maintenance

Build costs are development costs borne by the municipality in the game
(Erschließung, park construction, afforestation), in k€ per hectare. All are
initial estimates; sources to be added per task T-103.

## CO₂ per hectare

Forest −10 t/ha/a (Thünen, Bundeswaldinventur, growing stands), grassland
−1, cropland +1.5 (incl. N₂O), buildings by heating per resident (UBA), industry
+400 t/ha/a for 45 jobs. Traffic CO₂ is computed from car-km (0.15 kg/km, UBA
fleet average). Initial estimates.

## References

- BKompV Anlage 2: https://www.gesetze-im-internet.de/bkompv/anlage_2.html
- BfN-Schriften 721, Kartieranleitung für die Biotoptypen nach Anlage 2 BKompV
- Destatis, Wohnfläche je Einwohner: https://www.destatis.de/DE/Presse/Pressemitteilungen/2025/09/PD25_336_31231.html
- BauNVO § 17: https://www.gesetze-im-internet.de/baunvo/__17.html
- Copernicus Land Monitoring Service, Imperviousness
- InVEST User Guide, Urban Cooling Model

## The six tiles added by T-502 (2026-09-17)

`wetland`, `solar_field`, `mixed_use`, `school`, `tram_stop`, `cycle_path`,
taking the table from ten types to sixteen.

Sources follow the convention already in `tiles.json`: a real citation where
one exists (BKompV Anlage 2, InVEST Urban Cooling, TR-55 Table 2-2), and an
explicit `design:` or `initial estimate` where the value is an interpolation
between tiles that are already calibrated. Nothing is presented as sourced
that is not.

### One value is unlike the others

`solar_field.co2PerHaYear` is **−266 t/ha/yr**, derived rather than estimated:
German ground-mount PV occupies about 1.4 ha per MWp, so a hectare is roughly
0.7 MWp; at about 1000 kWh/kWp/yr that is 700 MWh/ha/yr; at the UBA grid
emission factor of about 380 g CO₂/kWh that displaces 266 t/ha/yr.

That is an order of magnitude larger than any other figure in the table —
industry emits 400, forest absorbs 10 — and it is an **avoided** emission
rather than an emitted one, sitting in a column that otherwise holds emissions.
Both facts are true to the physics, and both have a consequence worth stating
plainly: **a solar field is by far the strongest climate lever in the game, and
tiling them would make the climate indicator easy to satisfy.**

It was left at the derived value rather than quietly scaled, because the
alternative is a number that is wrong about the world in order to be
convenient. Whether the game wants it capped, rescaled, or balanced by land
cost is a design decision; a scenario can override it through
`paramOverrides`. No shipped level allows the tile yet, so nothing existing is
affected.

### Wetland closes a gap left by T-503

`model/water.dart` treats wetland as retention alongside open water. T-503
shipped with only water in that set because wetland did not exist; the
retention list was waiting for this tile.

### What these tiles do not do yet

`tram_stop` and `cycle_path` carry a placeholder negative `co2PerHaYear` and
otherwise act only through their land cover — their sealing, noise and biotope
value. **The point of both is the car traffic they replace, and that belongs in
the commute model**, which currently derives mode share from distance alone
(`commute.modeShareByDistance`, MiD 2017). Until a stop or a path can shift
mode share for the cells around it, these two tiles are honest about their
land cover and silent about their purpose. That is the next piece of work, and
it needs its own sources.
