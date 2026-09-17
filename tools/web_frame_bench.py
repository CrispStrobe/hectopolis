#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Measure map animation frame times of a built web app in real Chrome (T-202).

Serves a `flutter build web` output, drives Chrome over the DevTools protocol
into the sandbox level, fills part of the map so the painter has real work, and
reports the frame times of the ambient animation.

    tools/web_frame_bench.py --build app/build/web --runs 3

Needs Python's `websockets` package and a Chrome binary (--chrome, $CHROME, or
one of the usual locations, including a Playwright cache).

The numbers are only comparable between runs on the same machine: Chrome falls
back to software rasterisation in headless mode, so absolute frame times say
nothing about a real device. Use it to compare two builds, not to certify a
frame rate. Every run writes a screenshot; a run is only meaningful if that
screenshot shows the populated map, since the app is driven by clicking at
fixed coordinates in a 1200x800 window.
"""
import argparse, asyncio, base64, functools, glob, http.server, json, os
import shutil, signal, socketserver, statistics, subprocess, sys, tempfile
import threading, urllib.request

try:
    import websockets
except ImportError:
    sys.exit("needs the websockets package: pip install websockets")

CHROME_CANDIDATES = [
    "/usr/bin/google-chrome", "/usr/bin/chromium", "/opt/google/chrome/chrome",
    *sorted(glob.glob(os.path.expanduser(
        "~/.cache/ms-playwright/chromium-*/chrome-linux64/chrome")), reverse=True),
]


def find_chrome(explicit):
    for c in filter(None, [explicit, os.environ.get("CHROME"), *CHROME_CANDIDATES]):
        if os.path.exists(c):
            return c
    sys.exit("no Chrome binary found; pass --chrome")


class Handler(http.server.SimpleHTTPRequestHandler):
    """Flutter needs the wasm and mjs types; Python's table lacks them."""
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map,
                      ".wasm": "application/wasm", ".mjs": "text/javascript",
                      ".js": "text/javascript", ".json": "application/json",
                      ".otf": "font/otf", ".ttf": "font/ttf"}

    def log_message(self, *a):
        pass


def serve(directory, port):
    socketserver.TCPServer.allow_reuse_address = True
    httpd = socketserver.TCPServer(
        ("127.0.0.1", port), functools.partial(Handler, directory=directory))
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    return httpd


class CDP:
    def __init__(self, ws):
        self.ws, self.n = ws, 0

    async def send(self, method, **params):
        self.n += 1
        await self.ws.send(json.dumps({"id": self.n, "method": method, "params": params}))
        while True:
            msg = json.loads(await self.ws.recv())
            if msg.get("id") == self.n:
                if "error" in msg:
                    raise RuntimeError(f"{method}: {msg['error']}")
                return msg.get("result", {})

    async def eval(self, expression, await_promise=False):
        r = await self.send("Runtime.evaluate", expression=expression,
                            returnByValue=True, awaitPromise=await_promise)
        return r.get("result", {}).get("value")

    async def click(self, x, y):
        for kind in ("mousePressed", "mouseReleased"):
            await self.send("Input.dispatchMouseEvent", type=kind, x=x, y=y,
                            button="left", clickCount=1)
            await asyncio.sleep(0.05)


# Geometry of the 1400x900 layout this drives. The width matters: below 1280
# the app bar collapses its speed buttons into the overflow menu, so --play
# would click a zoom icon and measure a paused game. The palette is a
# fixed-width column, so its rows are the same at any width; the grid and the
# app bar are not.
WINDOW = (1400, 900)
GRID_LEFT, GRID_TOP, CELL = 331, 65, 42.5
SANDBOX_ROW = (700, 152)
SPEED_10X = (939, 27)
PLAN = [((129, 283), [(x, y) for x in range(2, 14) for y in (2, 3)]),
        ((129, 531), [(x, y) for x in range(2, 14) for y in (6, 7, 8)]),
        ((129, 593), [(x, y) for x in range(2, 14) for y in (10, 11)])]


