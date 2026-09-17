# Adding a tile type

Task T-704. Written straight after adding six of them (T-502), so the traps
listed here are the ones that actually bit, not the ones that seem likely.

Read `CONTRIBUTING.md` first for the licence and sourcing rules. This file is
only the mechanics.

## The short version

```
data/params/tiles.json                       the parameters, each with a source
packages/stadtbau_sim/lib/src/tile_type.dart the enum value and its id
app/lib/ui/tile_style.dart                   colour and icon
app/lib/ui/map_view.dart                     how it is drawn
app/lib/l10n/app_en.arb, app_de.arb          name and description, both files
dart run tools/gen_params.dart               regenerate the mirror
tools/check.sh                               analyze, tests, i18n lint, licences
```

## 1. Parameters, with sources

Add one entry to `tiles.json` under `tiles`, with **every** key the existing
entries carry. The loader fails loudly on a missing tile but silently accepts a
missing key by falling back to a default, so copy a neighbouring tile and edit
rather than writing from scratch.

Every value needs a `source`. The file's own convention, which is worth keeping:

- a real citation where one exists — `BKompV Anlage 2` for biotope values,
  `InVEST Urban Cooling` for shade, albedo and ETI, `TR-55 Table 2-2` for
  pervious curve numbers, `MiD 2017` for anything about travel;
- `"design: …"` when the value is a deliberate game choice;
- `"initial estimate"` in a `note` when it is an interpolation between tiles
  that are already calibrated.

**Do not dress up an estimate as a citation.** A reader who cannot tell the two
apart cannot improve either. If you look a number up, check it against a second
source and say which table it came from — `tiles.json` has entries naming the
exact row.

### Watch the scale of what you add

A derived figure can be physically right and still overwhelm the game.
`solar_field.co2PerHaYear` is −266 t/ha/yr, correctly derived from PV land use,
yield and the grid emission factor — and an order of magnitude beyond anything
else in the column, which makes solar the strongest climate lever there is. It
was kept at the derived value and the consequence documented, rather than
quietly scaled to be convenient. If your tile does that, say so in
`docs/model/tiles.md` rather than fixing it with a smaller number.

Compare your value against the column before you commit:

```bash
python3 -c "
import json; d=json.load(open('data/params/tiles.json'))
for k,v in d['tiles'].items(): print(f'{k:14s} {v[\"co2PerHaYear\"][\"value\"]:>8}')"
```

## 2. The enum

Add a value to `TileType` in the sim package. **Order is palette order**, so
put it beside the tiles it belongs with rather than at the end.

`TileType.terrain` is an alias for `meadow`, not a value of its own.

## 2b. The level legend

`levelMapLegend` in `packages/stadtbau_sim/lib/src/level.dart` maps one ASCII
character to each tile type, and it is what a level file is written in. A tile
with no character is a tile **no level can ever contain** — and nothing else
notices: the game runs, the palette offers the tile, the tests pass. The six
tiles added by T-502 sat like that until T-303 needed to write them out of
land-cover data. `level_test.dart` now asserts that the legend covers every
`TileType`, so this cannot happen again quietly.

Pick a character in the existing pattern: lower case is the softer member of a
pair (`w` water / `W` wetland, `h` low density / `H` high).

## 3. What the compiler will catch, and what it will not

The analyzer finds exhaustive `switch` statements over `TileType` — there are
two, in `game_controller.dart` (which overlay a placement previews) and
`map_view.dart` (how a tile is drawn). Fix those and it goes quiet.

**It will not find these:**

| Where | What happens | Why the analyzer misses it |
|---|---|---|
| `tile_style.dart` | **runtime crash** on first paint | `_styles[t]!` null-asserts a map |
| `app_en.arb`, `app_de.arb` | the tile shows the `other{}` fallback name | ICU `select` has no exhaustiveness |
| `model/water.dart` | a retention tile sheds water instead of holding it | `_isRetention` is a plain `==` chain |
| palette shortcuts | the tile has no digit key | only the first ten cards get one |

The digit limit is real and has no fix in the current design: keys 1–9 and 0
reach the first ten allowed tiles, and there are sixteen types. The palette
shows no badge above the tenth card, which is honest but means later tiles are
mouse- or Tab-only.

## 4. Drawing it

Add a case to the switch in `_drawTile`. Two rules:

- **Static detail goes on the still layer** (`still`), which is rasterised once
  behind a `RepaintBoundary` and costs nothing per frame. Put anything that
  moves on the moving layer (`moving`), which repaints every frame.
- **Respect `_lowDetail`**, which is set by the clean-visuals setting and by
  large maps zoomed out.

If the art should respond to the model, read the field — but **normalise
against the range the field actually occupies, not 0–1**. A healthy meadow
scores 0.42 for habitat quality, a decent block 0.65 for attractiveness, and a
busy map drags the air index from 100 only to about 95. Driving colour across
the full range of an absolute score paints a pristine map brown. Measure first — print the minimum, median and maximum of the field over a
representative map, and anchor your mapping on those rather than on 0 and 1.

## 5. Look at it

```bash
MAP_PNG=/tmp/tiles.png flutter test test/render_map_png.dart
```

That renders the painter to a PNG inside `flutter_test`, with no browser. Add
your tile to the scene in that file first. Text renders as boxes — the test
font is Ahem — and the tile art is the point.

## 6. Names, in both languages

`tileName` and `tileDescription` in both ARB files are ICU `select` blocks over
the tile id. Add your id **before** the `other{}` fallback so it stays last.
`tools/i18n_lint.dart` checks that both files have the same keys; it cannot
check that a `select` covers every id, so a missing case shows up as the
fallback string rather than as an error.

## 7. Model behaviour

A tile that is only land cover needs nothing further: sealing, biotope value,
emissions and curve number already act. A tile with a *purpose* needs a
mechanism, and the mechanism belongs in the model, not in a per-hectare figure.

`tram_stop` and `cycle_path` shipped with a placeholder negative
`co2PerHaYear` because the traffic they replace had nowhere to go; when the
commute model learned to shift mode share, both placeholders were removed,
because otherwise the same benefit is counted twice. If you find yourself
inventing a number to represent an effect, the effect probably belongs
somewhere else.

## 8. Before the pull request

```bash
dart run tools/gen_params.dart   # the generated mirror is committed
tools/check.sh
```

`gen_params.dart` rewrites `packages/stadtbau_sim/lib/src/generated/` from
`data/`. Commit the result; CI compares it.
