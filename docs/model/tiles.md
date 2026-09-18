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
- Jobs (verified in T-103): German land-demand forecasting works the other way
  round, in square metres of net building land per employee — the GIFPRO
  Flächenkennziffer, used in every municipal Gewerbeflächenkonzept. Inverted it
  gives jobs per hectare directly, and it lands on both stored values:

  | Wirtschaftsgruppe | m²/Beschäftigten | Jobs/ha |
  |---|---|---|
  | GIFPRO standard model | 225 | 44 |
  | Verarbeitendes Gewerbe (Vallee et al. 2012) | 250 | 40 |
  | Emissionsintensives verarbeitendes Gewerbe | 200 | 50 |
  | Emissionsarmes verarbeitendes Gewerbe | 150 | 67 |
  | Logistik, Lagerhaltung | 250–300 | 33–40 |
  | Einzelhandel, Kfz-Handel | 250 | 40 |
  | Wirtschaftsnahe Dienstleistungen | 100 | **100** |
  | Sonstige Dienstleistungen | 50 | 200 |

  **industry 45** is the standard model rounded; **commercial 100** is business
  services exactly, with retail below it and other services above, which is the
  mixture the tile stands for. The earlier attribution to "BBSR Flächenkennwerte"
  was not traceable to a BBSR publication and has been replaced.

  The Kennziffer is *net* building land, so a gross hectare including internal
  access roads carries slightly fewer jobs than the table says. The tile is one
  hectare of land use, and the rounding absorbs it.

- housing_high 15/ha and housing_low 3/ha (ground-floor services, home offices
  and local trades) remain estimates: the Kennziffer method covers commercial
  land, not jobs incidental to housing.

## Sealing (Umweltatlas Berlin 01.02, verified in T-103)

Sealing was an estimate anchored on the BauNVO GRZ ceilings until T-103. A GRZ
is a legal maximum for *buildings on a plot*, not a measurement of what is
actually impervious across a whole hectare, so it was the wrong kind of number
even where it happened to be close.

Berlin measures the sealed fraction of every block from satellite imagery,
building outlines and street-survey data, and publishes the mean per land-use
type. It is the only German dataset that measures sealing *by use* rather than
assuming it, so the built tiles now take their values from it: Umweltatlas
Berlin, Karte 01.02 Versiegelung 2021, Tabelle 19 (Stand 14.06.2022),
dl-de/zero-2.0.

Two corrections are needed before a block figure becomes a tile figure:

- **Streets.** A block value excludes the street in front of it, a game tile
  does not. Berlin's street land is 9 721 ha of 83 694 ha excluding water
  (11.6 %) and is 85.2 % sealed, so a tile is
  `0.88 · block + 0.12 · 0.852`.
- **Which sub-type.** A game tile is a hectare built out for one use, which is
  the denser end of a Berlin land-use class rather than its mean.

| Tile | Umweltatlas Flächentyp | Block | With streets | Tile |
|---|---|---|---|---|
| housing_low | 23 Freistehende Einfamilienhäuser mit Gärten 34.9 %, 22 Reihen-/Doppelhäuser 37.3 %, 25 Verdichtung in Einzelhausgebieten 39.9 % | 35–40 % | 0.44 | 0.45 |
| housing_high | 3 Geschlossene/halboffene Blockbebauung 65.6 %, 73 Geschosswohnungsbau ab 1990 64.3 %, 2 Geschlossene Blockbebauung 5-gesch. 77.8 % | 64–78 % | 0.72–0.79 | 0.75 |
| commercial | 29 Kerngebiet 85.7 % | 85.7 % | 0.86 | 0.85 |
| industry | 31 Gewerbe-/Industriegebiet, dichte Bebauung 88.4 % (38.0 pp of it unbuilt: yards and storage) | 88.4 % | 0.88 | 0.88 |
| park | 53 Park / Grünfläche 10.1 %, of which 0.7 pp built | 10.1 % | 0.10 | 0.10 |
| meadow, cropland, forest | 55 Wald 0.3 %, 56 Landwirtschaft 0.1 % (the 2016 edition also reports Grünland 0.2 %) | ≈ 0 | ≈ 0 | 0.00 |

Two values changed as a result:

- **industry 0.90 → 0.88.** 0.90 was above every type Berlin measures. The
  whole Gewerbe- und Industriegebiet class averages 70.7 %, because it also
  holds sparsely built sites (type 30, 66.9 %); a fully developed industrial
  hectare is the dense case, 88.4 %.
- **park 0.15 → 0.10.** Measured parks are 10.1 % sealed and almost none of
  that is building. 0.15 assumed more path and playground than parks have.

The BauNVO ceilings still hold as a cross-check rather than as the source:
§ 17 caps GRZ at 0.4 for WR/WA, 0.6 for MI and 0.8 for GE/GI, and § 19 Abs. 4
lets garages, drives and ancillary buildings overshoot that by half, to at most
0.8. Detached housing at 0.4 + overshoot and a hectare that is one-eighth
street lands where Berlin measures it.

`solar_field.sealing` is not covered by this dataset — Berlin has no
ground-mount PV type — and remains an estimate.

## Cooling parameters

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

## CO₂ per hectare — land cover (verified in T-103)

`co2PerHaYear` is real tonnes of CO₂ per hectare per year, positive for a
source. It does not age with the tile: a forest emits its number the month it
is planted.

That fixes what the land-cover values have to mean. **They are rates of
land-use change, not national averages of the land cover.** The player converts
a hectare; the number is what that conversion does. The distinction is not
pedantic, because for three of the five tiles the two differ in sign:

