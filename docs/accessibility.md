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
| 1.1.1 Non-text content | labels exist; **no screen reader has run** | — |
| 1.4.10 Reflow | partly: the 200 % sweep covers a 420 px viewport | `text_scaling_test.dart` |

## What a test can and cannot settle

A widget test walks the widget tree, so it can answer structural questions
exactly: whether traversal closes, whether a control is reachable, whether a
node carries a label, whether a layout overflows. It cannot answer whether the
order *makes sense to a person*, whether a label *reads* well aloud, or whether
a colour pair is comfortable rather than merely above 4.5:1.

So the open item has never moved: **nobody has run this app under a real
screen reader.** The semantics tree is asserted, which is not the same thing.

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
tools/check.sh test-app          # all of the above
cd app && flutter test test/text_scaling_test.dart
```

Every one of these tests was verified by breaking the thing it guards and
watching it fail. A check nobody has seen fail is a check nobody knows works.

## References

- BITV 2.0 (Barrierefreie-Informationstechnik-Verordnung), Anlage 1
- EN 301 549 V3.2.1, clause 9 (Web) and clause 11 (Software)
- WCAG 2.1, W3C Recommendation