async def measure(chrome, url, port, seconds, shot, play=False):
    profile = tempfile.mkdtemp(prefix="frame-bench-")
    proc = subprocess.Popen(
        [chrome, "--headless=new", "--no-sandbox", "--disable-dev-shm-usage",
         "--use-gl=swiftshader", "--enable-unsafe-swiftshader", "--hide-scrollbars",
         f"--remote-debugging-port={port}", f"--user-data-dir={profile}",
         f"--window-size={WINDOW[0]},{WINDOW[1]}", "about:blank"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        ws_url = None
        for _ in range(100):
            try:
                tabs = json.load(urllib.request.urlopen(f"http://127.0.0.1:{port}/json"))
                pages = [t for t in tabs if t["type"] == "page"]
                if pages:
                    ws_url = pages[0]["webSocketDebuggerUrl"]
                    break
            except Exception:
                pass
            await asyncio.sleep(0.2)
        if not ws_url:
            raise RuntimeError("could not attach to Chrome")

        async with websockets.connect(ws_url, max_size=None) as ws:
            c = CDP(ws)
            await c.send("Page.enable")
            await c.send("Runtime.enable")
            await c.send("Page.addScriptToEvaluateOnNewDocument",
                         source="localStorage.setItem('flutter.stadtbau.onboarding.v1','true');")
            await c.send("Page.navigate", url=url)
            for _ in range(150):
                if await c.eval("!!document.querySelector('flutter-view, flt-glass-pane')"):
                    break
                await asyncio.sleep(0.2)
            await asyncio.sleep(3)
            await c.click(*SANDBOX_ROW)
            await asyncio.sleep(4)
            for palette, cells in PLAN:
                await c.click(*palette)
                await asyncio.sleep(0.4)
                for cx, cy in cells:
                    await c.click(GRID_LEFT + CELL * (cx + 0.5), GRID_TOP + CELL * (cy + 0.5))
            if play:
                # 10x speed: a tick, and so a still-layer repaint, every 100 ms.
                await c.click(*SPEED_10X)
                await asyncio.sleep(2)
            await asyncio.sleep(3)
            png = await c.send("Page.captureScreenshot")
            with open(shot, "wb") as f:
                f.write(base64.b64decode(png["data"]))
            return await c.eval(f"""
              new Promise(resolve => {{
                const times = []; let last = performance.now();
                const stop = last + {int(seconds * 1000)};
                function tick(now) {{
                  times.push(now - last); last = now;
                  if (now < stop) requestAnimationFrame(tick); else resolve(times);
                }}
                requestAnimationFrame(tick);
              }})""", await_promise=True)
    finally:
        proc.send_signal(signal.SIGTERM)
        proc.wait(timeout=10)
        shutil.rmtree(profile, ignore_errors=True)


async def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--build", required=True, help="a flutter build web output directory")
    p.add_argument("--chrome")
    p.add_argument("--runs", type=int, default=3)
    p.add_argument("--seconds", type=float, default=12)
    p.add_argument("--port", type=int, default=8899)
    p.add_argument("--shots", default=tempfile.gettempdir())
    p.add_argument("--play", action="store_true",
                   help="run the game clock at 10x while measuring, so the still "
                        "layer repaints every tick instead of never")
    args = p.parse_args()

    chrome = find_chrome(args.chrome)
    httpd = serve(os.path.abspath(args.build), args.port)
    medians = []
    try:
        for run in range(1, args.runs + 1):
            shot = os.path.join(args.shots, f"frame-bench-{run}.png")
            frames = await measure(chrome, f"http://127.0.0.1:{args.port}/",
                                   args.port + 1000, args.seconds, shot,
                                   play=args.play)
            if not frames or len(frames) < 10:
                print(f"  run {run}: only {len(frames or [])} frames; check {shot}")
                continue
            ordered = sorted(frames[1:])  # the first interval includes start-up
            n = len(ordered)
            medians.append(ordered[n // 2])
            print(f"  run {run}: {n:4d} frames  median {ordered[n // 2]:6.1f} ms  "
                  f"p95 {ordered[int(n * 0.95)]:6.1f} ms  "
                  f"{1000 / (sum(ordered) / n):5.1f} fps avg   {shot}")
    finally:
        httpd.shutdown()
    if medians:
        print(f"  mean of medians: {statistics.mean(medians):.1f} ms over {len(medians)} runs")


if __name__ == "__main__":
    asyncio.run(main())
