#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Subset the bundled Roboto weights to the characters this app can render.

    tools/subset_fonts.py                 # regenerate app/assets/fonts/
    tools/subset_fonts.py --check         # fail if the committed files differ

The full Roboto that ships with Flutter carries Greek, Cyrillic and Vietnamese.
Hectopolis is German and English, and a first load pays for all of it: the three
weights are 271 KB gzipped whole and 143 KB subset -- 125 KB saved, about 4 %
of the entire first load, and more than the app's own data.

**Subsetting is only safe because of tools/web_origin_check.py.** A glyph the
bundled fonts lack is not a missing character on screen; CanvasKit fetches a
fallback font for it from Google, which is the request T-702 promises does not
happen. So this script refuses to write a subset that drops a character the
app's own strings use, and the origin check verifies the result in a browser.

The kept ranges are deliberately wider than the app's current strings: European
Latin, so a future translation or a player's name in Polish or Turkish works
without anyone having to remember this file.

Source: the Flutter SDK's material_fonts artifact (Apache-2.0). Modification
notice, as Apache-2.0 section 4(b) requires, is in
app/assets/licenses/Roboto-Apache-2.0.txt.

Needs fontTools (`pip install fonttools`).
"""
import argparse
import hashlib
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile

WEIGHTS = ["Regular", "Medium", "Bold"]
OUT_DIR = pathlib.Path("app/assets/fonts")

# Basic Latin, Latin-1, Latin Extended-A and -B, spacing modifiers, combining
# diacritics, General Punctuation, Currency, Letterlike, Number Forms, Arrows,
# Mathematical Operators, Box Drawing and Geometric Shapes -- plus U+03C0
# alone, for the pi in an air-model formula.
#
# The whole Greek block would cost 23 KB gzipped across the three weights for
# that one letter, which is more than the Latin Extended blocks that make a
# future Polish or Turkish translation work. Ranges are worth what they cover.
UNICODES = (
    "U+0000-00FF,U+0100-017F,U+0180-024F,U+02B0-02FF,U+0300-036F,U+03C0,"
    "U+2000-206F,U+20A0-20BF,U+2100-214F,U+2150-218F,"
    "U+2190-21FF,U+2200-22FF,U+25A0-25FF,U+2713-2714"
)


def app_characters():
    """Every character the app's own strings and data can put on screen."""
    chars = set()

    def add(value):
        if isinstance(value, str):
            chars.update(value)

    def walk(node):
        if isinstance(node, dict):
            for key, value in node.items():
                add(key)
                walk(value)
        elif isinstance(node, list):
            for value in node:
                walk(value)
        else:
            add(node)

    for path in ["app/lib/l10n/app_en.arb", "app/lib/l10n/app_de.arb"]:
        for key, value in json.load(open(path, encoding="utf-8")).items():
            if not key.startswith("@"):
                add(value)
    for path in pathlib.Path("data").rglob("*.json"):
        walk(json.loads(path.read_text(encoding="utf-8")))
    for path in pathlib.Path("app/lib").rglob("*.dart"):
        if "l10n/generated" in str(path):
            continue
        text = path.read_text(encoding="utf-8")
        for match in re.finditer(r"'([^'\\\n]*)'|\"([^\"\\\n]*)\"", text):
            add(match.group(1) or match.group(2) or "")
    return {c for c in chars if not c.isspace()}


def subset(source, target):
    subprocess.run(
        [sys.executable, "-m", "fontTools.subset", str(source),
         f"--unicodes={UNICODES}", "--layout-features=*",
         f"--output-file={target}"],
        check=True, stdout=subprocess.DEVNULL)


def main():
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument(
        "--sdk-fonts",
        default=os.path.join(
            os.environ.get("FLUTTER_ROOT", "/mnt/volume1/toolchain/flutter"),
            "bin/cache/artifacts/material_fonts"),
        help="where the full Roboto weights come from")
    parser.add_argument("--check", action="store_true",
                        help="verify the committed subsets, write nothing")
    args = parser.parse_args()

    try:
        from fontTools.ttLib import TTFont
    except ImportError:
        sys.exit("pip install fonttools")

    needed = app_characters()
    failures = 0
    with tempfile.TemporaryDirectory() as tmp:
        for weight in WEIGHTS:
            source = pathlib.Path(args.sdk_fonts) / f"Roboto-{weight}.ttf"
            if not source.exists():
                sys.exit(f"{source} not found; pass --sdk-fonts")
            built = pathlib.Path(tmp) / f"Roboto-{weight}.ttf"
            subset(source, built)

            # A dropped character is a request to Google, not a blank space.
            covered = set(TTFont(built).getBestCmap())
            full = set(TTFont(source).getBestCmap())
            lost = sorted(c for c in needed
                          if ord(c) not in covered and ord(c) in full)
            if lost:
                sys.exit(f"Roboto-{weight}: subsetting would drop "
                         f"{''.join(lost)!r}, which the app uses. Widen "
                         f"UNICODES in {__file__}.")

            target = OUT_DIR / f"Roboto-{weight}.ttf"
            new = built.read_bytes()
            if args.check:
                old = target.read_bytes() if target.exists() else b""
                same = hashlib.sha256(old).digest() == hashlib.sha256(new).digest()
                print(f"  Roboto-{weight}: "
                      f"{'up to date' if same else 'DIFFERS from the subset'}")
                failures += 0 if same else 1
            else:
                before = target.stat().st_size if target.exists() else 0
                target.write_bytes(new)
                print(f"  Roboto-{weight}: {before} -> {len(new)} bytes")

    if args.check and failures:
        print(f"subset_fonts: {failures} font(s) out of date; "
              f"run tools/subset_fonts.py")
        return 1
    print("subset_fonts: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
