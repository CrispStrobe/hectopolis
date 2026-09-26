# Hectopolis — Project Plan and Roadmap

Name: **Hectopolis** (chosen 2026-09-05 after a web collision check; register search at DPMA/EUIPO still open). Internal package names stay `stadtbau`/`stadtbau_sim`. A cross-platform tile-placement city/landscape
simulation game about the interplay of urban habitat, ecology and economy.

This file is the single source of truth for scope, architecture, the simulation model and
the task roadmap. Agents work through the tasks in `## Roadmap` one by one. Every task has
an ID, a scope, acceptance criteria and the files it touches. Mark a task done by changing
its checkbox and adding a one-line note (date, commit or summary).

---

## 1. Vision

The player builds a city on a square grid out of landscape and urban tile types and watches,
in real time, how placement changes biodiversity, air quality, noise, housing, jobs,
shopping and recreation access, commuting, municipal finances and climate. The model is
**realistic**: every parameter traces back to a public, license-free source (German federal
law, EU law, official statistics, open-licensed scientific models). The game exposes the
model at several depths: colour overlays first, then numbers, then the causal loops.

Non-protectable ideas we borrow (concepts only, never names, art, text or tables):

- **Ökolopoly / ecopolicy** (Vester): coupled cybernetic feedback loops, "steer the system,
  don't optimise one number". All rights are held by Malik Management; the name, the
  Wirkungstabellen, the artwork and the texts are off limits.
- **Future Landscape Simulator** (Futurium / IMAGINARY, inspired by MIT CityScope): tangible
  land-use tiles, live indicators (CO₂, biodiversity, yields), "avoid – shift – improve".
- **Micropolis** (SimCity classic, GPL-3): spatial fields computed from tile emitters with
  distance decay (pollution, land value, traffic). We re-implement from published science,
  we do not copy code.
- **Urban Dynamics** (Forrester 1969): stocks and flows for housing, industry, population.

## 2. Hard constraints

| Constraint | Decision |
|---|---|
| License | AGPL-3.0-or-later with an additional permission under section 7 allowing **us** (the copyright holders) to distribute through app stores under their terms. Contributors sign a DCO that accepts the exception. |
| Dependencies | Only AGPL-3-compatible: MIT, BSD, Apache-2.0, MPL-2.0, LGPL, GPL-3. **Not**: GPL-2-only, CC-BY-SA, ODbL for embedded data, anything proprietary or "free for non-commercial". |
| Data | Only CC0, CC-BY 4.0, Datenlizenz Deutschland 2.0, public-domain law texts (§ 5 UrhG), EU law, published scientific formulas. Every parameter carries a citation. |
| Platforms | Android, iOS, Web, macOS, Windows (Linux for free) from one Flutter codebase. |
| i18n | Every user-facing string lives in `app/lib/l10n/app_de.arb` and `app/lib/l10n/app_en.arb`. No hard-coded UI strings. CI fails otherwise. |
| Multiplayer | Same-WLAN cross-play (native host, native and web clients). Internet play later. |
| Storage on this box | Source in `/mnt/volume1/code/stadtbau` (small disk). `app/build/` is a symlink to `/mnt/storage/code/stadtbau/build`; raw datasets go to `/mnt/storage/code/stadtbau/data`. Never commit raw datasets; commit only the small derived parameter tables. |

## 3. Architecture

```
stadtbau/
  pubspec.yaml                 # Dart pub workspace root
  PLAN.md  CLAUDE.md  LICENSE  LICENSE-EXCEPTION.md  THIRD_PARTY.md
  docs/model/                  # one Markdown file per model component, with sources
  packages/stadtbau_sim/       # pure Dart, no Flutter: grid, tiles, fields, stocks, indicators
  packages/stadtbau_net/       # (Phase 6) LAN protocol, host/client, discovery
  app/                         # Flutter app: UI, overlays, drag&drop, l10n, settings
  tools/                       # scripts: i18n lint, license audit, parameter table validation
  data/params/                 # small JSON/YAML parameter tables with citations (committed)
  app/build -> /mnt/storage/code/stadtbau/build   (symlink; Flutter writes there)
```

Key design rules:

1. **Simulation is a pure Dart package** with no Flutter import. It is deterministic
   (fixed-step ticks, integer-seeded RNG, no wall clock) so that host and clients compute
   identical states and replays are possible. All state is serialisable to JSON.
2. **Two model layers.** (a) *Spatial fields*: each tile emits or absorbs quantities (noise,
   pollutants, cooling, retail supply, jobs, green access) that are propagated over the grid
   with distance-decay kernels. (b) *System dynamics stocks*: population, jobs, housing
   occupancy, municipal budget, habitat quality index, evolve per tick based on the fields.
   Feedback loops connect the two (see §4.6).
3. **Every parameter is data, not code.** Tile definitions and coefficients live in
   `data/params/*.json` with a `source` field. The sim loads them; tests validate them.
4. **UI reads, sim writes.** The app sends commands (`PlaceTile`, `RemoveTile`, `EndTurn`)
   and renders `WorldState` + `IndicatorSnapshot`. Same interface for local and network play.
5. **Grid unit = 1 ha (100 m × 100 m).** This matches the Zensus 2022 100 m grid and the
   InVEST/BKompV hectare-based parameters. A 16×16 map is 2.56 km², a small town quarter.

## 4. Simulation model v1 (16×16, 10 tile types)

All values below are **initial estimates** to be verified and cited in the tasks of Phase 1.
Units are per hectare (one tile) unless stated.

### 4.1 Tile types

| id | DE | EN | Category | Residents/ha | Jobs/ha | Sealing | Biotope (BKompV 0–24) | Noise dB(A) | CO₂ t/ha/a | Build k€ | Upkeep k€/a |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `meadow` | Wiese | Meadow | nature | 0 | 0 | 0,00 | 18 | – | -1 | 5 | 1 |
| `cropland` | Acker | Cropland | nature | 0 | 1 | 0,00 | 6 | – | 1,5 | 2 | 0 |
| `forest` | Wald | Forest | nature | 0 | 0 | 0,00 | 18 | – | -10 | 20 | 1 |
| `water` | Gewässer | Water | nature | 0 | 0 | 0,00 | 16 | – | 0 | 200 | 2 |
| `park` | Park | Park | green-urban | 0 | 2 | 0,10 | 13 | – | -3 | 400 | 20 |
| `housing_low` | Einfamilienhäuser | Detached housing | residential | 45 | 3 | 0,45 | 5 | 45 | 42 | 200 | 2 |
| `housing_high` | Mehrfamilienhäuser | Apartment blocks | residential | 180 | 15 | 0,75 | 4 | 50 | 166 | 400 | 4 |
| `commercial` | Gewerbe / Einzelhandel | Commercial / retail | work | 0 | 100 | 0,85 | 2 | 58 | 66 | 300 | 3 |
| `industry` | Industrie | Industry | work | 0 | 45 | 0,88 | 2 | 63 | 1220 | 300 | 3 |
| `road` | Hauptstraße | Main road | infrastructure | 0 | 0 | 0,95 | 0 | 60 | 0 | 300 | 10 |
| `wetland` | Feuchtgebiet | Wetland | nature | 0 | 0 | 0,00 | 22 | – | -5 | 20 | 1 |
| `solar_field` | Freiflächen-PV | Solar field | infrastructure | 0 | 0,5 | 0,10 | 8 | – | -266 | 700 | 8 |
| `mixed_use` | Mischgebiet | Mixed use | residential | 120 | 45 | 0,70 | 4 | 55 | 140 | 450 | 10 |
| `school` | Schule | School | work | 0 | 25 | 0,50 | 6 | 52 | 33 | 900 | 45 |
| `tram_stop` | Tramhaltestelle | Tram stop | infrastructure | 0 | 1 | 0,85 | 1 | 56 | 0 | 800 | 25 |
| `cycle_path` | Radweg | Cycle path | infrastructure | 0 | 0 | 0,35 | 12 | – | -1 | 120 | 3 |

**This table is a mirror, not the source.** `data/params/tiles.json` is the source
of truth — every entry there carries its own `source` field — and the generated
Quellen page lists all 380 parameters with their provenance. The values above
were regenerated from it on 2026-09-18, after T-103 verified them; if the two
ever disagree, the JSON is right. `docs/model/tiles.md` explains the
derivations, including the three cases where the original design anchored a
parameter on the wrong kind of number (a GRZ is not a measurement of sealing,
TA Lärm is an immission limit and not an emission, and the InVEST sample threat
table does not say what was claimed of it).

Sources behind the columns: BKompV Anlage 2 (biotope values), Umweltatlas
Berlin 01.02 (sealing), GIFPRO Flächenkennziffern (jobs/ha), Destatis 49.2 m²
living space per person with BauNVO GFZ (residents/ha), DIN 18005-1 and TA Lärm
(noise), UBA and Thünen (CO₂). Full register in §8.

### 4.2 Spatial fields (recomputed each tick, O(cells × kernel))

| Field | Emitters | Propagation | Sinks / modifiers | Read by |
|---|---|---|---|---|
| **Noise** L_den (dB) | road (100 m segments, emission scaled by 10·log10(Q/10 000)), industry, commercial, housing | Every tile is a point/area source: −6 dB per doubling from the 50 m tile boundary (ISO 9613-2). Road segments summed energetically reproduce the −3 dB per doubling of a line (CNOSSOS-EU segmentation). | Forest / park in the path: −2 dB per tile (foliage, CNOSSOS ground/foliage attenuation, simplified); housing_high blocks −5 dB per tile (screening). | Housing exposure vs TA Lärm limits (WA 55 day / 40 night; MI 60/45). |
| **Air pollution** index 0–100 | road (NOx), industry (PM, NOx), commercial (delivery traffic), commute-derived traffic | Exponential kernel exp(−d/L), L = 300 m (3 tiles), isotropic (no wind in v1). | Forest −20 %, park −10 %, meadow −5 % local deposition (i-Tree / Nowak et al. magnitudes). | Health/attractiveness of residential tiles. |
| **Cooling / heat** ΔT (°C) | Every tile has cooling capacity CC = 0.6·shade + 0.2·albedo + 0.2·ETI (InVEST Urban Cooling), with the ETI term scaled by the month (`seasons.growth`). | Connected green patches ≥ 2 ha cool neighbours within 300 m (3 tiles). | ΔT = UHI_max(month) · clamp((CC_meadow − HM) / (CC_meadow − CC_min)); `heat.uhiMaxC` = 3.0 °C is the **annual-mean** ceiling and the month's factor scales it (July ×1.93). Scores divide by that scaled ceiling, never by the parameter — see `docs/model/heat.md`. | Recreation, climate, attractiveness. |
| **Green access** | park, forest, meadow, water (≥ 0.5 ha ⇒ any tile qualifies) | Boolean within 300 m (3 tiles, WHO / 3-30-300 rule); quality weight by biotope value and size. | – | Recreation indicator per residential tile. |
| **Retail access** | commercial (retail floor space 2 000 m² per tile ≈ supply for 1 400 residents at 1.4 m²/resident, HDE) | Huff model: P_ij = S_j·d_ij^−λ / Σ, λ = 2, walking radius 700 m (BBSR Nahversorgung). | – | Shopping indicator; retail revenue → commercial viability. |
| **Job access** | commercial, industry, housing_high (local services) | Gravity: A_i = Σ_j J_j·exp(−d_ij/2 km). | – | Commute distance, mode share, traffic. |
| **Habitat quality** 0–1 | nature + park tiles | Base = biotope value / 24. Threats (InVEST Habitat Quality): road (w 1.0, max dist 300 m), industry (0.8, 500 m), housing_high (0.5, 200 m), commercial (0.6, 300 m), decay linear. | Patch connectivity via 8-neighbourhood; species-area S = c·A^z, z = 0.30 (MacArthur–Wilson / Arrhenius). | Biodiversity indicator. |
| **Traffic** (vehicles/day) | Derived from commutes (see 4.4) routed via nearest road tiles. | Assigned to road tiles; feeds noise and air. | – | Noise, air. |

### 4.3 Stocks (system dynamics, per tick = one game month)

