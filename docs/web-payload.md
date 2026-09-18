# The web build: what a first load costs, and who serves it

Two tools, both dependency-light and both driving the real build:

```bash
tools/web_payload.py app/build/web      # what a browser downloads, gzipped
tools/check.sh origin                   # and who it downloads it from
```

`tools/web_payload.py` counts only the files a first load fetches, which is not
the size of the directory: Flutter writes every CanvasKit variant and a browser
reaches exactly one. `tools/web_origin_check.py` serves the build on
`127.0.0.1`, drives real Chrome through the app with **every other host
resolving to nothing**, and reports anything that tried to leave our origin. It
runs in CI after the web build.

## First load, measured 2026-09-18

| | gzipped |
|---|---|
| shell and fonts | 280 KB |
| program (dart2js) | 877 KB |
| engine, CanvasKit chromium | 2157 KB |
| **total, Chromium browsers** | **3314 KB** |
| total elsewhere (generic CanvasKit, 2857 KB) | 4014 KB |

The engine is two thirds of it and is Flutter's, not ours. Of what is ours, the
program is three quarters and the fonts the rest.

### Removed: 15 KB of citations nobody reads

`data/params/tiles.json` carries a `source` on every one of its 376 entries,
which is the point of the table. Nothing reads one at run time: `Param` parses
`source` and `note` into fields no widget touches, and the Quellen page is
generated from the JSON on disk at build time. The generated mirror the app
ships is therefore **values only** — 12 KB instead of 63 KB raw, 2.3 KB instead
of 17.4 KB gzipped.

The T-103 citation pass had grown that mirror by a third without anyone
noticing, because nothing in the build reports it. The invariant that every
parameter carries a source moved to a test that reads the JSON, which is where
the citations live.

It removed a second thing by accident, and that one matters more than the
bytes: `∝` and `→` appeared only inside parameter sources, so they are no
longer in the shipped program at all — two fewer of the fallback triggers
below.

## The app fetches fonts from Google, and its own copy says it does not

**Found 2026-09-18 by the new check.** `T-702` had the web build serving
everything from our own origin, verified by hand at the time. It does not any
more, and the cause is not a dependency. It is a character.

CanvasKit falls back to `fontFallbackBaseUrl` — `https://fonts.gstatic.com/s/`
by default — for any glyph the bundled fonts lack. Bundled Roboto (the Flutter
`material_fonts` artifact, 896 glyphs) lacks twelve characters the app's own
copy uses:

| Character | Where |
|---|---|
| `₂` | `CO₂` in `indicatorFormula`, `indicatorHint`, `tileDescription`, `tonsPerYear` — shown on the main screen every tick |
| `→` | `causalPath`, the causal view |
| 😊 🙁 🙂 😐 😄 😠 🤔 | `impactSimple*` and the indicator panel — **simple mode is built on these faces** |
| 🏅 👥 | earned medals, and the multiplayer player count |

So a run of the app asks Google for `notosans` and `notocoloremoji`. The
privacy text in the About screen says there are no network requests while you
play. There are two.

The check now tolerates `fonts.gstatic.com` as a **dated, named hole** in
`KNOWN_HOSTS` rather than failing CI on a known problem or, worse, not being
wired up at all. It guards against a *new* third party from today, and prints a
reminder to delete the entry when the fix lands.

### Fixing it is a choice, not a patch

Every route changes something owned by a person rather than by the code:

1. **Material icons for the emoji.** Flutter's icon font is already bundled and
   tree-shaken (Apache-2.0, on the allow-list), and it has exactly this set:
   `sentiment_very_satisfied` through `sentiment_very_dissatisfied`,
   `military_tech`, `group`. Costs no new bytes and no new licence, and removes
   nine of the twelve triggers. It is a visual design change to simple mode.
2. **`CO2` instead of `CO₂`, `->` instead of `→`.** Zero bytes, zero licences,
   removes the other three. It is a copy change, and `CO₂` is the correct
   typography in German environmental writing.
3. **Bundle a subset font for the three text glyphs.** About 2 KB. Noto Sans is
   OFL-1.1, which is **not on the PLAN §2 allow-list** and would have to be
   added; the emoji would still need a colour font, which is heavier.
4. **Host the fallback ourselves** by pointing `fontFallbackBaseUrl` at our own
   origin. Keeps every character, keeps every request on our origin, and costs
   megabytes of Noto.

1 and 2 together are the cheapest complete fix and add nothing to the payload.

## Also measured, not done: Roboto is three quarters bigger than it needs to be

The three bundled weights carry Greek, Cyrillic and Vietnamese. Subsetting them
to European Latin plus the punctuation and symbols the app uses takes them from
271 KB gzipped to 129 KB — **139 KB off every first load, 4 % of the total**.

It is held because it belongs with the decision above: both are "which glyphs
do we ship", and subsetting while the fallback question is open would trade a
measured saving for more of exactly the bug the check just found. `pyftsubset`
does the work; keeping `π` needs the Greek block, and the Apache-2.0 notice
would need a modification note, as the LBM-DE data already has.

## A trap worth writing down

Chrome was started with `--remote-debugging-port=<n>` and polled on
`127.0.0.1:<n>`. On a busy machine that port is sometimes taken, and Chrome
then **silently binds `[::1]` instead** and starts perfectly well — while the
poll times out against an address nothing is listening on, and the tool reports
"could not attach to Chrome". Pass `--remote-debugging-port=0` and read the
`DevTools listening on ws://…` line Chrome prints; that line is authoritative.
`tools/web_frame_bench.py` still has the older pattern.
