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

| id | DE | EN | Category | Residents/ha | Jobs/ha | Sealing | Biotope value (BKompV 0–24) | Noise emission L_eq dB(A) at tile edge |
|---|---|---|---|---|---|---|---|---|
| `meadow` | Wiese | Meadow | nature | 0 | 0 | 0.00 | 13 (mesophiles Grünland) | – |
| `cropland` | Acker | Cropland | nature | 0 | 1 | 0.00 | 6 (Intensivacker) | – |
| `forest` | Wald | Forest | nature | 0 | 0 | 0.00 | 17 (Laubwald mittleres Alter) | – |
| `water` | Gewässer | Water | nature | 0 | 0 | 0.00 | 16 (naturnahes Stillgewässer) | – |
| `park` | Park | Park | green-urban | 0 | 2 | 0.15 | 9 (Parkanlage mit Baumbestand) | – |
| `housing_low` | Einfamilienhäuser | Detached housing | residential | 45 | 3 | 0.45 | 5 (locker bebaut mit Gärten) | 45 |
| `housing_high` | Mehrfamilienhäuser | Apartment blocks | residential | 180 | 15 | 0.75 | 2 (dicht bebaut) | 50 |
| `commercial` | Gewerbe / Einzelhandel | Commercial / retail | work | 0 | 100 | 0.85 | 2 | 58 |
| `industry` | Industrie | Industry | work | 0 | 45 | 0.90 | 1 | 65 |
| `road` | Hauptstraße | Main road | infrastructure | 0 | 0 | 0.95 | 0 | 60 per 100 m segment at 10 000 Kfz/24h (sum of segments ≈ 58 dB at 100 m) |

Sources to verify against: BKompV Anlage 2 (biotope values, gesetze-im-internet.de),
BBSR "Städtebauliche Dichte" and BauNVO (GRZ/GFZ → residents and sealing), Destatis
(47.4 m² living space per person), TA Lärm and CNOSSOS-EU (emission levels), Copernicus
Imperviousness (sealing by land use).

### 4.2 Spatial fields (recomputed each tick, O(cells × kernel))

| Field | Emitters | Propagation | Sinks / modifiers | Read by |
|---|---|---|---|---|
| **Noise** L_den (dB) | road (100 m segments, emission scaled by 10·log10(Q/10 000)), industry, commercial, housing | Every tile is a point/area source: −6 dB per doubling from the 50 m tile boundary (ISO 9613-2). Road segments summed energetically reproduce the −3 dB per doubling of a line (CNOSSOS-EU segmentation). | Forest / park in the path: −2 dB per tile (foliage, CNOSSOS ground/foliage attenuation, simplified); housing_high blocks −5 dB per tile (screening). | Housing exposure vs TA Lärm limits (WA 55 day / 40 night; MI 60/45). |
| **Air pollution** index 0–100 | road (NOx), industry (PM, NOx), commercial (delivery traffic), commute-derived traffic | Exponential kernel exp(−d/L), L = 300 m (3 tiles), isotropic (no wind in v1). | Forest −20 %, park −10 %, meadow −5 % local deposition (i-Tree / Nowak et al. magnitudes). | Health/attractiveness of residential tiles. |
| **Cooling / heat** ΔT (°C) | Every tile has cooling capacity CC = 0.6·shade + 0.2·albedo + 0.2·ETI (InVEST Urban Cooling). | Green tiles ≥ 2 ha (connected) cool neighbours up to 100 m (InVEST default d_cool). | UHI magnitude 3.5 °C × (1 − CC) for sealed tiles. | Recreation, health, attractiveness. |
| **Green access** | park, forest, meadow, water (≥ 0.5 ha ⇒ any tile qualifies) | Boolean within 300 m (3 tiles, WHO / 3-30-300 rule); quality weight by biotope value and size. | – | Recreation indicator per residential tile. |
| **Retail access** | commercial (retail floor space 2 000 m² per tile ≈ supply for 1 400 residents at 1.4 m²/resident, HDE) | Huff model: P_ij = S_j·d_ij^−λ / Σ, λ = 2, walking radius 700 m (BBSR Nahversorgung). | – | Shopping indicator; retail revenue → commercial viability. |
| **Job access** | commercial, industry, housing_high (local services) | Gravity: A_i = Σ_j J_j·exp(−d_ij/2 km). | – | Commute distance, mode share, traffic. |
| **Habitat quality** 0–1 | nature + park tiles | Base = biotope value / 24. Threats (InVEST Habitat Quality): road (w 1.0, max dist 300 m), industry (0.8, 500 m), housing_high (0.5, 200 m), commercial (0.6, 300 m), decay linear. | Patch connectivity via 8-neighbourhood; species-area S = c·A^z, z = 0.25 (MacArthur–Wilson / Arrhenius). | Biodiversity indicator. |
| **Traffic** (vehicles/day) | Derived from commutes (see 4.4) routed via nearest road tiles. | Assigned to road tiles; feeds noise and air. | – | Noise, air. |

