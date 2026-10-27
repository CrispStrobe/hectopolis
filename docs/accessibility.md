# Accessibility: what is tested, and what is only claimed

Hectopolis is a German-language teaching game, so the standards that matter are
**BITV 2.0** and **EN 301 549**, both of which point at **WCAG 2.1 level AA**.
This file records which of those criteria are checked by something that fails,
which are checked by a human looking, and which are neither.

That distinction is the point of the file. "Accessible" is easy to claim and
hard to keep: every one of the checks below was written after a change had
already broken something, or turned one up on first run.

| Criterion | How it is held | Where |
|---|---|---|
| 1.4.3 Contrast (text) | test, sweeps every gauge reading 0–100 | `app/test/contrast_test.dart` |
| 1.4.11 Non-text contrast | test, same sweep | `app/test/contrast_test.dart` |
| 1.4.4 Resize text (200 %) | test, 48 configurations | `app/test/text_scaling_test.dart` |
| 2.1.1 Keyboard | test + verified by hand in a browser | `app/test/keyboard_test.dart` |
| 2.1.2 No keyboard trap | test, traversal must close | `app/test/focus_order_test.dart` |
| 2.4.3 Focus order | test, every app-bar action reachable | `app/test/focus_order_test.dart` |
| 4.1.2 Name, role, value | test, asserts the semantics tree | `app/test/semantics_test.dart` |
| 2.3.3 Animation from interactions | code honours `disableAnimations` | `map_view.dart`, `game_screen.dart` |
| 1.1.1 Non-text content | test, read back over AT-SPI by a real client | `tools/a11y_probe.py` |
| 2.1.1 Keyboard, with a screen reader on the web | probe plays the web build by keyboard with semantics on | `tools/web_a11y_probe.py` |
| 1.3.1 Info and relationships (goal met / not met) | test, each goal row speaks its state | `app/test/semantics_test.dart` |
| 1.4.10 Reflow | partly: the 200 % sweep covers a 420 px viewport | `text_scaling_test.dart` |

## The AT-SPI probe

`tools/a11y_probe.py` is the only check here that leaves the process. It
stands up a private D-Bus session, an AT-SPI bus, Xvfb and the real Linux
build, then walks the tree over D-Bus the way a screen reader does, and fails
if the labels it is told to expect are not announced. CI runs it on every push.

It matters because every other test asserts Flutter's *own* semantics tree from
inside the app. That is worth doing and it is a different claim: it cannot tell
you whether any of it survives the journey out through GTK's ATK bridge onto
the accessibility bus, which is where an assistive technology actually reads.

What it currently reads, unprompted, on first launch:

```
application: 'com.crispstrobe.hectopolis'
  frame: 'Hectopolis'
    ...
      panel: 'Alert'
        panel: 'How Hectopolis works'
          panel: 'Step 1 of 3'
          panel: 'Place tiles'
          panel: 'Drag a tile from the palette onto the map, or select it ...'
        push button: 'Skip'
        push button: 'Next'
```

**Walk by index, not by `GetChildren`.** GTK's bridge answers
`org.a11y.atspi.Accessible.GetChildren` with an empty list while reporting a
correct `ChildCount`, so a client that trusts `GetChildren` sees a window with
nothing in it. That cost an afternoon and produced a confident wrong diagnosis
— "Flutter is not publishing semantics", followed by a code change to force
them — when the tree had been there the whole time and the probe was blind.
The code change was reverted; a stock build exposes everything above. Real
clients use `GetChildAtIndex`, and so does this one.

**The app follows the platform locale, and CI's is not yours.** The first CI
run of this probe failed while passing locally: this box starts the app in
English and GitHub's runner starts it in German, so the expected labels were
never going to match. Pinning a locale would need one generated on the machine
and would stop testing what a real user sees, so `--expect` takes `|`
alternatives instead and the check lists both languages.

Two environment notes for whoever runs it elsewhere: the AT-SPI bus puts its
socket under `$HOME` by default, and a home directory on a network filesystem
cannot host a unix socket (the bus dies with `Failed to bind socket ... Input/
output error`), so the probe points `XDG_CACHE_HOME` at local scratch; and
`at-spi2-core` is not on GitHub's Ubuntu image, so CI installs it.

**What it still does not settle.** It proves the labels reach the bus. It does
not prove they are *good* — that the reading order makes sense aloud, that a
gauge announces its value usefully, or that the map is navigable by someone who
cannot see it. And it is the Linux build; iOS VoiceOver and Android TalkBack
remain unexercised.

## The web screen-reader probe

