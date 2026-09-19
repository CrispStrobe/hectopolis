#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Check that a built web app fetches nothing from anyone but us (T-702).

    tools/web_origin_check.py --build app/build/web

Serves the build on 127.0.0.1, drives real Chrome through the screens that
render the app's own text, and fails if any request leaves our origin.

Why this exists as a tool rather than a one-off: T-702's guarantee was verified
by hand once, and the thing that breaks it is not a new dependency. It is a
character. CanvasKit falls back to `fontFallbackBaseUrl`
(https://fonts.gstatic.com/s/ by default) for any glyph the bundled fonts lack,
so one typographic flourish in a translation is enough to reopen a request to
Google from a screen nobody re-tested.

Chrome is started with `--host-resolver-rules="MAP * ~NOTFOUND, EXCLUDE
127.0.0.1"`, so a third-party fetch cannot quietly succeed on a machine with
working DNS: it fails, and the failure is what this reports. Every run writes a
screenshot, and a run only means something if that screenshot shows the app.

Needs Python's `websockets` package and a Chrome binary (--chrome, $CHROME, or
one of the usual locations).
"""
import argparse
import asyncio
import base64
import functools
import glob
import http.server
import json
import os
import shutil
import signal
import socketserver
import subprocess
import sys
import tempfile
import threading
import urllib.request

try:
    import websockets
except ImportError:
    sys.exit("pip install websockets")

CHROME_CANDIDATES = [
    "/usr/bin/chromium-browser", "/snap/bin/chromium",
    "/usr/bin/google-chrome", "/usr/bin/chromium", "/opt/google/chrome/chrome",
    *sorted(glob.glob(os.path.expanduser(
        "~/.cache/ms-playwright/chromium-*/chrome-linux64/chrome")), reverse=True),
]

# The layout this drives, shared with tools/web_frame_bench.py.
WINDOW = (1400, 900)
GRID_LEFT, GRID_TOP, CELL = 331, 65, 42.5
SANDBOX_ROW = (700, 152)

# Hosts this check tolerates, and why. An entry here is a known hole, dated, in
# the code rather than in someone's memory -- not a permanent exception.
#
# Empty since 2026-09-18: fonts.gstatic.com was here because CanvasKit fetched
# a fallback font for the twelve characters the bundled Roboto lacked -- the
# subscript in CO2, an arrow, and nine emoji. The emoji became Material icons,
# which were already bundled, and the two text glyphs became plain ASCII, so
# there is nothing left to tolerate.
KNOWN_HOSTS: set[str] = set()


def find_chrome(explicit):
    for c in filter(None, [explicit, os.environ.get("CHROME"), *CHROME_CANDIDATES]):
        if os.path.exists(c):
            return c
    sys.exit("no Chrome binary found; pass --chrome")


class Handler(http.server.SimpleHTTPRequestHandler):
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
        self.ws, self.n, self.events = ws, 0, []

    async def send(self, method, **params):
        self.n += 1
        await self.ws.send(json.dumps(
            {"id": self.n, "method": method, "params": params}))
        while True:
            msg = json.loads(await self.ws.recv())
            if msg.get("id") == self.n:
                if "error" in msg:
                    raise RuntimeError(f"{method}: {msg['error']}")
                return msg.get("result", {})
            if "method" in msg:
                self.events.append(msg)

    async def drain(self, seconds):
        """Collect events while nothing is being asked of the browser."""
        try:
            deadline = asyncio.get_event_loop().time() + seconds
            while True:
                left = deadline - asyncio.get_event_loop().time()
                if left <= 0:
                    return
                msg = json.loads(await asyncio.wait_for(self.ws.recv(), left))
                if "method" in msg:
                    self.events.append(msg)
        except asyncio.TimeoutError:
            return

    async def eval(self, expression, await_promise=False):
        r = await self.send("Runtime.evaluate", expression=expression,
                            returnByValue=True, awaitPromise=await_promise)
        return r.get("result", {}).get("value")

    async def click(self, x, y):
        for kind in ("mousePressed", "mouseReleased"):
            await self.send("Input.dispatchMouseEvent", type=kind, x=x, y=y,
                            button="left", clickCount=1)
            await self.drain(0.05)


async def run(chrome, url, shot):
    profile = tempfile.mkdtemp(prefix="origin-check-")
    # Keep Chrome's stderr: when it refuses to start, its own message is the
    # only thing that says why, and discarding it turns every failure into the
    # same unhelpful "could not attach".
    log = open(os.path.join(profile, "chrome.log"), "w+")
    proc = subprocess.Popen(
        [chrome, "--headless=new", "--no-sandbox", "--disable-dev-shm-usage",
         "--use-gl=swiftshader", "--enable-unsafe-swiftshader", "--hide-scrollbars",
         # A third-party fetch must fail rather than quietly succeed.
         '--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1',
         # Port 0: Chrome picks a free one and prints it. Naming a port and
         # polling 127.0.0.1 for it is what a busy machine breaks — if the
         # IPv4 port is taken Chrome silently binds [::1] instead, and the
         # poll then times out against a browser that started perfectly well.
         "--remote-debugging-port=0", f"--user-data-dir={profile}",
         f"--window-size={WINDOW[0]},{WINDOW[1]}", "about:blank"],
        stdout=subprocess.DEVNULL, stderr=log)
    try:
        # Chrome announces its endpoint on stderr; that line is authoritative.
        browser_ws = None
        for _ in range(300):
            log.flush()
            with open(log.name, encoding="utf-8", errors="replace") as f:
                for line in f:
                    if "DevTools listening on" in line:
                        browser_ws = line.split("DevTools listening on")[1].strip()
                        break
            if browser_ws:
                break
            await asyncio.sleep(0.2)
        ws_url = None
        if browser_ws:
            base = browser_ws.split("/devtools/")[0].replace("ws://", "http://")
            for _ in range(100):
                try:
                    tabs = json.load(urllib.request.urlopen(
                        f"{base}/json", timeout=2))
                    pages = [t for t in tabs if t["type"] == "page"]
                    if pages:
                        ws_url = pages[0]["webSocketDebuggerUrl"]
                        break
                except Exception:
                    pass
                await asyncio.sleep(0.2)
        if not ws_url:
            log.flush()
            log.seek(0)
            lines = [l for l in log.read().splitlines() if "dbus" not in l]
            tail = [l for l in lines if "ERROR:ui/gl" not in l
                    and "viz_main_impl" not in l
                    and "command_buffer_proxy" not in l][-10:]
            raise RuntimeError(
                "could not attach to Chrome\n  " + "\n  ".join(tail))

        async with websockets.connect(ws_url, max_size=None) as c_ws:
            c = CDP(c_ws)
            await c.send("Page.enable")
            await c.send("Runtime.enable")
            await c.send("Network.enable")
            await c.send("Page.addScriptToEvaluateOnNewDocument",
                         source="localStorage.setItem("
                                "'flutter.stadtbau.onboarding.v1','true');")
            await c.send("Page.navigate", url=url)
            for _ in range(150):
                if await c.eval(
                        "!!document.querySelector('flutter-view, flt-glass-pane')"):
                    break
                await c.drain(0.2)
            await c.drain(4)

            # Into the sandbox, where the indicator panel renders "t CO2/year"
            # and the tile palette renders every tile description.
            await c.click(*SANDBOX_ROW)
            await c.drain(4)
            # Build something, so impact feedback and the causal arrows render.
            for cx, cy in [(3, 3), (4, 3), (5, 3), (3, 4)]:
                await c.click(GRID_LEFT + CELL * (cx + 0.5),
                              GRID_TOP + CELL * (cy + 0.5))
                await c.drain(0.3)
            await c.drain(4)

            png = await c.send("Page.captureScreenshot")
            with open(shot, "wb") as f:
                f.write(base64.b64decode(png["data"]))
            return c.events
    finally:
        # A loaded machine can take longer than a polite SIGTERM allows, and a
        # teardown that raises would hide whatever went wrong above it.
        proc.send_signal(signal.SIGTERM)
        try:
            proc.wait(timeout=20)
        except subprocess.TimeoutExpired:
            proc.kill()
            try:
                proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                pass
        log.close()
        shutil.rmtree(profile, ignore_errors=True)


def main():
    p = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--build", default="app/build/web")
    p.add_argument("--port", type=int, default=8713)
    p.add_argument("--chrome")
    p.add_argument("--shot", default="/tmp/web-origin-check.png")
    args = p.parse_args()

    if not os.path.isfile(os.path.join(args.build, "index.html")):
        sys.exit(f"{args.build} has no index.html; run flutter build web first")
    chrome = find_chrome(args.chrome)
    httpd = serve(args.build, args.port)
    try:
        events = asyncio.run(run(
            chrome, f"http://127.0.0.1:{args.port}/", args.shot))
    finally:
        httpd.shutdown()

    ours, foreign, failed = set(), {}, []
    for e in events:
        method, params = e["method"], e.get("params", {})
        if method == "Network.requestWillBeSent":
            url = params["request"]["url"]
            if url.startswith(("data:", "blob:")):
                continue
            host = url.split("/")[2] if "//" in url else "?"
            if host.startswith("127.0.0.1"):
                ours.add(url)
            else:
                foreign.setdefault(host, set()).add(url)
        elif method == "Network.loadingFailed":
            failed.append(params.get("errorText", "?"))

    print(f"screenshot: {args.shot}")
    print(f"{len(ours)} request(s) served by us")
    known = {h: u for h, u in foreign.items() if h in KNOWN_HOSTS}
    new = {h: u for h, u in foreign.items() if h not in KNOWN_HOSTS}
    for host, urls in sorted(known.items()):
        print(f"  known hole: {host} ({len(urls)} request(s))")
        for url in sorted(urls)[:3]:
            print(f"    {url[:110]}")
    for host in sorted(KNOWN_HOSTS - set(foreign)):
        print(f"  {host} was not contacted — if that is the fix landing, "
              f"drop it from KNOWN_HOSTS")
    if not new:
        print("web origin check: ok, no new third party"
              f"{' (see the known hole above)' if known else ''}")
        return 0
    for host, urls in sorted(new.items()):
        print(f"  {host}")
        for url in sorted(urls)[:5]:
            print(f"    {url[:110]}")
    print(f"web origin check: {len(new)} unexpected third-party host(s)")
    return 1


if __name__ == "__main__":
    sys.exit(main())
