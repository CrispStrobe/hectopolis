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
SHELL_FILES = [
    "index.html", "flutter_bootstrap.js", "manifest.json",
    "assets/FontManifest.json", "assets/AssetManifest.bin.json",
    "assets/fonts/MaterialIcons-Regular.otf",
    "assets/assets/fonts/Roboto-Regular.ttf",
    "assets/assets/fonts/Roboto-Medium.ttf",
    "assets/assets/fonts/Roboto-Bold.ttf",
]

# A --wasm build ships BOTH entry points and each browser fetches exactly one:
# WasmGC browsers take main.dart.wasm, the rest fall back to main.dart.js.
# Summing them overstates the payload by a whole compiled program -- it put the
# wasm build at 2084 KB when no browser ever downloads more than about 1190.
ENTRY_POINTS = [
    ("dart2wasm", ["main.dart.wasm", "main.dart.mjs"]),
    ("dart2js", ["main.dart.js"]),
]


def gz(path):
    try:
        with open(path, "rb") as handle:
            return len(gzip.compress(handle.read(), 9))
    except FileNotFoundError:
        return 0


def main(root):
    shell = sum(gz(os.path.join(root, f)) for f in SHELL_FILES)
    print(f"  shell and fonts          {shell / 1024:8.0f} KB gz")
    entries = []
    for name, files in ENTRY_POINTS:
        size = sum(gz(os.path.join(root, f)) for f in files)
        if size:
            entries.append((name, size))
            print(f"  program via {name:<11} {size / 1024:8.0f} KB gz")
    engines = []
    for name, js, wasm in ENGINE_VARIANTS:
        engine = gz(os.path.join(root, js)) + gz(os.path.join(root, wasm))
        if engine:
            engines.append((name, engine))
            print(f"  engine {name:<16} {engine / 1024:8.0f} KB gz")
    print("  first load = shell + one program + one engine:")
    for entry_name, entry in entries:
        for engine_name, engine in engines:
            total = shell + entry + engine
            print(f"    {entry_name:<9} + {engine_name:<22}"
                  f" {total / 1024:8.0f} KB gz")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "app/build/web")