`tools/web_a11y_probe.py` drives the web build the way a screen-reader user
would: it switches Flutter's web semantics on, opens a scenario, and plays it
with Tab, the arrow keys, a digit and Enter, reading what the browser's
accessibility tree and Flutter's `aria-live` hosts are handed. CI runs it after
the web build.

It exists because the web is different in a way no widget test sees. A screen
reader on the web follows the **browser's** focus, and the browser can only
focus semantics nodes flagged focusable. Until 2026-10-26 three things were
not:

- the palette cards and the gauges, because `excludeSemantics` — used to merge
  an icon, a name and a number into one sentence — also drops the focus flags
  of the `InkWell` inside (now `FocusableLabel`);
- the map, because its `Focus` sat above the labelled region, so the flags
  went to some ancestor;
- and the map's taps, left in the semantics tree, merged into the screen's node
  and turned it into one full-window button that also swallowed every loose
  text, so the first thing read was "Goals 96 months left Housing ≥ 70 0 …".

So with a screen reader running, Tab moved Flutter's focus through the cards
while the reader sat on the last control it could focus and said nothing, and
the map was never a stop at all: **the game could not be played**. Every
widget test passed, because Flutter's own focus moved fine, and the keyboard
check by hand passed, because it was done without a screen reader.

Two more web specifics the probe holds:

- The map is a live region, but the web engine announces a live region only
  when its *label* changes, and the cursor reading is its *value*. On the web
  the map therefore announces cursor moves itself (`SemanticsService`); the
  native platforms are left to the live region, so they do not hear it twice.
- Picking a tile with a digit changes a palette card's label, but focus is on
  the map, so no platform read it. That is announced on every platform.

**Known gap: dialogs are unnamed on the web.** The `alertdialog` element is the
dialog route's own node, and the web engine names it only if that node names
itself; `AlertDialog.semanticLabel` lands on a child, which Chrome ignores.
The title is still the first thing read inside the dialog. Fixing the name
needs an engine change, not an app one.

## What a test can and cannot settle

A widget test walks the widget tree, so it can answer structural questions
exactly: whether traversal closes, whether a control is reachable, whether a
node carries a label, whether a layout overflows. It cannot answer whether the
order *makes sense to a person*, whether a label *reads* well aloud, or whether
a colour pair is comfortable rather than merely above 4.5:1.

The open item has moved, but not all the way. An assistive-technology *client*
now reads the app in CI over AT-SPI, so the tree demonstrably reaches the bus,
and the web build is played by keyboard with semantics on, so it demonstrably
can be played. What the probes say aloud was also read through end to end and
fixed where it did not make sense (goal states, a doubled "Speed 3× 3×", an
unnamed choice of predictions). Nobody has yet sat with Orca, VoiceOver, NVDA
or TalkBack and tried to play, which is the judgement a machine cannot make.
`docs/accessibility-playtest.md` is the script for doing that (T-705).

## Three things worth remembering

**The worst point of a gauge scale is the middle, not an end.** A warm-to-cool
lerp passes through a desaturated tone whose luminance sits closest to the
track; in dark mode that midpoint measured 2.73:1 while both endpoints passed.
The contrast test therefore sweeps every reading rather than checking the ends,
and the colours are named constants the widget and the test share — a test that
re-typed the literal would keep passing after someone changed the widget.

**An overflow is a WCAG 1.4.4 failure that no other test sees.** Flutter
*reports* an overflow rather than throwing it, so every widget test in this
directory rendered the clipping screens and said nothing. A test has to install
its own `FlutterError.onError` to notice. When one finally did, it found the
compact palette strip clipping at **100 %** text, in shipped code, in both
languages.

**A stated height is a scaling bug waiting to happen.** A horizontal list
cannot take its height from its children, so it states one — and that literal
knows nothing about the system font size. Scaling the literal by the text
scaler is not a fix either: content does not grow linearly, because an icon
does not scale at all and a line box grows faster than its font size. Take the
height from the content and keep the old literal as a floor.

## Running the checks

```bash
tools/check.sh test-app          # every in-process test above
cd app && flutter test test/text_scaling_test.dart

# The web probe needs a web build and a Chrome:
cd app && flutter build web --release --no-web-resources-cdn && cd ..
tools/check.sh web-a11y

# The AT-SPI probe needs a Linux build and at-spi2-core, so it is opt-in
# locally and runs in CI on every push:
cd app && flutter build linux --debug && cd ..
tools/check.sh a11y
```

Every one of these tests was verified by breaking the thing it guards and
watching it fail. A check nobody has seen fail is a check nobody knows works.

## References

- BITV 2.0 (Barrierefreie-Informationstechnik-Verordnung), Anlage 1
- EN 301 549 V3.2.1, clause 9 (Web) and clause 11 (Software)
- WCAG 2.1, W3C Recommendation