### 4.3 Stocks (system dynamics, per tick = one game month)

| Stock | Inflow | Outflow | Notes |
|---|---|---|---|
| Population P | Immigration = capacity_free × attractiveness × 0.05 | Emigration = P × (1 − attractiveness) × 0.02 | capacity = Σ residents/ha of residential tiles |
| Jobs filled J | min(jobs_capacity, P × labour_participation 0.52) | – | participation from Destatis Erwerbstätigenquote |
| Budget B (€) | Taxes: 600 €/resident/yr (Einkommensteuer-Gemeindeanteil), 2 100 €/job/yr (Gewerbesteuer), 180 €/resident/yr (Grundsteuer) | Maintenance: road 25 000 €/ha/yr, park 20 000 €/ha/yr, other 2 000 €/ha/yr; building costs on placement | Annual figures ÷ 12 per tick. Sources: Destatis kommunale Finanzen, BBSR. |
| Habitat index H | Recovery towards potential (biotope value) with τ = 60 months for meadow, 240 for forest | Immediate loss when a nature tile is replaced | Newly planted forest starts at 30 % of its potential biotope value. |
| CO₂ balance (t/yr) | Sequestration: forest −10 t/ha/yr, meadow −1, wetland (later) −3 | Emissions: industry 400 t/ha/yr, commercial 60, housing_high 50, housing_low 25, commute km × 0.15 kg | Magnitudes from UBA / Thünen forest inventory; verify. |

### 4.4 Commuting

For each residential tile: workers = residents × 0.52. Distribute to job tiles with the
gravity kernel. Mean commute distance d̄ per tile. Mode share by distance (MiD 2017):
≤ 1 km walk 0.6 / bike 0.2 / car 0.2; 1–3 km walk 0.2 / bike 0.35 / car 0.45; > 3 km car 0.8.
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
- [~] **T-115 Performance.** 24×24 map full tick < 16 ms on desktop, < 50 ms on a mid
  Android phone (measure with `benchmark_harness`). Optimise kernels if needed.
  *Note 2026-09-05 (3):* 180 → 38 ms per tick on a loaded VPS (`benchmark/tick_benchmark.dart`); desktop and phone targets still to measure on real hardware.

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
- [ ] **T-303 Level generator from open data (optional).** Script under `tools/` that
  converts a Copernicus Urban Atlas or ATKIS extract (stored in
  `/mnt/storage/code/stadtbau/data`, never committed) into a level JSON. Document the data
  license and attribution text required in-game.
- [x] **T-304 Scoring and end screen.** Level goals evaluation, star rating, replay
  summary of indicator curves.
  *Note 2026-09-05 (3):* Goals panel with live progress, end dialog with 0–3 stars, best stars stored per level; level select screen with continue.

### Phase 4 — Platforms and release

- [x] **T-401 Web release build** to `/mnt/storage/code/stadtbau/build/web`, deploy target
  (static host). PWA manifest, icons (self-made).
  *Note 2026-09-05:* GitHub Pages at https://crispstrobe.github.io/stadtbau/ via `.github/workflows/pages.yml` (base href from the repo name). PWA manifest and own icons still open.
  *Note 2026-09-05 (2):* App icon for every platform generated by `tools/gen_icon.py` (Pillow, own work); PWA manifest named and themed. See `docs/release/icon.md`.
- [~] **T-402 Android.** SDK setup on a build machine, signing config outside the repo,
  `flutter build appbundle`. Verify AGPL notice screen (license text + sources) in-app.
  *Note 2026-09-05:* `.github/workflows/android-release.yml` (dry run by default, tag `v*` publishes to a GitHub release), release signing in `build.gradle.kts` with debug fallback, `docs/release/android.md`. Open: first CI run, upload keystore secrets, Play Console record.
- [~] **T-403 iOS / macOS.** Requires a Mac runner. Document steps; Xcode project settings;
  App Store exception referenced in the About screen.
  *Note 2026-09-05:* `.github/workflows/ios-release.yml` + `tools/ios/build-ios-appstore.sh` + `app/ios/ExportOptions.plist` following `/mnt/volume1/appstore.md` (manual signing, unsigned archive, sign at export, `--upload-package`). Bundle id `com.crispstrobe.hectopolis` registered, profile "Hectopolis AppStore CI" created, 5 of 8 secrets set. Open: human creates the app record (`ASC_APP_ID`) and exports the `.p12` (`DIST_CERT_P12_BASE64`, `DIST_CERT_PASSWORD`); first dry run. `docs/release/ios.md`.
  *Note 2026-09-05 (2):* Store screenshot pipeline: `app/integration_test/screenshots_test.dart` + `app/test_driver/integration_test.dart` + `.github/workflows/screenshots.yml` (iPhone 6.9", iPad 13", Android emulator), see `docs/release/screenshots.md`.