| Stock | Inflow | Outflow | Notes |
|---|---|---|---|
| Population P | Immigration = capacity_free × attractiveness × 0.08 | Emigration = P × (1 − attractiveness) × 0.03 | capacity = Σ residents/ha of residential tiles |
| Jobs filled J | min(jobs_capacity, P × labour_participation 0.52) | – | participation from Destatis Erwerbstätigenquote |
| Budget B (€) | Taxes: 550 €/resident/yr (Einkommensteuer-Gemeindeanteil), 2 100 €/job/yr (Gewerbesteuer), 180 €/resident/yr (Grundsteuer) | Maintenance: school 45 000 €/ha/yr, tram stop 25 000, park 20 000, road 10 000, other 1 000–10 000; building costs on placement | Annual figures ÷ 12 per tick. Sources: Destatis kommunale Finanzen; GALK benchmarks for green upkeep; Difu/KfW Kommunalpanel for roads. |
| Habitat index H | Recovery towards potential (biotope value) over `recoveryMonths`: 120 for meadow, 240 for forest and park, 180 for wetland | Immediate loss when a nature tile is replaced | A newly planted forest starts at 40 % of its potential biotope value (`biotopeStart`). |
| CO₂ balance (t/yr) | Sequestration: solar field −266 t/ha/yr (avoided grid emissions), forest −10, wetland −5, park −3, meadow −1 | Emissions: industry 1 220 t/ha/yr, housing_high 166, mixed use 140, commercial 66, housing_low 42, school 33, cropland 1,5, commute km × 0.15 kg | Verified in T-103 against the UBA inventory, the Waldgesamtrechnung and the LULUCF figures; the land-cover values are rates of land-use *change*, not national averages. The climate indicator scores 5.0 t per resident-or-job as zero, which is Germany's own figure. |

### 4.4 Commuting

For each residential tile: workers = residents × 0.52. Distribute to job tiles with the
gravity kernel. Mean commute distance d̄ per tile. Mode share by distance (MiD 2017):
≤ 1 km walk 0.55 / bike 0.20 / car 0.25; 1–3 km walk 0.15 / bike 0.35 / car 0.50;
> 3 km walk 0.02 / bike 0.13 / car 0.85. **The gravity kernel is `access.jobDecayM`,
the same 2 km decay that drives the job-access overlay** — retuning it moves both
(`docs/model/access.md`).
Car trips × 2 per day become vehicles/day on the nearest road path (v1: straight-line to
nearest road tile, then nearest road tile to job). No road within 3 tiles ⇒ residents count
as poorly connected (attractiveness malus).

### 4.5 Indicators (shown to the player)

1. Biodiversity (0–100): habitat-weighted, connectivity-weighted species index.
2. Air quality (0–100): population-weighted inverse pollution.
3. Noise (0–100): share of residents below TA Lärm daytime limit.
4. Housing (0–100): occupancy and free capacity balance (target 95 %).
5. Jobs / economy (0–100): job-housing balance, budget trend.
6. Shopping (0–100): population-weighted Huff accessibility within 700 m.
7. Recreation (0–100): share of residents with green access within 300 m, cooling bonus.
8. Commuting (0–100): inverse mean commute distance and car share.
9. Climate (0–100): CO₂ balance and mean UHI ΔT.
10. Budget (€): raw number, with monthly delta.

### 4.6 Feedback loops (must exist in v1)

- Attractiveness = f(noise, air, green access, retail access, job access, cooling).
  → population → traffic → noise & air → attractiveness (balancing loop).
- Population → tax revenue → budget → placement affordability (reinforcing until costs bite).
- Jobs without housing → commuting from outside → traffic without residents (malus).
- Nature patches fragmented by roads → habitat threat and lower patch area → biodiversity.
- Forest matures over years: biodiversity and cooling gain lag behind placement (delay).

## 5. Visualisation depths

1. **Colour overlays** per field (toggle): noise, air, heat, green access, retail access,
   habitat quality. Diverging or sequential palettes; colour-blind safe.
2. **Numbers**: indicator panel with 0–100 gauges and raw units on tap.
3. **Causal view**: a loop diagram highlighting which loops are currently dominant
   (Phase 5).
4. **Tile inspector**: tap a tile to see its per-field values and sources.

## 6. Multiplayer (Phase 6)

Host-authoritative, deterministic sim. One native device hosts a WebSocket server; clients
(native or browser) send commands and receive state diffs. Discovery via mDNS/DNS-SD
(package `bonsoir`, MIT) with QR-code / room-code fallback (browsers cannot use mDNS and
cannot host). Turn-based v1: each player owns a district; noise, air and habitat cross
district borders. Later: internet play via a small Dart relay (same protocol).

---

## 7. Roadmap

Conventions: `[ ]` open, `[x]` done, `[~]` in progress. Each task is sized for one agent
session. Tasks within a phase are ordered; phases can overlap where noted.
Run `tools/check.sh` (analyze, test, i18n lint, license audit) before marking a task done.

### Phase 0 — Repository and toolchain

- [x] **T-001 Workspace scaffold.** Root `pubspec.yaml` pub workspace with `app/` (Flutter,
  org `de.stadtbau`, platforms android, ios, web, macos, windows, linux) and
  `packages/stadtbau_sim/` (pure Dart). `app/build/` symlinked to
  `/mnt/storage/code/stadtbau/build`. `.gitignore` for Flutter, `analysis_options.yaml`
  with `flutter_lints` and strict mode.
  *Done when* `flutter analyze` and `flutter test` pass in both packages and
  `flutter build web` writes to the storage mount.
  *Note 2026-09-05:* Workspace, app, sim package, build symlink, analysis options in place; analyze and tests pass; web build verified.
- [x] **T-002 License files.** `LICENSE` (AGPL-3.0-or-later full text),
  `LICENSE-EXCEPTION.md` (section 7 additional permission for app-store distribution by the
  copyright holders), SPDX header in every source file
  (`// SPDX-License-Identifier: AGPL-3.0-or-later`), `CONTRIBUTING.md` with DCO text.
  *Done when* `tools/license_audit.sh` finds no source file without header.
  *Note 2026-09-05:* LICENSE (AGPL text), LICENSE-EXCEPTION.md, CONTRIBUTING.md with DCO, SPDX headers everywhere.
- [x] **T-003 Dependency license audit tool.** `tools/license_audit.sh` reads
  `pubspec.lock` files, resolves each package's license from the pub cache and fails on
  anything outside the allow-list (MIT, BSD-2/3, Apache-2.0, MPL-2.0, LGPL-2.1+, GPL-3.0+,
  Zlib, ISC, Unlicense, CC0). Writes `THIRD_PARTY.md`.
  *Note 2026-09-05:* `tools/license_audit.sh` classifies pub-cache and SDK licenses, writes THIRD_PARTY.md, fails on non-allow-listed licenses.
- [x] **T-004 i18n scaffold and lint.** `app/l10n.yaml`, `app_de.arb` + `app_en.arb`,
  `flutter gen-l10n` wired into build. `tools/i18n_lint.dart` fails on: keys missing in
  one language, string literals inside `Text(`/`Tooltip(`/`SnackBar(` widgets under
  `app/lib/` (allow-list annotation `// i18n-ignore` for identifiers).
  *Note 2026-09-05:* ARB files with ~90 keys in DE and EN, `flutter gen-l10n`, `tools/i18n_lint.dart` (key parity + literal detection).
  *Note 2026-09-18:* The lint now also fails on a **key nothing reads**. Eight had accumulated of
  260 — copy two translators maintain and nobody sees. Seven were deleted; the eighth,
  `missionPredictionSaved`, turned out to be missing UI rather than dead copy: answering a
  mission's prediction closed the dialog and said nothing, so the player could not tell the answer
  was taken. It is wired now, at zero new copy. `// i18n-unused: <key> <why>` keeps one
  deliberately. Verified by adding a key nothing reads and watching it fail, and by marking it and
  watching it pass. Removing `categoryName` — copy for a grouped palette that never shipped —
  then made `tool/learning_audit.dart` fail, because it required a branch per `TileCategory`; that
  requirement was aspirational, and the audit now checks the copy the app *shows*. The two lints
  keeping each other honest is the point of having both.
- [x] **T-005 CI.** GitHub Actions (or Woodpecker) workflow: analyze, test, i18n lint,
  license audit, web build artifact. Cache pub. Runs on push and PR.
  *Note 2026-09-05 (2):* `.github/workflows/check.yml`: analyze, tests, i18n lint, license audit, params mirror check, web build artifact.
- [x] **T-006 `tools/check.sh`.** One local command that runs everything CI runs.
  *Note 2026-09-05:* `tools/check.sh` runs params mirror, gen-l10n, analyze, tests, i18n lint, license audit.

### Phase 1 — Simulation core (`packages/stadtbau_sim`)

- [x] **T-101 Grid and world state.** `Grid<T>` with width/height, `TileId` enum from
  params, `WorldState` (grid, tick, seed, stocks), JSON (de)serialisation, deterministic
  `Rng` (xorshift, seeded). Tests: round-trip, determinism with same seed.
  *Note 2026-09-05:* `WorldState`, `Rng` (xorshift32, web-safe), JSON round trip, hash; tests pass.
- [x] **T-102 Parameter tables.** `data/params/tiles.json` with the table in §4.1, every
  numeric field carrying `{ "value": …, "source": "…", "note": "…" }`. Loader + validator
  (all ids present, ranges sane). Test: schema validation.
  *Note 2026-09-05:* `data/params/tiles.json` with {value, source} entries, mirrored by `tools/gen_params.dart`; loader validates all ten ids.
