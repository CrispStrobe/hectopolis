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

## Noise emission (verified in T-103 where a source exists)

See `noise.md`. Tile values are L_eq at the tile boundary, 50 m from the centre.

The values had been anchored on the **TA Lärm daytime limits** (WR 50, WA 55,
MI 60, GE 65, GI 70 dB(A)). Those are *immission* limits at a protected
building — what may arrive — not what a hectare radiates, so they were the
wrong quantity, much as the GRZ was for sealing.

German planning does have the right quantity: the **flächenbezogener
Schallleistungspegel**, the sound power a square metre of a use may radiate,
which DIN 18005-1 Ziffer 5.2.3 puts at 60 dB(A)/m² for a Gewerbegebiet and
65 dB(A)/m² for an Industriegebiet. Over a hectare and out to the tile
reference:

```
L_W  = L_W" + 10·log10(10 000 m²)
L₅₀  = L_W  − 10·log10(2π · 50²)      (hemispherical, source on the ground)
```

| Tile | L_W" | L_W (1 ha) | L at 50 m | Tile value |
|---|---|---|---|---|
| commercial | 60 | 100 | 58.0 | **58** ✔ unchanged |
| industry | 65 | 105 | 63.0 | **63** (was 65) |

commercial came out exactly right; industry had been 2 dB above what the norm
gives, which is a factor of 1.6 in sound energy.

**road 60** is a calibration, not an estimate, and is now marked as one: the
per-segment level is set so that the energetic sum of segments reproduces
L_den ≈ 58 dB(A) at 100 m and ≈ 65 at 25 m from a straight road carrying
10 000 vehicles a day — the RLS-19 / CNOSSOS orders of magnitude.

**housing_low 45 and housing_high 50** are design values and will stay that
way. There is no flächenbezogener Schallleistungspegel for residential land,
because a residential area is not treated as a noise source in German
planning — its traffic is, and in this model that traffic lives in the road
tiles. The two numbers stand for residual noise, 5 dB apart for a fourfold
difference in density, below the TA Lärm daytime limits for the corresponding
area types. They are now labelled `design:` rather than "initial estimate",
because no source is going to settle them.

**noise.backgroundDb 35** is TA Lärm Nr. 6.1's night limit for a reine
Wohngebiet — the quietest environment the rule recognises, and the floor the
field never falls below.

**noise.buildingScreeningDbPerTile 5** is design anchored on ISO 9613-2 and
CNOSSOS: a closed row of buildings gives 5–10 dB of insertion loss in practice,
and the lower end is taken because a game hectare does not guarantee a closed
row. ISO 9613-2 caps single diffraction at 20 dB.

## Costs and maintenance (partly verified in T-103)

Build costs are development costs borne by the municipality in the game
(Erschließung, park construction, afforestation), in k€ per hectare.

**What T-103 could ground:**

| Parameter | Was | Now | Source |
|---|---|---|---|
| wetland build | 250 | **20** | Difu, Folgekosten der Siedlungsentwicklung (REFINA III, 2009), after TMLNU 2003: a Feuchtwiese on cropland including rewetting costs about €20 000/ha |
| meadow build | 5 | 5 ✔ | the same source's low-intervention case — a Feuchtwiese on fallow wet grassland, about €5 000/ha, which is what sowing without earthworks costs |
| park maintenance | 20 | 20 ✔ | GALK benchmarks: park lawn €0.40/m²·a for mowing alone, a park tree €52/a; a hectare of used park with paths, beds, trees, playgrounds, litter and safety inspection lands near €2/m²·a |
| meadow maintenance | 1 | 1 ✔ | the same benchmarks, well under the park lawn because an extensive meadow is cut once or twice a year |
| road maintenance | 10 | 10 ✔ | Difu/KfW Kommunalpanel, unchanged |

wetland at 250 k€/ha had been an estimate in the order of an excavated pond.
Rewetting is not excavation, and the correction is a factor of twelve. It makes
wetland much the cheapest way to buy biotope value — worth watching in level
design, and the reason the change is called out here rather than buried.

**What T-103 could not ground, and why.** The four Erschließung costs
(housing_low 200, housing_high 400, commercial 300, industry 300, i.e. 20–40
€/m²) stay estimates. **There is no open, citable dataset of German
Erschließungskosten per square metre.** The established tools — the Difu
FolgekostenSchätzer, LEANkom, was-kostet-mein-baugebiet.de, all out of the
REFINA programme — carry their Kostenkennwerte internally and publish the
method, not the numbers, and the cost manuals that do publish them (BKI) are
proprietary and cannot be copied into an AGPL project. Building practice
reports 15–40 €/m² of plot area for Erschließung, up to €100/m² including house
connections; all four values sit inside that band, which is the most that can
honestly be said. `forest`, `water`, `park` and `solar_field` build costs and
`economy.demolitionCostKEur` are in the same position.

Settling these needs either a licensable Kennwert set or a municipality willing
to publish a worked Baulandkalkulation. Until then they are the least grounded
numbers in the table, and they are marked as such in `tiles.json`.

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

