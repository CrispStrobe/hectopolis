#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Print what a browser actually downloads on a first load, gzipped.

    tools/web_payload.py app/build/web

Counts only the files a first load fetches, which is not the same as the size
of the directory: Flutter writes every CanvasKit variant and a symbol map for
each, and a given build can reach at most one variant. See the prune step in
.github/workflows/pages.yml.
"""
import gzip
import os
import sys

# One engine variant per row; a run fetches whichever its browser selects.
ENGINE_VARIANTS = [
    ("chromium", "canvaskit/chromium/canvaskit.js", "canvaskit/chromium/canvaskit.wasm"),
    ("generic", "canvaskit/canvaskit.js", "canvaskit/canvaskit.wasm"),
    ("skwasm", "canvaskit/skwasm.js", "canvaskit/skwasm.wasm"),
    ("skwasm_heavy", "canvaskit/skwasm_heavy.js", "canvaskit/skwasm_heavy.wasm"),
]
APP_FILES = [
    "index.html", "flutter_bootstrap.js", "manifest.json",
    "main.dart.js", "main.dart.wasm", "main.dart.mjs",
    "assets/FontManifest.json", "assets/AssetManifest.bin.json",
    "assets/fonts/MaterialIcons-Regular.otf",
    "assets/assets/fonts/Roboto-Regular.ttf",
    "assets/assets/fonts/Roboto-Medium.ttf",
    "assets/assets/fonts/Roboto-Bold.ttf",
]


def gz(path):
    try:
        with open(path, "rb") as handle:
            return len(gzip.compress(handle.read(), 9))
    except FileNotFoundError:
        return 0


def main(root):
    app = sum(gz(os.path.join(root, f)) for f in APP_FILES)
    print(f"  app and fonts            {app / 1024:8.0f} KB gz")
    for name, js, wasm in ENGINE_VARIANTS:
        engine = gz(os.path.join(root, js)) + gz(os.path.join(root, wasm))
        if engine == 0:
            continue
        print(f"  + engine {name:<14} {engine / 1024:8.0f} KB gz"
              f"   -> first load {(app + engine) / 1024:8.0f} KB gz")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "app/build/web")