- [x] **T-103 Verify tile parameters against sources.** For each row in §4.1 look up:
  BKompV Anlage 2 biotope code and value (gesetze-im-internet.de/bkompv/anlage_2.html),
  BBSR density values, TA Lärm zone limits, CNOSSOS emission references. Update
  `tiles.json` sources. Write `docs/model/tiles.md` with the citations. No code.
  *Note 2026-09-05 (2):* BKompV Anlage 2 codes recorded per tile (`docs/model/tiles.md`); densities derived from Destatis 49.2 m²/EW and BauNVO GFZ; taxes from Destatis 2023/2024 releases; MiD 2017 mode shares. Costs and recovery times remain estimates.
  *Note 2026-09-18:* Sealing verified against Umweltatlas Berlin 01.02 Versiegelung 2021 Tabelle 19 (new source register row, dl-de/zero-2.0), corrected for street share; industry 0.90 → 0.88, park 0.15 → 0.10, the other three confirmed. Costs, CO₂, air and noise emissions still estimates.
  *Note 2026-09-18 (2):* Land-cover CO₂ verified (forest, meadow, cropland, park, wetland): all five values hold, but they are rates of land-use *change*, not national averages of the cover, and `docs/model/tiles.md` now says so — for forest and meadow the national average has the opposite sign. Cropland +1.5 matches UBA/Destatis to two decimals. **The four building CO₂ values are wrong by about 3× and were deliberately not changed**: correcting them requires rescaling the climate indicator's 2.5 t/person zero point and re-proving every level, which is a design decision for the user. Costs, air and noise emissions still estimates.
  *Note 2026-09-18 (3):* jobsPerHa verified: commercial 100 and industry 45 both fall straight out of the GIFPRO Flächenkennziffern (100 m²/Beschäftigten for business services; 225 m² standard model). The old attribution to "BBSR Flächenkennwerte" was not traceable to any BBSR publication and is gone.
  *Note 2026-09-18 (4):* Building CO₂ corrected on the user's decision: housing_low 25 → 42, housing_high 50 → 166, commercial 60 → 66, industry 400 → 1220, mixed_use 55 → 140, school 30 → 33, each divided out of a published national total. The climate indicator's zero point moved with them from a hard-coded 2.5 t/person to a new sourced parameter `climate.zeroScoreTonsPerPerson` = 5.0 t per resident-or-job (Germany's own figure), so a city emitting like Germany scores zero. All six levels still solve with three stars unchanged.
  *Note 2026-09-18 (5):* Costs partly settled. wetland build 250 → 20 k€/ha (Difu/REFINA after TMLNU: a Feuchtwiese incl. rewetting is ~20 k€/ha, not the cost of an excavated pond); meadow build, park and meadow maintenance confirmed against the same source and the GALK green-space benchmarks. **The four Erschließung costs stay estimates and will not be settled by searching**: no open dataset of German Erschließungskosten per m² exists — the REFINA tools publish the method, not the Kennwerte, and BKI is proprietary. `docs/model/tiles.md` says what would settle them.
  *Note 2026-09-18 (6):* Noise emissions verified. TA Lärm gives *immission* limits, not emissions — the wrong quantity, like the GRZ for sealing. DIN 18005-1 Ziffer 5.2.3 gives the right one (flächenbezogener Schallleistungspegel 60 dB(A)/m² GE, 65 GI): commercial 58 comes out exactly, industry 65 → 63. road 60 re-marked as the calibration it always was; housing 45/50 re-marked `design:` because no source will settle a residential emission; backgroundDb 35 = TA Lärm Nr. 6.1 night limit for WR.
  *Note 2026-09-18 (7):* Air emissions verified as *ratios* (the scale is relative, road = 1.0, and calibrated by T-114). UBA 2024 data sets the ordering and the table matches it. industry 3.0 is deliberately below the inventory ratio (~10×) and now says why: the model has no stack height or plume rise, so a ground-level source at inventory strength would be wrong. Sinks and decay length re-labelled `design, anchored on …` — air.md already said the sink effect is amplified on purpose, so "initial estimate" was the wrong label. Calibration harness re-run: industrial-park noise 63 % → 43 % above 55 dB(A) from the industry noise correction (expectation updated); **dense-quarter ΔT is 0.18 against a recorded 1.6, and that drift predates this work** — flagged in calibration.md, not fixed here.
  *Note 2026-09-18 (8):* Habitat threats verified. Two source strings were wrong about what they cited: the InVEST example table lists roads at 0.1/0.4 and agriculture at 1.0, and has no "urban" row. What the guide does say is that weights are normalised, so only their ratios mean anything — the ordering is the whole content, and it is now labelled `design`. The distances could not come from InVEST either (its example is 2–8 km, landscape scale). `road.maxDistanceM = 300` is now grounded in the road-effect-zone literature (Forman & Deblinger 2000; Reijnen & Foppen); the four settlement distances stay design.
  **Status after this session: of 380 parameters, 205 cite a source (was 182), 198 of those are settled (was 149), and 7 cited parameters are still marked as initial estimates (was 33).**
- [x] **T-104 Kernel engine.** Generic `FieldSolver` that takes emitters (tile → strength)
  and a kernel (function of Chebyshev or Euclidean distance in tiles) and fills a
  `Float32List` field. Support energetic (dB) summation and linear summation. Precompute
  offset tables up to radius R. Tests: single emitter symmetry, superposition.
  *Note 2026-09-05:* `Offsets` (radius tables), `cellsBetween` (Bresenham), `DisjointSet` in `geometry.dart`.
- [x] **T-105 Noise field.** Implement §4.2 noise: line-source decay for roads, area decay
  for others, foliage and screening attenuation along the straight-line path (Bresenham).
  Output per residential tile L_den. Test: road at 100 m ≈ 60 dB, forest in between lowers
  by 2 dB per tile. Document in `docs/model/noise.md` with CNOSSOS / TA Lärm references.
  *Note 2026-09-05:* Code + tests done (`model/noise.dart`, point-source segments summed energetically, path attenuation). `docs/model/noise.md` still to write.
  *Note 2026-09-05 (2):* `docs/model/noise.md` written.
- [x] **T-106 Air pollution field.** Exponential kernel, deposition sinks, traffic
  contribution hook (filled by T-110). `docs/model/air.md` citing EMEP/EEA guidebook and
  Nowak et al. deposition magnitudes.
  *Note 2026-09-05:* Code done (`model/air.dart`). `docs/model/air.md` still to write; wind deferred to T-501.
  *Note 2026-09-05 (2):* `docs/model/air.md` written; kernel normalised after calibration.
- [x] **T-107 Cooling / heat field.** InVEST Urban Cooling simplification: CC per tile from
  params (shade, albedo, ETI), connected green patches ≥ 2 ha cool within 100 m, UHI 3.5 °C.
  `docs/model/heat.md` citing InVEST user guide (Apache-2.0 docs).
  *Note 2026-09-05:* Code done (`model/heat.dart`). `docs/model/heat.md` still to write.
  *Note 2026-09-05 (2):* `docs/model/heat.md` written; ΔT rescaled to the meadow reference, d_cool 3 tiles (InVEST default 450 m).
- [x] **T-108 Access fields.** Green access (300 m boolean + quality), retail Huff access
  (λ = 2, 700 m), job gravity access (2 km). `docs/model/access.md` citing WHO, 3-30-300,
  BBSR Nahversorgung, Huff 1963.
  *Note 2026-09-05:* Code done (`model/access.dart`). `docs/model/access.md` still to write.
  *Note 2026-09-05 (2):* `docs/model/access.md` written.
- [x] **T-109 Habitat quality and biodiversity.** InVEST Habitat Quality threats table,
  patch labelling (8-neighbourhood union-find), species-area index, maturation stock for
  forest/meadow. `docs/model/biodiversity.md` citing InVEST HQ, BKompV, MacArthur–Wilson.
  *Note 2026-09-05:* Code + tests done (`model/habitat.dart`, effective mesh size for connectivity). `docs/model/biodiversity.md` still to write.
  *Note 2026-09-05 (2):* `docs/model/biodiversity.md` written.
- [x] **T-110 Commuting and traffic.** §4.4: workers, gravity distribution, mode share by
  distance (MiD 2017 bins), vehicles/day assigned to road tiles, feeds T-105/T-106.
  `docs/model/commute.md`.
  *Note 2026-09-05:* Code done (`model/commute.dart`, in/out-commuters, road assignment). `docs/model/commute.md` still to write.
  *Note 2026-09-05 (2):* `docs/model/commute.md` written; trips now routed over the road network with border exits.
- [x] **T-111 Stocks and budget.** §4.3 population, jobs, budget, CO₂ with monthly ticks.
  Placement costs and maintenance from params. `docs/model/economy.md` citing Destatis
  kommunale Finanzen. Test: a balanced 16×16 sample city has positive budget after 24 ticks.
  *Note 2026-09-05:* Code + test done (`model/stocks.dart`). `docs/model/economy.md` still to write.
  *Note 2026-09-05 (2):* `docs/model/economy.md` written.
- [x] **T-112 Indicators.** §4.5 ten indicators with 0–100 scaling and raw values;
  `IndicatorSnapshot` JSON. Test: all-forest map → biodiversity ≈ 100, housing 0.
  *Note 2026-09-05:* `indicators.dart`; tests for all-forest and mixed quarter pass.
- [x] **T-113 Command API.** `Simulation.apply(Command)` for `PlaceTile`, `RemoveTile`,
  `EndTurn/Tick`, with validation (budget, allowed tile list, bounds). Event log for
  replay. Test: replaying a log reproduces the final state hash.
  *Note 2026-09-05:* `Simulation.apply`, `TileBudget`, command log and `Simulation.replay`; replay hash test passes.
- [x] **T-114 Calibration harness.** `tool/calibrate.dart` builds archetype maps
  (village, suburb, dense quarter, industrial park, forest) and prints indicators; results
  are checked against plausibility ranges written in `docs/model/calibration.md`
  (e.g. dense quarter noise exposure 55–65 dB, suburb car share 0.6–0.8). Adjust
  coefficients only via `data/params/`.
  *Note 2026-09-05 (2):* `tool/calibrate.dart` with seven archetypes; ranges and results in `docs/model/calibration.md`. Climate score changed to per-person CO₂.
  *Note 2026-09-18:* The harness read seasonal quantities at a single tick, and 60 ticks is a whole number of years from a January start — so every ΔT it printed was a January reading. That is what made the dense-quarter 0.18 K look like a regression against the recorded 1.6 K; the annual mean is 1.71 K and the model never moved. It now sweeps the twelve months after the warm-up and reports `heatDeltaCYearMean`, `heatDeltaCSummerPeak` and the yearly spread of the recreation and climate scores.
- [~] **T-115 Performance.** 24×24 map full tick < 16 ms on desktop, < 50 ms on a mid
  Android phone (measure with `benchmark_harness`). Optimise kernels if needed.
  *Note 2026-09-05 (3):* 180 → 38 ms per tick on a loaded VPS (`benchmark/tick_benchmark.dart`); desktop and phone targets still to measure on real hardware.
  *Note 2026-09-18:* **The 16 ms desktop target is met** — 9–11 ms per tick on the loaded VPS, so a real desktop has margin. The 38 ms above was read at load ≈ 17 and is not comparable. `benchmark/field_profile.dart` now reports the cost of each field separately (minimum over many batches, since a mean on this box is mostly other people's work), which is what turned up the one remaining easy win: noise spent about a third of its time in `exp`, turning decibels into energies once per source-receiver pair. Source, divergence and path attenuation are now all table lookups — noise 3.60 → 2.42 ms, the whole field pass 8.90 → 7.43 ms. Phone target still to measure on real hardware.
  *Note 2026-09-15 (2):* Noise made reciprocal and halved (~8 → ~5 ms); `Simulation.copy()` clones fields and inherits the road network instead of recomputing, so the hover placement forecast drops from ~51 to ~26 ms, the cost of the one field stack it needs. `benchmark/tick_benchmark.dart` measures that forecast too.
  *Note 2026-09-15:* Another ~3.5× on the same benchmark (interleaved A/B on a loaded VPS). Profiled per stage: commute 24.3 → 3.1 ms (road network and BFS trees cached across ticks, dense trip matrix instead of a pair hash map, subtree accumulation instead of one path walk per origin-destination pair), access 7.7 → ~3 ms and noise ~9 → ~8 ms (flat per-tile-type lookup tables in `lib/src/lookup.dart`, precomputed Huff and distance tables, `exp` instead of `pow`, `Float64List` energy buffer). `Simulation.copy()` no longer recomputes the whole field stack twice, which halves the hover placement forecast. Desktop and phone targets still to measure on real hardware.

### Phase 2 — Game UI (`app/`)

- [x] **T-201 App shell.** Material 3, responsive layout: grid centre, palette left (and
  right on wide screens), indicator panel top or bottom. Locale switch DE/EN. Theme with
  light/dark. All strings via ARB.
  *Note 2026-09-05:* Material 3 shell with wide/narrow layouts, DE/EN toggle, light/dark themes.
- [~] **T-202 Grid renderer.** `CustomPainter` grid with tile sprites (own SVG/PNG assets,
  CC0 or self-made; record author in `THIRD_PARTY.md`), zoom and pan, 16×16 default,
  supports 8–24. 60 fps on web.
  *Note 2026-09-05:* CustomPainter grid with Material icon glyphs, 8–24 sizes. Zoom/pan and sprite assets still open.
  *Note 2026-09-05 (4):* T-202 zoom/pan done: `InteractiveViewer` with a `MapViewController` (min scale = fit, max 4×, translation clamped to the viewport), pinch/wheel zoom, drag pan, app-bar zoom in/out/reset; hit testing goes through the transform. Sprite assets still open.
  *Note 2026-09-07:* Added a complete model-driven procedural tile atlas: textured terrain and crops, connected water and roads, distinct parks and buildings, occupancy/activity cues, traffic and emissions animation, parameter-scaled forest maturity, construction transitions, smooth overlays, reduced-motion support and simulation-backed placement forecasts. Physical-device FPS measurements remain open.
  *Note 2026-09-07 (2):* Added persisted presentation controls for a clean map, ambient/effect animation masters, independent traffic/environment/city-activity layers, forecasts, causal markers, sound and haptics. Large maps now reduce decorative detail automatically when zoomed out.
  *Note 2026-09-15:* The painter is split into a still layer (ground, decoration, finished buildings) behind a `RepaintBoundary` and a moving layer (waves, smoke, lit windows, swaying trees, traffic, buildings under construction, overlay tint, grid, interaction outlines). The still layer is rebuilt only by the listenables it depends on, so the six-second ambient animation no longer redraws the whole city every frame: `app/test/app_test.dart` asserts it paints zero times across ten animation frames. ~24-37 → ~16-24 ms per ambient frame in a widget test on the sandbox map; the saving grows with map size and density. Physical-device FPS measurements remain open.
  *Note 2026-09-16:* Measured in real Chrome with `tools/web_frame_bench.py`, which drives a built web app over the DevTools protocol into the sandbox, fills part of the map and times the ambient animation. Interleaved against a build of the commit before the split, five pairs, twelve seconds each: the split is faster in 5 of 5, mean median frame time 230 → 170 ms (1.35×). Headless Chrome rasterises in software, so those absolute times (~5 fps) say nothing about a real device and the 60 fps target is still unverified — but the comparison is like-for-like, and the gain survives a bottleneck that is mostly rasterisation, which is what the `RepaintBoundary` was meant to cut. Physical-device FPS measurements remain open.
- [x] **T-203 Palette and drag & drop.** Draggable tile cards with remaining count (level
  limits), drop onto grid with placement preview and validation feedback, long-press to
  remove. Touch and mouse. Keyboard accessible (select tile, arrow keys, Enter).
  *Note 2026-09-05:* Drag & drop, brush tap placement, long-press clear, placement preview outline. Keyboard access still open.
  *Note 2026-09-05 (4):* Keyboard access done: focusable map with a cursor cell (arrows, Enter/Space place, Delete/Backspace clear, 1–9/0 pick a tile, Esc drops the brush), shortcut digits on the palette cards, `Semantics` label on the map. Tests in `app/test/map_view_test.dart`.
  *Note 2026-09-07:* Build/remove actions now have bounded undo/redo history, toolbar and keyboard controls, plus a persistent, cancellable placement-mode chip on the map. Simulation ticks intentionally close editing history so undo never rewinds time implicitly.
  *Note 2026-09-07 (2):* Simple mode is now an end-to-end kid-friendly presentation: plain-language goals, smiley indicators and cell conditions, friendly forecasts/results, goal-aware suggestions and no technical detail sheets or management values. Expert mode retains exact values and adds indicator sparklines with build-event markers.
- [x] **T-204 Indicator panel.** Ten gauges with trend arrows, tap opens detail sheet
  with raw values, units and a "Quelle / Source" link into `docs/model`.
  *Note 2026-09-05:* Ten gauges with detail line and tooltip hint. Source links into docs/model still open.
  *Note 2026-09-05 (4):* Tapping a gauge (long-press or tap in the compact strip) opens a detail sheet with hint, raw values, a one-line "how it is computed" sentence per indicator and a `url_launcher` link into the matching `docs/model` file.
- [x] **T-205 Overlays.** Toggleable heat-map overlays for noise, air, heat, green access,
  retail access, habitat quality. Colour-blind-safe palettes; legend with units.
  *Note 2026-09-05:* Nine overlays with colour-blind-safe ramps and legend.
  *Note 2026-09-07:* Overlay UX now identifies helpful versus harmful directions, uses simple-mode wording, preserves more of the base map, marks causal source cells optionally, closes directly from the legend, and corrects the air-quality layer's formerly inverted palette semantics.
  *Note 2026-09-08:* Starter overlays use three readable bands; applicable fields draw
  reference-threshold contours. Selecting a cell traces its nearest plausible sources, and
  what-if experiments switch the heatmap to a before/after improvement delta.
- [x] **T-206 Tile inspector.** Tap tile → per-field values, contributing emitters
  ("Lärm: 62 dB, davon Hauptstraße (2 Felder) 58 dB…").
  *Note 2026-09-05:* Inspector shows all per-cell fields. Breakdown by contributing emitters still open.
  *Note 2026-09-05 (3):* `Simulation.explainNoise/explainAir` list contributing tile types (count, nearest distance, level); shown in the inspector.
- [x] **T-207 Game loop and pace.** Play/pause, 1×/3×/10× ticks, turn mode (tick only on
  "End turn"). Autosave to local storage (`shared_preferences` / file), load/new game.
  *Note 2026-09-05:* Play/pause, step, 1×/3×/10×, new game with size slider. Autosave/load still open.
  *Note 2026-09-05 (2):* Autosave (2 s debounce) and restore via `shared_preferences` (BSD-3); test covers the round trip.
- [x] **T-208 Onboarding.** Three-step tutorial overlay explaining tiles, overlays and one
  feedback loop. Strings in ARB.
  *Note 2026-09-05:* `ui/onboarding.dart`: three steps (tiles, overlays and inspector, the housing → traffic → noise → attractiveness loop) with icon and colour illustrations, Skip/Next/Done, dismissible with Escape and by tapping outside. Shown once on first launch (`SaveStore.onboardingSeen`/`markOnboardingSeen`) and reachable again from the help icon in the level select app bar.

### Phase 3 — Levels and content

- [x] **T-301 Level format.** JSON level: grid size, initial map, allowed tiles with
  counts, starting budget, goals (indicator thresholds), turn limit. Loader + validation.
  *Note 2026-09-05 (3):* `Level` in the sim package: ASCII map, tile counts, goals (indicator or metric), turn limit, param overrides; levels in `data/levels/*.json` mirrored by the generator.
- [x] **T-302 Five starter levels.** Sandbox 16×16; "Dorf" (village, limited tiles);
  "Lärmschutz" (existing road, place housing); "Biotopverbund" (connect two forests);
  "Haushalt" (balance the budget). Goal texts in ARB.
  *Note 2026-09-05 (3):* Five levels: village, noise, habitat, budget, quarter. `test/level_solutions_test.dart` proves each is solvable with three stars.
- [x] **T-303 Level generator from open data (optional).** Script under `tools/` that
  converts a Copernicus Urban Atlas or ATKIS extract (stored in
  `/mnt/storage/code/stadtbau/data`, never committed) into a level JSON. Document the data
  license and attribution text required in-game.
  *Note 2026-09-17:* `tools/level_from_landcover.py`, documented in
  `docs/level-generator.md`, plus the `tuebingen` level it produced. Urban Atlas needs a
  CLMS login, so the dataset is LBM-DE2021 (BKG) instead — CC BY 4.0, whose terms ship with
  the data and require a visible source notice *and* a notice of modification; `Level`
  gained an `attribution` field that the level select screen shows and a test asserts,
  because dropping it still loads the level and silently breaks the obligation. The reader
  is stdlib-only: a GeoPackage is a SQLite database with WKB geometry behind a short
  header, so `sqlite3` reads it and no GDAL, fiona or geopandas has to be installed
  (`shapely` is used when present). Four things worth recording. (1) `ZUS_AKT` holds a
  comma-separated list with a trailing comma (`"O,"`, `"F,O,"`), not one flag, so an
  equality test against `"S"` matched none of the 7 277 solar sites — a rule that failed
  silently and would have shipped every solar farm as industry. (2) A main road is ~20 m
  wide and a river ~30 m, so neither ever wins a hectare on area; without a share
  threshold the Neckar came out as disconnected specks (1.3 % of cells against 5.0 % with
  it), and connectivity is exactly what the traffic and runoff models read. (3) Six tile
  types had no character in `levelMapLegend`, so no level could contain them — invisible,
  since everything compiles and runs; a test now asserts the legend covers every
  `TileType`. (4) The simulation is superlinear in cells (3.3 ms per tick at 16×16, 10–12
  at 24×24, 22–26 at 32×32), so the shipped level is 24×24: at 10× speed a tick has about
  100 ms. Also: the first goal set asked for biodiversity 50 and the whole green allowance
  reaches 39, so the level was unwinnable and only `level_solutions_test.dart` said so. The
  goals now sit at values one written plan demonstrably reaches. Measuring three plans
  showed what the model actually rewards: replacing the industrial estate beats growing one
  large connected wood (biodiversity 39 with recreation 93, against 49 with recreation 75),
  because habitat quality responds most to the threat that is *removed*, while recreation
  and heat want green *near people* — and the corridor compromise is worse at both than
  either specialist.
- [x] **T-304 Scoring and end screen.** Level goals evaluation, star rating, replay
  summary of indicator curves.
  *Note 2026-09-05 (3):* Goals panel with live progress, end dialog with 0–3 stars, best stars stored per level; level select screen with continue.
- [~] **T-305 Progressive learning missions.** Data-driven mission tiers, concepts and
  optional features; Starter/Guided/Explorer profiles; predict–act–observe–explain–debrief
  loop with all copy in DE/EN. Missions opt into complexity individually.
  *Note 2026-09-08:* Added the reusable schema and localized learning notebook for all five
  scenarios; the noise mission is the complete first teaching slice. Playtesting and staged
  mission beats remain open.
  *Note 2026-09-20:* Tübingen, the one mission with no beats and no prediction of its own, now
  has both — and writing them turned up what the level is actually about, which was not what I
  assumed. **The worked plan places no housing at all.** It converts industry, commercial and
  farmed land into forest, park and wetland and puts transit on the existing roads. Measured with
  an empty plan: housing is met in month one (95 against 88) and never drops, the reserve target
  arrives by month six on its own, and biodiversity, recreation and climate all fail (35/38,
  71/88, 71/84). Adding quarters makes biodiversity *worse* (35 → 33). So the prediction
  `tuebingen_green` offers convert / expand / wait, and `convert` is right because it was measured
  to be, not because it sounded like the lesson. Had I written the copy first I would have taught
  the opposite.
  That measurement also became a check. `learning_audit.dart` now runs every level with an empty
  plan and separates two things that look alike: a **floor** (met at the start and never lost —
  "do not wreck the quiet you already have", which is a legitimate goal) from a goal that **starts
  unmet and is reached by waiting**, where the clock solves what the panel asks the player for.
  Only the second is reported, and across all six levels it fires exactly once: tuebingen's reserve
  target. A first, coarser version that reported anything met by an idle run flagged seven goals on
  six levels and was mostly noise. A level where *every* goal is idle is a failure, not a note; that
  branch was verified by lowering tuebingen's thresholds to 1.
  *Note 2026-09-20 (2):* Constraint medals measured, and the comment in `level_plans.dart` that
  said a constraint "only means something if the constrained solution costs something" is now a
  check rather than a remark. Both medals were measured against their own plan variant:
  `habitat_no_water` solves in the same 60 months with 205 tiles instead of 207 and 400 k€ less,
  changing biodiversity not at all (87 either way) — it is free. `noise_no_roads` takes the noise
  score from **88 to 100** and saves 1 200 k€, costing only three months (21 against 18).
  Neither is a sacrifice; both reward noticing the better line of play.
  The audit flags a medal whose constrained plan *dominates* — solves no later and places no more
  tiles. That is deliberately strict: it reports `habitat_no_water` and stays silent on
  `noise_no_roads`, whose three months are a real if small price. Re-pricing the medals is level
  balance and so a design decision, left to the author; the check means it can no longer be
  forgotten.
  *Note 2026-09-21:* **The medals are priced, and one earlier conclusion here was wrong.**
  I reported that tuebingen's `budgetKEur >= 50 000` could not be made to bind, comparing an idle
  run and the worked plan *at month 120*. The game ends at the first moment every goal is met, and
  that is where it banks stars and medals. Read there, the worked plan wins in month 23 with
  **50 517 k€ against 50 000** — a margin of one per cent. The goal was already tight and needed no
  change; the measurement did. Reading a level at the end of its term describes a game nobody
  plays, and the audit's own `_playPlan` had that right all along.
  Re-measured at the winning moment, each tile type in every worked plan was dropped in turn to
  see what it is worth. On `habitat`, forest and meadow are required and water and park are free;
  on `noise`, only the housing is required. So:
  `habitat_no_water` became **`habitat_lean`**, a reserve target of 2 000 k€, priced from
  measurement so that both the ponds and the parks have to go — the plan leaves 856, without ponds
  1 266, without parks 1 806, without either 2 214. `habitat_fast` went 120 → 66 months against a
  plan that takes 60, and `noise_fast` 48 → 24 against a plan that takes 18 and a no-road line that
  takes 21, so both noise medals stay earnable together. `noise_no_roads` is unchanged: it costs
  three months, which is a real if small price.
  The audit's two checks were re-scoped in the same pass, because both were answering slightly the
  wrong question. The "costs nothing" note now applies only to a **pure ban** — months and tiles are
  the whole cost of giving a tile up and not the cost of hitting a target, so a reserve medal is no
  longer mis-flagged. The "reached by waiting" note now also asks whether the worked plan clears the
  goal with room to spare, measured at the winning moment: tuebingen's one per cent means it binds,
  and it is correctly silent. Both were verified by re-breaking them — the free ban put back, and a
  reserve threshold lowered to 40 000 where the plan clears it by 26 %.
  `level_test.dart` had re-typed `maxMonths: 48` as a literal and failed on the re-pricing rather
  than on a defect; it now asserts the property that matters, that a "finish quickly" medal asks for
  less time than the level allows.
  *Note 2026-09-16:* Staged mission beats added. `MissionBeat` in the sim package owns only
  when a beat fires — `afterMonths`, `afterTilesPlaced`, `afterGoalsMet`, `whenIndicatorBelow`
  — so a teaching moment arrives when the player can see what it is talking about rather than
  as instructions before anyone has touched the map. Beats are declared in mission order and
  only one is offered at a time, so a fast player still meets them one after another. The card
  sits in the goals panel and outranks the tactical `goalGuidance` hint while it is showing.
  Two beats per scenario, ten in all, DE and EN. Verified in a browser: the first village beat
  appears on the fourth home and replaces the hint (screenshot via the T-202 CDP harness); the
  German copy is covered by the i18n lint and the existing German widget tests, not visually.
  **The copy is a first pass and wants your voice** — the structure is the durable part.
  Broader playtesting remains open.
  *Note 2026-09-18:* `packages/stadtbau_sim/tool/learning_audit.dart` audits the whole teaching
  surface without a browser, and runs in CI. It checks every id the level data produces against
  the ICU branches in **both** ARB files — the i18n lint compares keys, not the branches inside
  a `select`, where a missing id renders the generic wording instead of failing — and it replays
  every mission along randomised paths plus its worked plan from `tool/level_plans.dart` (moved
  out of the solutions test so both can use it). Copy coverage is clean: 205 ids, both languages,
  identical branch sets; verified by deleting a German branch and watching the audit catch what
  the lint missed. `docs/missions.md` has the findings. The largest: **`habitat` and `tuebingen`
  are won before a single month passes** — on habitat after 124 of the plan's 207 tiles, so the
  end screen appears mid-build, the 240-month limit and the seasonal cycle never apply, and the
  maturation model the level exists to teach never decides anything (biodiversity 72 at month 0
  against a goal of 70, reaching 87 by month 120). Two month-triggered beats are unreachable as a
  consequence, and `tuebingen` ships with no learning block at all. All of these are authoring
  decisions, recorded rather than taken.
  *Note 2026-09-18 (2):* The habitat threshold was taken, on request. Its biodiversity goal moves
  70 → **80**, which the worked plan reaches at month 60 of 240 — by maturation alone, since it
  starts at 71.8 and climbs to a 86.8 plateau. One number fixes three things: the level is no
  longer won mid-build (the plan now places all 207 tiles before winning, where it used to end
  after 124), `recoveryMonths` and `biotopeStart` finally decide the mission that exists to teach
  them, and the `habitat_maturity` beat — copy already written as "Gib ihm Zeit" — fires for the
  first time. 80 rather than 84: the ceiling is 86.8, so a higher bar leaves no headroom for an
  imperfect plan and would make the `habitat_fast` medal (≤ 120 months) nearly impossible.
  **`tuebingen` is still won at month 0** and is a different problem — biodiversity there moves
  39 → 41 over 240 months, so no threshold makes time matter.
  *Note 2026-09-18 (3):* Three more of the audit's notes closed. `village_quiet_left` fired
  `afterMonths: 24` against a tutorial solved in 3 months; here the trigger was wrong, not the
  level — the beat says "look at what is still meadow and forest", which is a thing to notice once
  the village has taken shape — so it fires at `afterTilesPlaced: 16`, half the tile budget.
  **Every beat in every mission now fires on the worked solution.** And `tool/level_plans.dart`
  carries a variant of the noise and habitat plans that earns `noise_no_roads` and
  `habitat_no_water`, derived by filtering the plan so it cannot drift from it; the audit fails if
  a variant stops solving or stops earning its medal. They proved something worth knowing: the
  constrained solutions are as good as the originals (habitat identical, noise 3 months slower),
  so the two ponds and the side road cost budget and earn nothing. **A constraint medal is only
  meaningful if the constraint costs something.** Two notes remain, both authoring: the habitat
  housing goal is a preservation constraint the tactical hint cannot express, and `tuebingen`
  still has no learning block.
  *Note 2026-09-18 (4):* Both taken, on the user's choice from a written options brief.
  (1) A `guidanceProtect` stage for goals the level gives nothing to build toward — "Nothing you
  can build here raises {goal}. Protect what is already on the map." Two strings, no schema
  change: the test is `guidanceCandidatesFor` against the palette, which the audit already ran.
  (2) `tuebingen` gains `budgetKEur ≥ 50 000`, reached at month 23 of 120 — it spends 29 090 of
  its 34 000 k€ and recovers ~2 000/month, and the threshold was checked against four plan
  variants (12–23 months) before committing. Population was rejected: a 613-person window between
  trivial and impossible. (3) `tuebingen` gains a tier-1 learning block — concepts `mixed_city`,
  `tradeoffs`, `resilience` plus causalView/experiment/debrief — at **zero new copy**, since all
  three concept ids already carry Name/Cause/Model/Law in both languages. Beats and a prediction
  are deliberately absent rather than stubbed; ids without copy render the ICU fallback, which is
  the failure the audit exists to catch, and `level_test` now requires concepts rather than beats
  and says why.
  **A real bug fell out of (2):** `guidanceCandidatesFor` had never been updated for the six
  T-502 tiles, so the hint could not suggest `mixed_use` for housing, `school` for the budget,
  `wetland` for biodiversity, `solar_field` for climate, or `tram_stop`/`cycle_path` for
  commuting. Adding one goal to a level with a modern palette surfaced it. The audit is down to
  one note, and that one is informational.
- [x] **T-306 Counterfactual experiments.** Pin the current deterministic simulation,
  freely test builds and time, compare live indicator and overlay deltas, then keep or
  discard the branch without affecting the pinned city.
  *Note 2026-09-08:* Reversible in-game what-if experiments are available only in missions
  that opt in; exact deltas are reserved for Explorer mode.
- [x] **T-307 Challenge medals.** Evaluate the optional per-mission constraints declared in
  level data, persist medals and show alternative successful strategies in the debrief.
  *Note 2026-09-08:* Data-driven time, tile, indicator and budget constraints are evaluated
  on successful completion; earned medals persist locally and appear in debriefs and the
  scenario list. They stay out of Starter and Guided mission notebooks.

### Phase 4 — Platforms and release

- [x] **T-401 Web release build** to `/mnt/storage/code/stadtbau/build/web`, deploy target
  (static host). PWA manifest, icons (self-made).
  *Note 2026-09-05:* GitHub Pages at https://crispstrobe.github.io/stadtbau/ via `.github/workflows/pages.yml` (base href from the repo name). PWA manifest and own icons still open.
  *Note 2026-09-05 (2):* App icon for every platform generated by `tools/gen_icon.py` (Pillow, own work); PWA manifest named and themed. See `docs/release/icon.md`.
  *Note 2026-09-15:* The web build now serves everything from our own origin. Two separate third-party requests had to go. `flutter.js` loads the CanvasKit engine from `https://www.gstatic.com/flutter-canvaskit/<revision>/` unless the build sets `useLocalCanvasKit`, so the build uses `--no-web-resources-cdn`. That alone was not enough: with the engine local the app still rendered without any text, because Flutter's font fallback (`fontFallbackBaseUrl`, default `https://fonts.gstatic.com/s/`) downloads Roboto, and the app declared no font family. Roboto 400/500/700 are now bundled from the Flutter SDK's material_fonts artifact (Apache-2.0; the licence text ships in `app/assets/licenses/Roboto-Apache-2.0.txt` and is registered with `LicenseRegistry`, since Apache-2.0 requires it to travel with the binaries). Verified in headless Chrome with `--host-resolver-rules="MAP * ~NOTFOUND, EXCLUDE 127.0.0.1"`: the app renders complete, and every request is served by us. This is what T-702 asks for, one layer down.
  First load, gzipped: ~3.3 MB on Chromium browsers (2.2 MB engine, 0.9 MB app, 0.26 MB Roboto), ~4.0 MB elsewhere, where the generic CanvasKit variant is larger. Previously ~0.9 MB came from us and the rest from Google. The deploy drops the engine variants a build cannot reach — symbol maps always, `experimental_webparagraph` (needs an explicit `canvasKitVariant`), and the skwasm family (only a `--wasm` build uses it) — taking the artifact from 41.7 MB to 17.5 MB; the guards read the build's own config, so changing the flags changes what is kept. Both surviving variants were loaded and render identically.
  *Still open:* `--wasm` (dart2wasm + skwasm, dart2js + CanvasKit kept as an automatic fallback) also loads and renders identically, but is a runtime-speed question rather than a size one.
  *Note 2026-09-18:* **The guarantee does not hold any more, and the cause is a character.** `tools/web_origin_check.py` serves the build, drives real Chrome with every host but 127.0.0.1 resolving to nothing, and reports what tried to leave — it runs in CI after the web build and as `tools/check.sh origin`. It finds two requests to `fonts.gstatic.com`: CanvasKit falls back to `fontFallbackBaseUrl` for any glyph the bundled Roboto lacks, and the app's own copy uses twelve of them — the subscript in CO₂ on the main screen every tick, an arrow in the causal paths, and nine emoji that simple mode is built on. The About screen says there are no network requests while you play. `docs/web-payload.md` has four costed routes out; the cheapest complete one is Material icons for the emoji (already bundled, Apache-2.0, no new bytes) plus plain `CO2`/`->`. Until that lands the check tolerates `fonts.gstatic.com` as a dated named hole, so it guards against a *new* third party rather than not being wired up at all.
  Payload: the shipped params mirror is now values only — the `source` and `note` prose was 15 KB gzipped of every first load and nothing reads it at run time. First load 3314 → ~3299 KB. Measured but held: subsetting the three Roboto weights to European Latin saves a further 139 KB, which belongs with the font decision above rather than before it.
  *Note 2026-09-19:* The fallback hole is closed. Emoji in simple mode are Material icons,
  and the two remaining unsupported text glyphs use `CO2` and `->`, so the origin check's
  allow-list is empty again. Roboto is reproducibly subset by `tools/subset_fonts.py`; CI
  checks the committed files and the shipped Apache-2.0 notice records the modification.
  The release build makes no third-party request, and the measured Chromium first load is
  now 3191 KB gzipped (155 KB shell/fonts, 879 KB program, 2157 KB engine).
- [~] **T-402 Android.** SDK setup on a build machine, signing config outside the repo,
  `flutter build appbundle`. Verify AGPL notice screen (license text + sources) in-app.
  *Note 2026-09-05:* `.github/workflows/android-release.yml` (dry run by default, tag `v*` publishes to a GitHub release), release signing in `build.gradle.kts` with debug fallback, `docs/release/android.md`. Open: first CI run, upload keystore secrets, Play Console record.
  *Note 2026-09-19:* The first CI dry run passed end to end in 4m59s and uploaded both the
  APK and AAB as workflow artifacts (run 35434176884). With no repository keystore it used
  the documented debug-key fallback and labelled the artifacts unsigned; no release or
  store upload occurred. The Actions runtime majors were updated after the run exposed the
  Node 20 and `setup-java@v4` deprecation warnings. Open: upload-keystore secrets, Play
  Console record and a physical-device install/performance pass.
- [~] **T-403 iOS / macOS.** Requires a Mac runner. Document steps; Xcode project settings;
  App Store exception referenced in the About screen.
  *Note 2026-09-05:* `.github/workflows/ios-release.yml` + `tools/ios/build-ios-appstore.sh` + `app/ios/ExportOptions.plist` following `/mnt/volume1/appstore.md` (manual signing, unsigned archive, sign at export, `--upload-package`). Bundle id `com.crispstrobe.hectopolis` registered, profile "Hectopolis AppStore CI" created, 5 of 8 secrets set. Open: human creates the app record (`ASC_APP_ID`) and exports the `.p12` (`DIST_CERT_P12_BASE64`, `DIST_CERT_PASSWORD`); first dry run. `docs/release/ios.md`.
  *Note 2026-09-05 (2):* Store screenshot pipeline: `app/integration_test/screenshots_test.dart` + `app/test_driver/integration_test.dart` + `.github/workflows/screenshots.yml` (iPhone 6.9", iPad 13", Android emulator), see `docs/release/screenshots.md`.
  *Note 2026-09-08:* Prepared build 0.1.1+4 for external TestFlight; added
  versioned DE/EN beta/store copy, public privacy/support pages and an idempotent
  external-beta preparation workflow. Fixed the macOS screenshot watchdog.
  *Note 2026-09-19:* A fresh signed iOS dry run on current `main` passed in 4m53s
  (run 35438021512): archive, export and Apple's validation all succeeded and the
  21.8 MB IPA is retained as an artifact. The App Store upload and GitHub release steps
  were skipped, as required. This also compiles the LAN local-network declaration and
  client transport into the signed app. The remaining iOS work is physical-device review;
  the Mac App Store flow remains separate.
- [~] **T-404 Windows and Linux desktop** builds; installer via MSIX (Windows) and
  AppImage/Flatpak (Linux).
  *Note 2026-09-16:* The builds were already there — `desktop-release.yml` builds Linux, macOS
  and Windows on tags and has run green. The gap was the installers, and the Linux half is now
  done: `tools/package_appimage.sh` assembles an AppDir from the bundle with the desktop entry
  and icon in `app/linux/packaging`, and `desktop-release.yml` attaches the AppImage to the
  release next to the zip. Verified locally end to end: built on this box (gtk+-3.0 dev headers
  are present), packaged to a 10 MB AppImage, extracted, checked that every library resolves,
  then launched under Xvfb and screenshotted showing the real level-select screen.
  **Windows MSIX is still open** and is deliberately not guessed at: it needs the `msix` pub
  package, a licence allow-list entry and pubspec configuration, none of which can be exercised
  from Linux — committing it untested would only surface on a release tag. Flatpak is also open.
  *Note 2026-09-19:* A manual matrix run on current `main` passed on all three hosted
  runners (run 35438023002): Linux in 1m30s, macOS in 3m38s and Windows in 4m29s.
  It exposed a workflow usability gap rather than a build failure: manual dry runs packaged
  the bundles and then discarded them because only tag builds attached files to a release.
  The workflow now retains one 14-day artifact per platform on every run. Verified on the
  branch in run 35438349043: Linux (22.1 MB), macOS (58.3 MB) and Windows (13.5 MB) all
  built, packaged and uploaded through the Node 24 action without creating a release.
  *Note 2026-09-26:* The Windows job now also creates an MSIX with the `msix` package,
  unpacks it with the Windows SDK to validate its manifest and payload, checks its signer and
  retains it as a separately named 14-day artifact. It is explicitly a CI-only test package:
  the dependency's bundled development certificate has a public private key, so the workflow
  neither trusts it nor copies it into `dist/`, and tag releases cannot attach it by accident.
  A distributable MSIX remains blocked on either a Partner Center product identity (the Store
  signs the upload) or a private code-signing certificate. The exact handoff is documented in
  `docs/release/windows.md`. Verified in the complete hosted desktop matrix (run 36235351467):
  the Windows SDK unpacked the 16.24 MB `0.1.1.5` package, its manifest contained the x64 app,
  English/German resources and both internet/LAN capabilities, and the expected untrusted test
  signer was present. Flatpak remains open.
  *Note 2026-09-26 (2):* Linux packaging now also builds a single-file Flatpak from the same
  release bundle against `org.freedesktop.Platform//25.08`, with only display/GPU and networking
  sandbox permissions and no host-filesystem access. The workflow installs the bundle into an
  isolated user Flatpak installation and launches the real app under Xvfb before retaining or
  releasing it. See `docs/release/linux.md`. A future Flathub
  listing is separate source-manifest/review work, not required for the downloadable installer.
  Verified in hosted matrix run 36236387010: the 8.0 MB bundle installed as
  `app/com.crispstrobe.hectopolis/x86_64/stable`, stayed alive for the launch probe, reported the
  intended network/IPC/display/GPU permissions and no filesystem grant, and the other three
  desktop artifacts still built successfully.
- [x] **T-405 About / licenses screen.** Shows AGPL, the section 7 exception, third-party
  licenses (`THIRD_PARTY.md`), data attributions, link to source repository.
  *Note 2026-09-05:* `AboutScreen` like the sibling apps: header with version, provider, contact, privacy, disclaimer, license + section 7 exception, data sources, `showLicensePage` with the bundled AGPL/exception texts and data-source entries registered via `LicenseRegistry`. Widget tests in DE and EN.

### Phase 5 — Model depth

- [x] **T-501 Wind and dispersion.** Directional kernel for air pollution with a per-level
  prevailing wind; document with a Gaussian-plume reference.
  *Note 2026-09-17:* `air.windFromDegrees`, `windSpeedMs` and `windStretchPerMs` in
  `data/params/tiles.json`. The kernel applies the existing exponential to a distance measured in
  a wind-stretched frame — divided by the stretch downwind, multiplied upwind, and the crosswind
  component widened by its square root — and renormalises, so wind redistributes the emission
  rather than creating it. `windSpeedMs` is 0 by default, which is bit-for-bit the isotropic model,
  so scenarios opt in through the existing `paramOverrides` and no shipped level changed except
  `04_budget`, which gets the prevailing south-westerly its own brief already implies. Direction
  follows the meteorological convention so it can be read off a wind rose.
  `docs/model/air.md` documents it as a screening stand-in for a Gaussian plume, not a solution of
  one, and lists what it leaves out: no stability class, no plume rise, no wind rose, no downwash.
- [x] **T-502 Wetland, solar field, mixed-use, school, tram stop, cycle path** tile types
  with parameters and sources (extends §4.1 to ~16 types; sub-types per level).
  *Note 2026-09-17:* All six exist: ten tile types to sixteen, each with the full parameter set,
  a style, a drawing, and DE/EN name and description. Sources follow the file's own convention —
  a real citation where one exists (BKompV, InVEST, TR-55), an explicit `design:` or
  `initial estimate` where the value interpolates between already-calibrated tiles.
  Wetland joins open water in the runoff retention set, closing the gap T-503 left open.
  **`solar_field.co2PerHaYear` is −266 t/ha/yr**, derived from PV land use, yield and the UBA
  grid emission factor. That is an order of magnitude larger than anything else in the table and
  makes solar the strongest climate lever in the game. It was left at the derived value rather
  than quietly scaled; whether to cap or rescale it is a design decision, noted in
  `docs/model/tiles.md`. No shipped level allows the tile, so nothing existing changed.
  *Note 2026-09-17 (2):* `tram_stop` and `cycle_path` now act. The model has no public-transport
  mode — the bins are walk, bike and car, and the car share absorbs what would be transit — so a
  stop or a route takes a share of a cell's car trips away rather than adding a fourth mode, and
  everything downstream (traffic, noise, air, CO₂) follows without further change. Reach falls
  linearly to zero at the radius, a trip needs the infrastructure at both ends so the two are
  averaged, and cycling stops competing past `cycleCompetitiveKm`. `minCarShareFactor` keeps at
  least half the car trips, so no scenario is won by tiling stops. Anchored on the MiD 2017 modal
  split (10% public transport, 11% bicycle nationally) and 400 m stop catchment from planning
  practice; the reduction shares are design values and say so. Both placeholder `co2PerHaYear`
  figures are gone — the benefit is modelled once now, in the commute, rather than twice.
  *Note 2026-09-20:* Sub-types per level done, which closes T-502. `docs/model/tiles.md` already
  listed "which sub-type" as a correction applied once by hand when a Berlin land-use class became
  a game tile — the tile takes the denser end of the class. That is the right default and the wrong
  answer for a level that is *about* sprawl or *about* densification, so `data/params/tiles.json`
  grew a `subtypes` section and a level may name one per tile type
  (`"subtypes": {"housing_low": "terraced"}`). Parameters, name and description all follow.
  It is **per level, not per cell**: a mix would need the sub-type on the cell, which the world
  state does not carry, and that is written down rather than left to be discovered.
  Six sub-types, all measured rather than invented: residents per hectare from Umweltatlas Berlin
  **06.06 Einwohnerdichte 2021, Tab. 1** (column Wohngebiet, Stand 31.12.2021) and sealing from the
  01.02 table already in use, both corrected for streets the same way — `0,88 · Block` for
  residents, since the street has none. housing_low 35 / 56 / 68 Ew/ha, housing_high 185 / 235 / 362.
  **The cross-check is the find.** The class defaults were derived independently, from BauNVO
  floor-area ratios and Destatis floor space, and the Berlin measurements agree: housing_low's 45
  sits mid-range in 35–68. housing_high's 180 sits 3 % *below* its lightest sub-type rather than
  inside the range — and that is the right answer, not a defect, because the BauNVO derivation used
  the §17 ceiling and 1990s blocks are what building at that ceiling produces, while the denser
  sub-types are pre-war forms the ceiling would not permit. A test pins both with a 10 % tolerance,
  so a future edit that moves a default away from its measurements fails instead of surprising.
  A sub-type sets only what the Umweltatlas measures; `paramOverrides` still applies afterwards and
  wins, so a level can tune anything else.
  `tileSubtypeName`/`tileSubtypeDescription` are ICU `select`s, which have no exhaustiveness check —
  a missing branch renders `other`, so a level would quietly call its housing "Unknown".
  `app/test/subtype_copy_test.dart` checks both languages against the table and was verified by
  deleting a branch.
  **No shipped level names a sub-type yet**: doing so changes that level's balance, which is level
  design rather than model work — the same call made for `solar_field`.
- [x] **T-503 Water and runoff.** SCS curve number method (USDA, public domain) with
  sealing degree; flood risk indicator; wetlands and water as retention.
  *Note 2026-09-17:* `model/water.dart` implements the SCS curve number method in millimetres.
  The sealed and unsealed parts of a cell compose by TR-55's connected-impervious formula, so the
  existing `sealing` parameter finally has a consequence. Every number was read from a published
  table and checked against a second source, not recalled: pervious curve numbers from TR-55
  Table 2-2 for hydrologic soil group B (forest 55, meadow 58, park 61, cropland 78, built 61,
  impervious 98), verified against the USACE HEC-HMS tabulation; the design storm is 22.1 mm from
  KOSTRA-DWD-2020 grid field 081118 at 60 min / 5 a, extracted from the published table rather
  than estimated. A test re-derives the runoff equation independently so the code cannot drift
  from the method.
  Water retains: each water cell shares `retentionMmPerCell` among the runoff-producing cells in
  reach. That is **storage, not routing** — nothing knows which way the ground slopes, so a pond
  helps neighbours above it as much as below. `docs/model/water.md` is explicit about that.
  *Note 2026-09-20:* the flood indicator lands, so T-503 is closed. `Indicator.flood` is
  `100 · clamp(1 − meanRunoffMm / water.designStormMm)`. The reference is the design storm and
  not the 10 mm `floodRiskMm` threshold, because that was measured first: on uniform maps only
  `road` (13.32 mm) crosses 10 mm, so a threshold count would have scored a player on how many
  roads they drew and read 100 for a sheet of industry. The mean separates the archetypes
  (forest 100, village 93, suburb 90, industrial park 86, mixed town 84, dense quarter 67) and
  distinguishes the industrial park from the village where the cell count cannot — both have 16
  flood-risk cells and the park sheds twice the water. `tool/calibrate.dart` now reports runoff
  so that table is reproducible. The reason to spend the eleventh indicator now: water and
  wetland had retention and biotope value but no scored consequence, so the ponds a player
  builds for `habitat_no_water` cost budget and earned nothing. Wetland joined the retention set
  in T-502. Night noise is still reported and not scored.
- [x] **T-504 Causal loop view.** Diagram of §4.6 loops with live dominance highlighting.
  *Note 2026-09-16:* `packages/stadtbau_sim/lib/src/loops.dart` names the five loops and reads a
  strength for each off quantities the model already computes — the share of attractiveness that
  noise and air fail to deliver, revenue over revenue plus upkeep, in-commuters over job capacity,
  mean habitat threat, mean outstanding maturity. No new formulas: see `docs/model/loops.md` for
  what each reading is and why it stands for its loop. They are different quantities, so the view
  ranks them and refuses to invite comparison by number.
  Drawn as chains rather than a node graph: five loops sharing nodes tangle at phone width, and the
  readable thing is the order of the steps. Missions opt in through the existing
  `MissionFeature.causalView`; the sandbox always offers it. DE and EN.
  Writing the regrowth reading caught a modelling slip in my own first draft — it ignored
  `biotopeStart`, so a fresh meadow read as owing its whole value when the model already counts
  almost half. The test now pins it to `1 − biotopeStart`.
- [x] **T-505 Night noise and health.** L_night, WHO night guideline, exposure shares
  (WHO 2018 Environmental Noise Guidelines and WHO 2009 Night Noise Guidelines).
  *Note 2026-09-17:* L_night rides along in the existing noise pass — same geometry, same path
  attenuation, only the source term differs — from a per-tile `noiseNightReductionDb`. The road
  value of 6.5 dB is derived from the German urban day-night traffic split rather than assumed.
  **The task text conflated two WHO documents:** 40 dB L_night is the 2009 Night Noise Guidelines
  value (and LOAEL), while the 2018 Environmental Noise Guidelines recommend 45 dB for road
  traffic — 40 dB there is the *aircraft* figure. Both are now parameters with their own sources,
  and the indicators use 45 dB because this game's night noise is road traffic.
  Reported, not scored: the 0–100 noise indicator still scores the day level, so no scenario was
  silently rebalanced. A %HSD exposure-response curve was deliberately left out because the
  coefficients could not be read from a primary source from here; `docs/model/noise.md` says so.
- [x] **T-506 Time and seasons.** Yearly cycle for crop yield, ETI, heat waves.
  *Note 2026-09-17:* Model side done. A tick is a month and tick 0 is January, so the month is
  `tick % 12` and the cycle carries no state — replays stay deterministic. Two twelve-value series
  in `seasons.*`: `growth` scales the ETI term of cooling capacity, `heat` scales `uhiMaxC`.
  Both average **exactly 1.0** over the year, which is why seasons shipped without re-tuning a
  single scenario: a season redistributes within a year rather than adding warmth to one, and all
  five level solution tests passed unchanged. A test asserts that mean, after a first draft
  averaged 0.900 while its source field claimed 1.0. `amplitude` scales the departure from the
  mean, so 0 reproduces the season-free model exactly.
  *Note 2026-09-18:* A seasonal numerator needs a seasonal denominator. `heat.uhiMaxC` is the annual-mean ceiling, but the ceiling in force is that times the month's factor (4.1 K in July against a parameter of 3.0), and every score that turned a ΔT into 0–1 divided by the parameter. The result was that **for three months a year the climate indicator could not tell a dense quarter with sixteen hectares of park from one with none** — both 53.8 — and the heat term of residential attractiveness went to zero for every cell, which drives migration. `computeHeat` now publishes the ceiling it used as `fields.uhiMaxNowC` and everything divides through `fields.heatScoreOf`, so the two cannot drift apart. The same comparison now reads 64.0 against 62.5. The map's terrain tint deliberately keeps the absolute scale: a July city should look hotter. Three tests in `seasons_test.dart` pin it.
  Crop yield is represented through `growth` on cropland's evapotranspiration; an economic yield
  term is deliberately not modelled (`docs/model/seasons.md` says why).
  *Note 2026-09-19:* The visible half is complete. Meadow, cropland, forest, park and wetland
  ground — plus meadow blades and tree canopies — now read the same `growthAt(tick)` as the
  model. A factor of 1 preserves the previous colour exactly; winter shifts gently toward straw
  and the growing season toward lush green. The tint is clamped, tested at winter, annual mean
  and summer, and does not feed back into a score or alter any scenario balance.

### Phase 6 — Multiplayer (same WLAN, cross-play)

- [x] **T-601 Protocol package** `packages/stadtbau_net`: message schema (JSON, versioned),
  `Host` (authoritative sim, WebSocket server via `shelf_web_socket`) and `Client`.
  Tests with in-memory transport.
  *Note 2026-09-17:* Done except the WebSocket server, which moves to T-602 on purpose:
  `Transport` is an interface over send/receive/close, the only implementation here is an
  in-memory pair, and **no first-party code touches a networking API**. Opening a listening
  socket is the moment the About screen's "no network requests while you play" has to be
  restated for an opt-in LAN mode, and `tools/privacy_audit.sh` fails the build on any
  networking API — that guard should hold until the promise and the store listings are
  changed in the same commit, not be quietly bypassed under a protocol task. Documented in
  `docs/multiplayer.md`. **Design decision:** the wire carries commands, not state. Every
  client could instead run the simulation and agree because it is deterministic, but
  "deterministic" means the same binary on the same input — not two builds, two platforms
  or two web engines — so that trades a 20 ms round trip for a city that silently drifts
  apart. Instead every `applied`/`ticked` carries the host's `WorldState.hash()`, one
  disagreement throws the client's world away for a snapshot, and
  `SessionClient.resyncCount` is asserted to stay zero in a healthy session, which turns a
  determinism bug into a failing test. Three bugs the in-memory transport exposed, all of
  which would have been real over a socket: closing a connection from inside a message
  handler threw (a host rejecting a `hello` does exactly that); the whole host-client-host
  resync round trip was re-entrant, so delivery now happens from a microtask and
  `InMemoryTransport.settle()` gives tests a condition instead of a guessed number of
  pumps; and a seat cached its own copy of the player record, so `assignDistrict` wrote to
  one and the intent validator read the other — a district that silently did not apply. The
  privacy audit also now strips line comments before matching, since it was failing on the
  paragraph explaining where the socket *will* go, and a guard that fails on its own
  documentation teaches people to delete the documentation.
- [~] **T-602 Discovery.** mDNS/DNS-SD via `bonsoir` on native; room code + QR code
  (`qr_flutter`, BSD) as universal fallback; manual IP entry.
  *Note 2026-09-19:* The reachable, privacy-preserving slice is complete on native: a host
  binds an ephemeral IPv4 port behind a random 128-bit path, displays every usable
  `address:port/path` as text and QR, and a guest can paste or type one. The protocol has
  real loopback WebSocket coverage in addition to the in-memory tests. mDNS and camera
  scanning remain open; omitting mDNS avoids broadcasting a device name, while the QR can
  already be read by an ordinary phone camera as text. HTTPS web builds generally cannot
  open a plain `ws://` LAN connection because of mixed-content policy, so native-to-native
  is the supported first slice and T-606 is the path to browser cross-play.
  *Note 2026-09-19 (2):* The app-side `LanSession` boundary now has its own real loopback
  test — host, join, lobby, ready, start, turn and authoritative placement — rather than
  relying only on the lower-level transport test. WebSocket handshakes have an eight-second
  ceiling, so a stale or mistyped address returns to the setup screen with its existing
  connection error instead of leaving an indefinite spinner.
- [x] **T-603 Lobby UI.** Host or join, player list, district assignment, ready check.
  *Note 2026-09-17:* `SessionController` (the only place that knows both the protocol and
  Flutter) and `LobbyScreen`, with seven widget tests driving a real host and a real guest
  over the in-memory transport. **No menu entry yet, on purpose:** a player reaches a lobby
  by hosting or joining over a network and there is no transport until T-602, so wiring a
  button that cannot work would be worse than leaving it out; the screen is verified end to
  end regardless. Districts are vertical strips in player order, last strip taking the
  remainder — strips rather than quadrants because every strip touches both edges, while a
  quadrant would shield the player in the far corner from everyone else's noise and
  traffic, in a mode whose point is that effects cross borders. Building it found a gap in
  T-601: `SessionHost` broadcast to its clients, but the host's own screen is not a client,
  so a lobby on the hosting device never saw anyone arrive; `SessionHost.changes` now fires
  from `_broadcast`, the single place every outgoing message passes through. Two lessons
  about `flutter_test` cost most of the time and are written into `docs/multiplayer.md`:
  never wait on a timer (`Future.delayed(Duration.zero)` is a timer, and a faked clock will
  not run it — the in-memory transport now defers with microtasks, which is the matching
  primitive anyway), and never await a session teardown inside a test body. The transport
  also now defers a close **only when it is inside a message delivery**, which is the only
  time a broadcast controller cannot be closed; deferring unconditionally meant a session
  closed from a test body never told the other end.
- [x] **T-604 Turn-based co-op mode.** Districts, per-player tile budgets, shared
  indicators, cross-border effects visible in overlays.
  *Note 2026-09-17:* Rules and enforcement done in `stadtbau_net` with twelve tests; the
  game-screen half (district borders drawn, whose-turn banner, per-player stock in the
  palette) waits for T-602, since refactoring `GameScreen` around a session nobody can open
  yet would be scaffolding, not progress. Indicators are shared already — there is one
  simulation — and cross-border effects need no code at all, which is the point of a shared
  sim and divided build rights. Three decisions. **Time moves between rounds, not inside
  them**: when the last player ends their turn the host advances a year, so consequences
  land where everyone can see them and nobody plays against a city that changed under them
  mid-turn. **The money is shared and the tiles are not** — one municipal budget is the
  subject of the game, so the per-player allowance is the only private resource, and it is
  what makes a district a responsibility rather than a patch of map; a player's allowance
  is checked before the simulation so running out of parks reports as running out of parks.
  **Everyone sees everyone's stock**, because hiding it would stop people planning
  together. An end-turn arriving after the turn already moved on is ignored, so a late tap
  cannot skip the next player. Turn order survives a reconnect: a returning seat comes back
  where it was, not at the front of the queue, which `session_test.dart` asserts.
  *Note 2026-09-19:* The game-screen half is complete: district borders and ownership fill,
  active-player/round banner, end-turn control and private stock all read the authoritative
  session. Speed, undo, redo and new-game controls are unavailable in co-op. Placements and
  removals go through the host, including the host player's own actions, so district, turn
  and stock rules have one enforcement path.
- [x] **T-605 Reconnect and state sync.** Full state on join, diffs afterwards, hash check
  per tick, resync on mismatch.
  *Note 2026-09-17:* Protocol half done with T-601; the remaining half is UI (hold the token
  across a reconnect, decide when a seat is given up), which waits for T-603. Full state on
  join, the per-tick hash check and resync-on-mismatch came with T-601 — "diffs afterwards"
  is satisfied by sending commands rather than state, since a command *is* the diff and is
  three orders of magnitude smaller than the fields it changes. Added here: a resume token
  on `welcome`, and a disconnect during a game now **holds** the seat (`connected: false`)
  instead of dropping the player, because a dropped connection on a phone is the ordinary
  case and freeing the district would give their land away. Three judgement calls worth
  recording. A token for a seat that is still occupied is refused rather than honoured —
  otherwise a stale copy of a token is a way to evict someone and take their district. The
  host never expires a seat on its own: there is no clock in this package, and "how long do
  we wait for them" is a session-UI decision, so `releaseSeat` is explicit. And the token
  is kept out of `PlayerInfo` because the player list goes to everyone. The default token
  factory is a counter, which is right for the in-memory transport and wrong over a network,
  so it is a named constructor parameter rather than a default that quietly ships. None of
  it needed a protocol bump: both fields are optional, which is the additive-change rule
  from `docs/multiplayer.md` working as designed.
  *Note 2026-09-19:* The UI now retains the resume token for the lifetime of the session,
  shows a connection-lost banner and reconnects to the room code. A loopback test drops a
  real WebSocket, reclaims the held seat and proves the returned client and host hashes are
  equal. Deliberately not promised: recovery after the app process is killed, because the
  admission token is not written to storage.
- [ ] **T-606 Internet relay (later).** Dart server reusing the protocol; document hosting.

### Phase 7 — Quality and community

- [ ] **T-701 Accessibility pass.** Screen-reader labels for tiles and gauges, contrast,
  reduced motion, font scaling.
  *Note 2026-09-16:* First slice done — keyboard navigation, not screen readers. Every shortcut used to live on the map's focus node, so tabbing to a palette card or an app-bar button silently killed the digits, undo and Escape with nothing on screen to say why. Digits, undo/redo, Escape and a `?`/F1 help dialog are now global to the game screen (the app has no text input anywhere, so bare digits are unambiguous); cursor keys stay with the map, since making them global would fight focus traversal. Selecting a brush hands the keyboard back to the map, so a mouse pick or a Tab-and-Enter on a card no longer leaves the arrows dead. The cursor is drawn at full strength only while the map holds focus, and palette cards show a focus wash distinct from the selection border. The binding list — which already existed in DE and EN as a screen-reader label only — is now reachable from the overflow menu. Verified keyboard-only in a browser: digit picks a tile, arrows move, Enter places, Tab moves focus away and a digit still works and pulls focus back. Screen readers were deferred at that point to a later slice.
  *Note 2026-09-17:* Screen-reader support added, which was the bulk of this task. **Design
  decision:** the map is one labelled region whose `value` is the cursor cell, marked as a live
  region so a cursor move is announced. A semantics node per cell would be 256–576 nodes rebuilt
  on every placement, describing a grid a screen reader cannot usefully wander — and the app
  already navigates cell by cell with the arrow keys, so the region announces what that cursor
  stands on, read from the same fields the tile inspector shows. The ten gauges and the palette
  cards each carry one merged label with their reading, cost and stock, since a bar, a number, a
  smiley and a coloured border convey nothing without one. `app/test/semantics_test.dart` asserts
  the actual semantics tree, including the live-region flag.
  *Note 2026-09-18:* Contrast audit done, and it found two real failures in shipped UI rather
  than confirming what we assumed. A met goal was written in a colour measuring **4.14:1** on
  the light surface and 4.28:1 on the dark one, where WCAG 1.4.3 (which both BITV 2.0 and
  EN 301 549 point at) wants 4.5:1 for text — close enough to look fine and still short of
  the line. And the indicator bar measured **2.91:1** against its track at a reading of 0,
  under the 3:1 that WCAG 1.4.11 asks of a meter. Both now have one colour per theme, each
  the nearest shade of the same hue that clears the bar, so the warm-poor/cool-good meaning
  is unchanged. The part worth remembering: **the worst point of the gauge scale is the
  middle, not an end** — a warm-to-cool lerp passes through a desaturated tone whose
  luminance sits closest to the track, and in dark mode that midpoint measured 2.73:1 while
  both endpoints passed. `app/test/contrast_test.dart` therefore sweeps every reading from 0
  to 100 rather than checking the ends, and the colours are named constants the widgets and
  the test share, so a test that re-typed the literal cannot keep passing after someone
  changes the widget. Verified numerically and then looked at, rendered.
  *Note 2026-09-18:* Focus-order audit done — which was wrongly written off earlier as
  impossible here. Traversal order is a property of the widget tree, so a widget test can
  walk it; only a *screen reader* needs hardware this box does not have.
  `app/test/focus_order_test.dart` tabs through the game screen and asserts that the
  traversal closes (WCAG 2.1.2, no keyboard trap), that focus never falls off the tree, and
  that every app-bar action is reachable by Tab, plus that Shift-Tab exactly undoes a Tab.
  It found **nothing wrong**, which is the honest result: the order was already sound, and
  the value is that a refactor stranding a control now fails a test instead of shipping.
  Two notes for whoever extends it: the map runs a repeating animation controller, so the
  test needs the same reduce-motion `MediaQuery` that `render_map_png.dart` documents or
  `pumpAndSettle` never returns; and what a test cannot check is whether the order *makes
  sense to a person*, only that nothing is unreachable.
  *Note 2026-09-20:* Font scaling done, which was the last item in this task's own headline
  with no note against it — and unlike the focus-order audit, it did not come back clean.
  WCAG 1.4.4 asks for 200 % text without loss of content, and a Flutter overflow is exactly
  that: the clipped part is still laid out, still in the semantics tree, and invisible. It is
  *reported* rather than thrown, so every other widget test in `app/test` rendered these
  screens and said nothing. `app/test/text_scaling_test.dart` installs its own
  `FlutterError.onError` and sweeps three window sizes x four scales x two languages x simple
  and expert mode — 48 configurations — attributing each overflow to the widget that caused it,
  so a failure names a file rather than a pixel count.
  It found three real defects, one of them at **default settings**: the compact palette strip
  clipped by 4 px at 100 % text on any narrow window, in both languages, in shipped code. At
  200 % that strip and the indicator strip clipped by up to 86 px, and the roomy app bar
  overflowed by 87 px on a 1400 px desktop.
  Two causes, both the same mistake. A horizontal list has to state its own height, and both
  strips stated a literal that knew nothing about the text scaler; they now take their height
  from their content with the old literal as a floor, so the default layout is unchanged.
  **Scaling the literal by the text scaler was tried first and is not good enough** — the
  content does not grow linearly (a 26 px icon does not scale at all, a line box grows faster
  than its font size), so one factor was simultaneously too generous for the palette and 22 px
  short for the indicators. The app bar's breakpoints were in pixels while what had to fit was
  text: at 200 % a 1400 px window has the room of a 700 px one, so the breakpoints are now in
  text-sized units and a large-text desktop falls back to the layouts small windows already use.
  Two notes for whoever extends this. The test must restore `FlutterError.onError` **before**
  it calls `expect`, or the binding asserts and the assertion arrives during teardown — which
  turned every real failure into a six-minute cascade that hid the failure itself. And it must
  install the same four localization delegates the app does: without the Cupertino one a German
  build logs a warning through `FlutterError`, which this test forwards rather than swallows.
  *Note 2026-09-20 (2):* `docs/accessibility.md` collects the five audits, which until now existed
  only as notes in this file. It is organised around one distinction — which WCAG criteria are held
  by a test that fails, which by a person looking, and which by neither — because "accessible" is
  easy to claim and the claim is what rots. It records the three findings worth carrying forward:
  the worst point of a gauge scale is its middle rather than an end; a Flutter overflow is a 1.4.4
  failure that no ordinary widget test can see, because it is reported rather than thrown; and a
  stated height is a scaling bug waiting to happen, which scaling the literal does not fix.
  *Note 2026-09-21:* **An assistive technology now reads this app, in CI.**
  `tools/a11y_probe.py` stands up a private D-Bus session, an AT-SPI bus, Xvfb and the real Linux
  build, then walks the tree over D-Bus the way a screen reader does and fails if the labels it is
  told to expect are not announced. It reads the onboarding dialog unprompted — "How Hectopolis
  works", "Step 1 of 3", "Place tiles", the body text, and the Skip and Next buttons as
  `push button`. Every other accessibility test asserts Flutter's own semantics tree from inside
  the process; this is the first that proves any of it survives the journey out through GTK's ATK
  bridge onto the bus, which is where an assistive technology actually reads.
  **A correction, because I reported the opposite.** I first concluded that Flutter was not
  publishing semantics under AT-SPI — the tree stopped at the window — and changed `main.dart` to
  force semantics on. That diagnosis was wrong and the change was reverted. GTK's bridge answers
  `GetChildren` with an empty list while reporting a correct `ChildCount`, so my probe was blind,
  not the app. A stock build with no flags exposes the whole tree. Real clients use
  `GetChildAtIndex`, and the probe now does too.
  *Note 2026-09-21 (2):* the probe's first CI run failed while passing locally, and the reason is
  worth keeping: this box starts the app in English, GitHub's runner starts it in German, so the
  expected labels never matched. `--expect` now takes `|` alternatives and the check lists both
  languages — pinning a locale would need one generated on the machine and would stop testing what
  a real user sees. Reproduced locally under `LC_ALL=de_DE.UTF-8` before and after the fix.
  It also merged before CI ran, which is its own lesson: `main` has no branch protection, so there
  are no required checks, so `gh pr merge --auto` has nothing to wait for and merges immediately.
  Enabling `allow_auto_merge` on the repository was necessary but not sufficient; "merge when
  green" needs required status checks, which is a policy decision left to the owner. Until then the
  discipline is to wait for checks and merge by hand.
  Two environment traps are written into the tool: the AT-SPI bus puts its socket under `$HOME`,
  and a home directory on a network filesystem cannot host a unix socket, so it points
  `XDG_CACHE_HOME` at local scratch; and `at-spi2-core` is not on GitHub's Ubuntu image, so CI
  installs it.
  **Open:** the probe proves the labels reach the bus, not that they are *good* — nobody has sat
  with Orca, VoiceOver or TalkBack and tried to play, which is the judgement a machine cannot
  make. iOS and Android remain unexercised.
- [x] **T-702 Telemetry-free analytics.** None by default; optional local statistics only.
  *Note 2026-09-17:* The guarantee already held — there is no networking API anywhere in
  first-party code, and the dependency list is seven packages none of which reports anything.
  So the work was turning a claim in a user-facing string into an invariant CI can fail on.
  `tools/privacy_audit.sh`, wired into `check.sh`, fails if a networking API appears in
  first-party code, if an analytics or crash-reporting package enters the **lock file** (so a
  transitive dependency cannot slip one in), or if the app writes a `shared_preferences` key that
  `docs/privacy.md` does not document. All three arms were verified by making each one fail on
  purpose and checking the exit code, not just the message.
  `docs/privacy.md` lists the five stored keys, names `url_launcher` as the single outbound path
  and why it cannot fetch anything back, and records that the web build serves its own engine and
  font so a first load contacts nobody — the two requests to Google that Flutter makes by
  default. Local statistics are the stars and medals already kept for the player; nothing is
  aggregated, and no identifier of any kind is generated, because nothing is sent that would need
  one.
- [x] **T-703 Model documentation site.** `docs/model` rendered as a static site with
  formulas; "Quellen" page listing every dataset and law used.
  *Note 2026-09-17:* `tools/build_docs_site.dart` renders `docs/` into `docs/_site/` and
  the pages workflow writes it into `app/build/web/docs`, so one deployment publishes the
  game and its documentation and the in-app links are same-origin. Two decisions worth
  recording. First, no maths renderer: KaTeX or MathJax from a CDN would have been the one
  third-party request left in the project, directly against T-702, so formulas are typeset
  from the backticked text the docs already contain (a paragraph that is nothing but one
  code span becomes a display formula). Second, the generator has no dependencies and
  implements only the markdown the docs use — it *fails* on an image, a block quote, a
  nested list, an unbalanced backtick or a link to an unpublished page, with file and line,
  rather than emitting literal markdown nobody would trace back. All four guards were
  checked by deliberate failure, as was the one that catches a new doc missing from the
  navigation. The "Quellen" page is generated from the 379 `source` fields in
  `data/params/tiles.json`: 182 of them (48 %) cite a law, standard, dataset or paper, and
  the remaining 197 are grouped by the reason they carry none — design decision,
  derivation, calibration, initial estimate awaiting T-103, or not applicable — so the
  estimates are on the page rather than hidden behind it. An authority anywhere in the
  string wins over the `design:` prefix, because "design, anchored on MiD 2017" does rest
  on MiD 2017 and filing it as a bare design decision would understate it; the page tags
  it as anchored rather than cited. The page also asserts that every parameter appears
  exactly once. Along the way: three screens each carried their own copy of a
  `github.com/CrispStrobe/stadtbau/blob/main/docs/model/...` URL, which only resolved
  through GitHub's rename redirect and showed raw markdown when it did; they now share
  `app/lib/ui/doc_links.dart` and point at the rendered pages.
- [x] **T-704 Contributor guide** for adding tile types and parameters with citations.
  *Note 2026-09-17:* `docs/adding-a-tile-type.md`, written straight after adding six of them, so
  the traps listed are the ones that actually bit: `TileStyle.of` null-asserts its map so a
  missing entry is a runtime crash rather than a compile error; ICU `select` has no
  exhaustiveness so a missing name shows as the fallback; `_isRetention` in the water model is a
  plain `==` chain; and digits reach only the first ten of sixteen tiles. Also records the two
  judgement calls worth passing on — normalise art against the range a field actually occupies
  rather than 0–1, and put a tile's *purpose* in the model rather than in an invented
  per-hectare figure. Linked from `CONTRIBUTING.md`.

---

## 8. Source register (keep current)

| Topic | Source | License / status | Used for |
|---|---|---|---|
| Biotope values | Bundeskompensationsverordnung Anlage 2 | German federal law, § 5 UrhG public domain | Tile biotope value |
| Habitat quality, urban cooling, nature access | InVEST user guide and code (Natural Capital Project) | Apache-2.0 | Formulas and defaults |
| Road-effect zone | Forman & Deblinger 2000 (Conservation Biology 14, 36–46); Reijnen & Foppen, traffic disturbance of breeding birds | Scientific papers (values only) | Road threat distance in habitat quality |
| Noise | Directive (EU) 2015/996 Annex II (CNOSSOS-EU); TA Lärm | EU law; German administrative rule | Emission, propagation, limits |
| Noise emission of commercial and industrial land | DIN 18005-1 Ziffer 5.2.3 flächenbezogene Schallleistungspegel, values as reported in public legal literature (Versteyl/Storr/Schiller) | Values only; standard text not reproduced | Commercial and industry noise emission |
| Air | EMEP/EEA air pollutant emission inventory guidebook; UBA | Free, EEA standard re-use | Emission factors |
| Deposition and carbon, urban trees | Nowak et al. (i-Tree publications), incl. Nowak et al. 2013 (Environ. Pollut. 178) | Scientific papers (values only) | Sink coefficients; park CO₂ |
| Density | BBSR, BauNVO, Destatis (living space per person) | Public | Residents and jobs per ha |
| Population grid | Zensus 2022 100 m grid | dl-de/by-2.0 | Calibration, level generator |
| Mobility | Mobilität in Deutschland 2017 (aggregated results) | Public report | Mode share by distance |
| Municipal finance | Destatis kommunale Finanzen | Public | Tax and cost coefficients |
| Green-space upkeep | GALK-Kennzahlen zur Unterhaltung von Grünanlagen (2012, in Stadt+Grün) | Public professional benchmarks (values only) | Park and meadow maintenance |
| Compensation and wetland creation | Difu, Folgekosten der Siedlungsentwicklung (REFINA Band III, 2009), after TMLNU 2003 | Public research report (values only) | Wetland and meadow creation cost |
| Employment density | GIFPRO / Vallee et al. 2012 Flächenkennziffern, as applied in municipal Gewerbeflächenkonzepte (Difu methodology) | Public reports (values only) | Jobs per hectare |
| Retail | HDE / BBSR Nahversorgung studies | Public reports (values only) | Floor space per resident, radii |
| Recreation | WHO Urban green spaces (2016/2017); 3-30-300 rule (Konijnendijk 2021) | Public / paper | Access thresholds |
| Runoff | USDA SCS curve number (NRCS TR-55) | US public domain | Water module |
| Land-use carbon | UBA, Emissionen der Landnutzung (LULUCF); Waldgesamtrechnung (Thünen für Destatis); Bundeswaldinventur 2022 | Public federal reporting | CO₂ per hectare of forest, grassland, cropland |
| Soil carbon after land-use change | Poeplau & Don 2013 (Geoderma 192); Poeplau et al. 2017 (Sci. Rep. 7) | Scientific papers (values only) | Meadow sink after conversion |
| Peatland carbon | Greifswald Mire Centre; Commun. Earth Environ. 2024, emission factors for rewetted peatlands | Public / papers (values only) | Wetland sink |
| Soil sealing by land use | Umweltatlas Berlin 01.02 Versiegelung 2021 (SenStadt Berlin) | dl-de/zero-2.0 (no attribution required; we attribute anyway) | Sealed fraction of the built tiles |
| Land use maps | Copernicus Urban Atlas, CORINE, ATKIS (open Länder) | Copernicus free; dl-de/by-2.0 | Level generator |
| Land cover, Germany | Landbedeckungsmodell LBM-DE2021 (BKG) | CC BY 4.0, prescribed Quellenvermerk and modification notice | Level generator (T-303); the `tuebingen` level |
| Game model references | Micropolis (GPL-3), Citybound (AGPL-3), Forrester Urban Dynamics | Read only | Design inspiration |

Anything not in this table must be added here with its license before it is used.