## CO₂ per hectare — buildings (corrected in T-103)

The four built values were placeholders that **their own source strings did not
produce**: `housing_low` cited "≈ 2 t CO₂/EW/a at 45 EW/ha", which is 90 t/ha,
and stored 25. Checked against the national inventory they were all roughly a
third of the real figure. They are now derived, each from a published total
divided by a published denominator:

| Tile | Was | Now | Derivation |
|---|---|---|---|
| housing_low | 25 | **42** | UBA: 77 Mt direct CO₂ from private households' combustion plants (2024) ÷ 4.1 bn m² Wohnfläche (Destatis, end 2024) = 18.8 kg/m²·a; × 49.2 m²/resident × 45 residents/ha |
| housing_high | 50 | **166** | the same 18.8 kg/m²·a × 49.2 × 180 residents/ha |
| commercial | 60 | **66** | KSG building sector 100 Mt − households 77 Mt = 23 Mt from commercial and service buildings ÷ 34.8 M service employees = 0.66 t/job·a; × 100 jobs/ha |
| industry | 400 | **1220** | KSG industry sector 149 Mt ÷ 5.5 M employees in manufacturing establishments of 50+ (Destatis, end 2024) = 27.1 t/job·a; × 45 jobs/ha |
| mixed_use | 55 | **140** | 120 residents and 45 jobs on the two rates above |
| school | 30 | **33** | twice the commercial rate per job — a school heats far more floor area per employee — at 25 jobs/ha |

Three things are worth saying plainly about this table.

**The two housing tiles use the same emission per square metre.** UBA finds
detached and apartment buildings differ only slightly per m² once the weather
is corrected for. So the whole difference between 42 and 166 is density, which
is the honest answer: an apartment block emits four times as much per hectare
and the same per resident.

**District heat and electricity are not in these numbers.** They are about 15 %
of residential heat (dena-Gebäudereport 2025) and the inventory books them to
the energy sector, not to the building. The tile carries what the building
burns.

**industry 1220 is the German average, steel and cement included.** A municipal
light-industry estate emits far less per job, and the 5.5 M denominator leaves
out establishments under 50 employees, so the figure sits at the upper end of
what an industrial hectare plausibly does. It was taken anyway, for the same
reason `solar_field.co2PerHaYear` was: the alternative is a number chosen to be
convenient rather than true. It makes industry the most expensive tile in the
game climatically, which is what industry is.

Correcting the table required moving the climate indicator's zero point from a
hard-coded 2.5 t per person to Germany's own 5.0 t per resident-or-job
(`climate.zeroScoreTonsPerPerson`, see `indicators.md`). The two changes belong
together: real emissions judged against a scale calibrated to the old, too-small
table would have scored every city zero. All six built-in levels remain solvable
with three stars — `level_solutions_test.dart` is unchanged and passes — and
`tuebingen`, the only level with a climate goal, now starts at 73.8 against a
goal of 84.

## References

- BKompV Anlage 2: https://www.gesetze-im-internet.de/bkompv/anlage_2.html
- BfN-Schriften 721, Kartieranleitung für die Biotoptypen nach Anlage 2 BKompV
- Destatis, Wohnfläche je Einwohner: https://www.destatis.de/DE/Presse/Pressemitteilungen/2025/09/PD25_336_31231.html
- BauNVO § 17: https://www.gesetze-im-internet.de/baunvo/__17.html
- Copernicus Land Monitoring Service, Imperviousness
- DIN 18005-1 flächenbezogene Schallleistungspegel, values as reported in Versteyl/Storr/Schiller, Die schalltechnische Überplanung von bebauten Gewerbe- und Industriegebieten mit Emissionskontingenten: https://bekon-akustik.de/wp-content/uploads/2021/03/Die_schalltechnische_Ueberplanung_von_bebauten_GE_und_GI.pdf
- Difu, Folgekosten der Siedlungsentwicklung (REFINA Band III, 2009): https://difu.de/sites/default/files/media_files/publikationen/Band%20III%20Folgekosten-web-end%20neu.pdf
- GALK-Kennzahlen zur Unterhaltung von Grünanlagen (Stadt+Grün): https://stadtundgruen.de/artikel/daten-fuer-die-erstellung-und-unterhaltung-von-gruenanlagen-ueberarbeitet-neue-kennzahlen-7914
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

It is an **avoided** emission rather than an emitted one, sitting in a column
that otherwise holds emissions — still true, and still worth watching: **a
solar field remains the strongest climate lever a player can pull on the
negative side, and tiling them makes the climate indicator easy to satisfy.**

*Revised in T-103:* it is no longer an order of magnitude larger than
everything else. Industry was corrected from 400 to 1220 t/ha/yr, so the
largest number in the column is now an emission, and a solar field offsets
about a fifth of an industrial hectare rather than two-thirds of one. The
question the paragraph below raises is still open, but it is a smaller question
than it was.

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
