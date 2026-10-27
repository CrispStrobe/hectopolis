#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Play the web build by keyboard, the way a screen-reader user would (T-701).

    tools/web_a11y_probe.py --build app/build/web

Serves the build, turns on Flutter's web semantics (what a screen reader
does), opens a scenario, and plays it with Tab, the arrow keys, a digit and
Enter. It fails unless:

  * Tab reaches the map, and never sits on one element while Flutter moves
    its own focus somewhere the browser cannot follow;
  * an arrow key moves the cursor and the move is announced;
  * picking a tile with a digit is announced;
  * Enter places the tile, and the map says so;
  * every element the browser can focus has a name.

Why this exists next to tools/a11y_probe.py: that probe reads the Linux
build's tree over AT-SPI and proves the labels reach the bus. It cannot see
the web, where a screen reader follows the *browser's* focus, which lands
only on semantics nodes flagged focusable. Until 2026-10-26 the palette cards,
the gauges and the map were not, so with a screen reader running the game
could not be played at all, while every widget test passed: Flutter's own
focus moved fine.

Expected text is read from app/lib/l10n/app_en.arb, so a copy change does not
silently turn a check into one that can never fail. Chrome runs with
--use-mock-keychain (see open_page). Needs Python's `websockets` package and a
Chrome binary (--chrome, $CHROME, or one of the usual locations).
"""
import argparse
import asyncio
import base64
import json
import os
import re
import sys

from web_origin_check import find_chrome, open_page, serve

ARB = os.path.join(os.path.dirname(__file__), "..", "app", "lib", "l10n",
                   "app_en.arb")
LEVEL = "noise"

KEYS = {  # key, code, windowsVirtualKeyCode, text
    "Tab": ("Tab", "Tab", 9, ""),
    "ArrowRight": ("ArrowRight", "ArrowRight", 39, ""),
    "ArrowDown": ("ArrowDown", "ArrowDown", 40, ""),
    "Enter": ("Enter", "Enter", 13, "\r"),
    "1": ("1", "Digit1", 49, "1"),
}

# Records every text Flutter writes to its aria-live hosts, which is what a
# screen reader is handed to say.
WATCH_ANNOUNCEMENTS = """
window.__announced = [];
for (const host of document.querySelectorAll('[aria-live]')) {
  new MutationObserver(() => {
    const t = host.textContent.trim();
    if (t) window.__announced.push(t);
  }).observe(host, {childList: true, subtree: true, characterData: true});
}
"""


def strings():
    arb = json.load(open(ARB, encoding="utf-8"))
    title = re.search(LEVEL + r"\{([^}]*)\}", arb["levelTitle"]).group(1)
    selected = re.escape(arb["a11yTileSelected"]).replace(
        re.escape("{name}"), ".+")
    return {
        "level": title,
        "skip": arb["onboardingSkip"],
        "hint": arb["keyboardHint"],
        "no_cursor": arb["a11yMapNoCursor"],
        "selected": re.compile("^" + selected + "$"),
    }


async def press(c, name):
    key, code, vk, text = KEYS[name]
    down = dict(type="keyDown", key=key, code=code,
                windowsVirtualKeyCode=vk, nativeVirtualKeyCode=vk)
    if text:
        down["text"] = text
    await c.send("Input.dispatchKeyEvent", **down)
    await c.send("Input.dispatchKeyEvent", type="keyUp", key=key, code=code,
                 windowsVirtualKeyCode=vk, nativeVirtualKeyCode=vk)
    await c.drain(0.15)


async def click_text(c, text, shot):
    """Clicks the centre of the semantics node whose text starts with text,
    waiting up to ten seconds for it to appear."""
    for _ in range(50):
        rect = await c.eval(f"""(() => {{
          const want = {json.dumps(text)};
          const e = [...document.querySelectorAll('flt-semantics')].find(x =>
            (x.getAttribute('aria-label') || x.textContent || '').trim()
              .startsWith(want));
          if (!e) return null;
          const r = e.getBoundingClientRect();
          return r.width > 0 ? [r.x + r.width / 2, r.y + r.height / 2] : null;
        }})()""")
        if rect is not None:
            await c.click(*rect)
            return
        await c.drain(0.2)
    png = await c.send("Page.captureScreenshot")
    with open(shot, "wb") as f:
        f.write(base64.b64decode(png["data"]))
    raise RuntimeError(f"nothing on screen reads {text!r}; see {shot}")


def map_js(hint):
    return f"""(() => {{
      const m = [...document.querySelectorAll('flt-semantics')].find(x =>
        x.getAttribute('aria-description') === {json.dumps(hint)});
      if (!m) return null;
      return {{text: (m.textContent || '').replace(/\\s+/g, ' ').trim(),
               focused: document.activeElement === m}};
    }})()"""


FOCUS_JS = """(() => {
  const a = document.activeElement;
  return a.tagName.toLowerCase() === 'flt-semantics' ? a.id : a.tagName;
})()"""


async def unnamed_focusables(c):
    tree = await c.send("Accessibility.getFullAXTree")
    out = []
    for n in tree["nodes"]:
        if n.get("ignored"):
            continue
        role = n.get("role", {}).get("value", "")
        props = {p["name"]: p.get("value", {}).get("value")
                 for p in n.get("properties", [])}
        if not props.get("focusable") or role in ("RootWebArea", "generic"):
            continue
        if not (n.get("name", {}).get("value") or "").strip():
            out.append(role)
    return out


async def run(chrome, url, shot, s):
    failures, notes = [], []

    def check(ok, what):
        (notes if ok else failures).append(("ok   " if ok else "FAIL ") + what)

    async with open_page(chrome, ["--lang=en-US"]) as c:
        await c.send("Page.enable")
        await c.send("Runtime.enable")
        await c.send("Accessibility.enable")
        await c.send("Page.addScriptToEvaluateOnNewDocument",
                     source="localStorage.setItem("
                            "'flutter.stadtbau.onboarding.v1','true');")
        await c.send("Page.navigate", url=url)
        for _ in range(150):
            if await c.eval("!!document.querySelector('flt-semantics-placeholder')"):
                break
            await c.drain(0.2)
        await c.drain(3)
        # What a screen reader's first touch does: switch semantics on.
        await c.eval("document.querySelector('flt-semantics-placeholder').click()")
        await c.drain(1.5)

        await click_text(c, s["level"], shot)
        await c.drain(2.5)
        await click_text(c, s["skip"], shot)
        await c.drain(1.5)
        await c.eval(WATCH_ANNOUNCEMENTS)

        # Tab to the map. A Tab that leaves the browser's focus where it was
        # means Flutter moved focus to a node the browser cannot focus, and a
        # screen reader announced nothing.
        reached, stuck, last = None, [], await c.eval(FOCUS_JS)
        for i in range(90):
            await press(c, "Tab")
            now = await c.eval(FOCUS_JS)
            if now == last and now.startswith("flt-semantic"):
                stuck.append(now)
            last = now
            m = await c.eval(map_js(s["hint"]))
            if m and m["focused"]:
                reached = i + 1
                break
        check(reached is not None,
              f"Tab reaches the map ({reached} presses)" if reached
              else "Tab never reached the map in 90 presses")
        check(not stuck, "every Tab moved the browser's focus" if not stuck
              else f"Tab left focus on the same element {len(stuck)} times: "
                   f"{sorted(set(stuck))}")

        before = (await c.eval(map_js(s["hint"])) or {}).get("text", "")
        await c.eval("window.__announced = []")
        await press(c, "ArrowRight")
        await c.drain(0.6)
        after = (await c.eval(map_js(s["hint"])) or {}).get("text", "")
        said = await c.eval("window.__announced")
        check(s["no_cursor"] not in after and after != before,
              f"an arrow key moves the cursor: {after!r}")
        check(any(a and a in after for a in said),
              f"the move is announced: {said!r}")

        await c.eval("window.__announced = []")
        await press(c, "1")
        await c.drain(0.6)
        said = await c.eval("window.__announced")
        check(any(s["selected"].match(a) for a in said),
              f"picking a tile by digit is announced: {said!r}")

        before = after
        await press(c, "Enter")
        await c.drain(0.8)
        after = (await c.eval(map_js(s["hint"])) or {}).get("text", "")
        check(after != before, f"Enter places the tile: {after!r}")

        unnamed = await unnamed_focusables(c)
        check(not unnamed, "every focusable element has a name" if not unnamed
              else f"{len(unnamed)} focusable element(s) without a name: "
                   f"{unnamed}")

        png = await c.send("Page.captureScreenshot")
        with open(shot, "wb") as f:
            f.write(base64.b64decode(png["data"]))
    return notes, failures


def main():
    p = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--build", default="app/build/web")
    p.add_argument("--port", type=int, default=8714)
    p.add_argument("--chrome")
    p.add_argument("--shot", default="/tmp/web-a11y-probe.png")
    args = p.parse_args()

    if not os.path.isfile(os.path.join(args.build, "index.html")):
        sys.exit(f"{args.build} has no index.html; run flutter build web first")
    chrome = find_chrome(args.chrome)
    httpd = serve(args.build, args.port)
    try:
        notes, failures = asyncio.run(run(
            chrome, f"http://127.0.0.1:{args.port}/", args.shot, strings()))
    finally:
        httpd.shutdown()

    print(f"screenshot: {args.shot}")
    for line in notes + failures:
        print(line)
    if failures:
        sys.exit(f"web a11y probe: {len(failures)} check(s) failed")
    print("web a11y probe: ok")


if __name__ == "__main__":
    main()