| Tile | Value | What it is | National average of that cover |
|---|---|---|---|
| forest | −10 | a newly established, growing stand: age class II (21–40 a) binds most, an establishing Mischwald about 2.4 t C/ha/a = 8.8 t CO₂ | German forest 2021: 52.5 Mt over 10.7 M ha = **−4.9**; and since 2017 a *source* (BWI 2022; UBA 2024: +2.1 Mt) after the calamity years |
| meadow | −1 | soil carbon built after conversion from cropland: 0.8 t C/ha/a ≈ 2.9 t CO₂ (Poeplau & Don 2013), taken conservatively because Poeplau et al. 2017 finds productive arable a poor candidate | German grassland 2024: 24.2 Mt over 4.74 M ha = **+5.1**, a source, because drained peat dominates it |
| cropland | +1.5 | the national average, which is what a cropland tile is | UBA 2024: 17.5 Mt over 11.66 M ha = **+1.50** ✔ |
| park | −3 | Nowak et al. 2013: 0.28 kg C/m² of canopy; at this tile's canopy fraction of 0.5 that is 5.1 t CO₂/ha once mature, and a park spends two decades below it | — |
| wetland | −5 | conservative sink for a created wetland; rewetting drained peat saves ≥ 20 t CO₂-eq/ha/a against drained grassland, and a rewetted fen needs 13–16 years to reach the standard factors | — |

Only cropland is a case where the tile value and the national average are the
same number, and there the two agree to two decimals.

Traffic CO₂ is computed separately from car-km (0.15 kg/km, UBA fleet average).

## CO₂ per hectare — buildings (**not** verified; see the warning below)

housing_low 25, housing_high 50, commercial 60, industry 400. These four are
still the placeholders T-102 wrote, and T-103 found that **their own source
strings did not produce them**: `housing_low` cited "≈ 2 t CO₂/EW/a at 45
EW/ha", which is 90 t/ha, against a stored value of 25.

Checked against UBA, direct CO₂ from private households' combustion plants was
77 Mt in 2024 across about 83.5 M residents — 0.92 t per resident per year,
before district heat and electricity, which the energy sector carries. At the
model's own densities that is roughly **41 t/ha for housing_low and 166 t/ha
for housing_high**: three times the stored values.

They were left alone because raising them is not a parameter fix. The climate
indicator scores 2.5 t CO₂ per person as zero
(`indicators.dart`), which is already an aspirational scale rather than a
German one — the real figure is about 7.8 — so tripling the housing term would
push every city on every level to a climate score of zero. Correcting the
table and rescaling the indicator have to happen together, and the level goals
have to be re-proven winnable afterwards. That is a design decision, recorded
here rather than taken quietly.

## References

- BKompV Anlage 2: https://www.gesetze-im-internet.de/bkompv/anlage_2.html
- BfN-Schriften 721, Kartieranleitung für die Biotoptypen nach Anlage 2 BKompV
- Destatis, Wohnfläche je Einwohner: https://www.destatis.de/DE/Presse/Pressemitteilungen/2025/09/PD25_336_31231.html
- BauNVO § 17: https://www.gesetze-im-internet.de/baunvo/__17.html
- Copernicus Land Monitoring Service, Imperviousness
- GIFPRO Bedarfsprognose, Gewerbeflächenkonzept Bielefeld 2020, Baustein 07: https://www.bielefeld.de/sites/default/files/datei/2020/GewerbeflKonz_7.pdf
- BauNVO § 19: https://www.gesetze-im-internet.de/baunvo/__19.html
- Umweltatlas Berlin 01.02 Versiegelung 2021: https://www.berlin.de/umweltatlas/boden/versiegelung/2021/kartenbeschreibung/
- Umweltatlas Berlin, Abschlussbericht Versiegelung 2021 (Tabelle 19): https://www.berlin.de/umweltatlas/_assets/literatur/ab_versiegelung_2021.pdf
- InVEST User Guide, Urban Cooling Model
- UBA, Emissionen der Landnutzung, -änderung und Forstwirtschaft: https://www.umweltbundesamt.de/daten/umweltzustand-trends/klima/treibhausgas-emissionen-in-deutschland/emissionen-der-landnutzung-aenderung
- UBA, Energieverbrauch privater Haushalte: https://www.umweltbundesamt.de/daten/umweltzustand-trends/private-haushalte-konsum/wohnen/energieverbrauch-privater-haushalte
- Destatis/Thünen, Waldgesamtrechnung 2021: https://www.destatis.de/DE/Presse/Pressemitteilungen/Zahl-der-Woche/2024/PD24_12_p002.html
- Thünen, Ergebnisse der Bundeswaldinventur 2022: https://www.thuenen.de/de/themenfelder/waelder/die-bundeswaldinventur/ergebnisse-der-bundeswaldinventur-2022
- Destatis, Landwirtschaftliche Bodennutzung nach Hauptnutzungsarten: https://www.destatis.de/DE/Themen/Branchen-Unternehmen/Landwirtschaft-Forstwirtschaft-Fischerei/Feldfruechte-Gruenland/Tabellen/flaechen-hauptnutzungsarten.html
- Poeplau & Don 2013, Geoderma 192, 189–201; Poeplau et al. 2017, Sci. Rep. 7, 11550
- Nowak et al. 2013, Environmental Pollution 178, 229–236
- Greifswald Mire Centre, peatland conservation: https://www.greifswaldmoor.de/moore-61.html

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