- [ ] **T-404 Windows and Linux desktop** builds; installer via MSIX (Windows) and
  AppImage/Flatpak (Linux).
- [x] **T-405 About / licenses screen.** Shows AGPL, the section 7 exception, third-party
  licenses (`THIRD_PARTY.md`), data attributions, link to source repository.
  *Note 2026-09-05:* `AboutScreen` like the sibling apps: header with version, provider, contact, privacy, disclaimer, license + section 7 exception, data sources, `showLicensePage` with the bundled AGPL/exception texts and data-source entries registered via `LicenseRegistry`. Widget tests in DE and EN.

### Phase 5 — Model depth

- [ ] **T-501 Wind and dispersion.** Directional kernel for air pollution with a per-level
  prevailing wind; document with a Gaussian-plume reference.
- [ ] **T-502 Wetland, solar field, mixed-use, school, tram stop, cycle path** tile types
  with parameters and sources (extends §4.1 to ~16 types; sub-types per level).
- [ ] **T-503 Water and runoff.** SCS curve number method (USDA, public domain) with
  sealing degree; flood risk indicator; wetlands and water as retention.
- [ ] **T-504 Causal loop view.** Diagram of §4.6 loops with live dominance highlighting.
- [ ] **T-505 Night noise and health.** L_night, WHO night guideline 40 dB, annoyance
  curves (WHO 2018 Environmental Noise Guidelines, free).
- [ ] **T-506 Time and seasons.** Yearly cycle for crop yield, ETI, heat waves.

### Phase 6 — Multiplayer (same WLAN, cross-play)

- [ ] **T-601 Protocol package** `packages/stadtbau_net`: message schema (JSON, versioned),
  `Host` (authoritative sim, WebSocket server via `shelf_web_socket`) and `Client`.
  Tests with in-memory transport.
- [ ] **T-602 Discovery.** mDNS/DNS-SD via `bonsoir` on native; room code + QR code
  (`qr_flutter`, BSD) as universal fallback; manual IP entry.
- [ ] **T-603 Lobby UI.** Host or join, player list, district assignment, ready check.
- [ ] **T-604 Turn-based co-op mode.** Districts, per-player tile budgets, shared
  indicators, cross-border effects visible in overlays.
- [ ] **T-605 Reconnect and state sync.** Full state on join, diffs afterwards, hash check
  per tick, resync on mismatch.
- [ ] **T-606 Internet relay (later).** Dart server reusing the protocol; document hosting.

### Phase 7 — Quality and community

- [ ] **T-701 Accessibility pass.** Screen-reader labels for tiles and gauges, contrast,
  reduced motion, font scaling.
- [ ] **T-702 Telemetry-free analytics.** None by default; optional local statistics only.
- [ ] **T-703 Model documentation site.** `docs/model` rendered as a static site with
  formulas; "Quellen" page listing every dataset and law used.
- [ ] **T-704 Contributor guide** for adding tile types and parameters with citations.

---

## 8. Source register (keep current)

| Topic | Source | License / status | Used for |
|---|---|---|---|
| Biotope values | Bundeskompensationsverordnung Anlage 2 | German federal law, § 5 UrhG public domain | Tile biotope value |
| Habitat quality, urban cooling, nature access | InVEST user guide and code (Natural Capital Project) | Apache-2.0 | Formulas and defaults |
| Noise | Directive (EU) 2015/996 Annex II (CNOSSOS-EU); TA Lärm | EU law; German administrative rule | Emission, propagation, limits |
| Air | EMEP/EEA air pollutant emission inventory guidebook; UBA | Free, EEA standard re-use | Emission factors |
| Deposition by trees | Nowak et al. (i-Tree publications) | Scientific papers (values only) | Sink coefficients |
| Density | BBSR, BauNVO, Destatis (living space per person) | Public | Residents and jobs per ha |
| Population grid | Zensus 2022 100 m grid | dl-de/by-2.0 | Calibration, level generator |
| Mobility | Mobilität in Deutschland 2017 (aggregated results) | Public report | Mode share by distance |
| Municipal finance | Destatis kommunale Finanzen | Public | Tax and cost coefficients |
| Retail | HDE / BBSR Nahversorgung studies | Public reports (values only) | Floor space per resident, radii |
| Recreation | WHO Urban green spaces (2016/2017); 3-30-300 rule (Konijnendijk 2021) | Public / paper | Access thresholds |
| Runoff | USDA SCS curve number (NRCS TR-55) | US public domain | Water module |
| Land use maps | Copernicus Urban Atlas, CORINE, ATKIS (open Länder) | Copernicus free; dl-de/by-2.0 | Level generator |
| Game model references | Micropolis (GPL-3), Citybound (AGPL-3), Forrester Urban Dynamics | Read only | Design inspiration |

Anything not in this table must be added here with its license before it is used.
