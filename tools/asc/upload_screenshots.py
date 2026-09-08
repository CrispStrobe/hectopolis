# SPDX-License-Identifier: AGPL-3.0-or-later
#!/usr/bin/env python3
"""Upload store screenshots to App Store Connect.

Input is whatever `.github/workflows/screenshots.yml` produced: a tree of
`<device>/<locale>_<nn>_<name>.png`, as downloaded from the `screenshots-ios`
artifact. The device directory decides the size class, the file name decides
the store language and the order:

    iPhone_17_Pro_Max/en_02_map.png -> APP_IPHONE_67,          en-US, #2
    iPad_Pro_13-inch_M5/de_05_...   -> APP_IPAD_PRO_3GEN_129,  de-DE, #5

Screenshots hang off a *version localization*, so the full path to a set is
app -> editable appStoreVersion (platform IOS or MAC_OS) -> appStoreVersionLocalization
(one per store language) -> appScreenshotSet (one per display type), and each
image is a three-call dance: reserve, PUT the bytes to Apple's presigned URL,
commit with an MD5. See docs/release/screenshots.md §5.

    python3 tools/asc/upload_screenshots.py --dry-run app/screenshots
    python3 tools/asc/upload_screenshots.py --replace screenshots-ios

Credentials come from the environment, exactly as `client.py` reads them:
ASC_API_KEY_P8_BASE64, ASC_KEY_ID, ASC_ISSUER_ID. The app is `--app-id` or
ASC_APP_ID. Nothing here is ever submitted for review.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import client  # noqa: E402  (sibling module, path fixed up above)

ROOT = pathlib.Path(__file__).resolve().parents[2]
PUBSPEC = ROOT / "app" / "pubspec.yaml"

PLATFORM = "IOS"

# The states in which a version's metadata can still be edited. Anything else
# (PROCESSING_FOR_APP_STORE, READY_FOR_SALE, …) is read-only, so a new version
# has to be created instead.
EDITABLE_STATES = [
    "PREPARE_FOR_SUBMISSION",
    "DEVELOPER_REJECTED",
    "REJECTED",
    "METADATA_REJECTED",
    "WAITING_FOR_REVIEW",
    "READY_FOR_REVIEW",
]

# Apple's enum names still carry the old marketing sizes: APP_IPHONE_67 is the
# 6.9" iPhone bucket (1320x2868) and APP_IPAD_PRO_3GEN_129 the 13" iPad Pro
# (2064x2752). That is expected, not a mismatch — see docs/release/screenshots.md §4.
DISPLAY_TYPES: list[tuple[str, str]] = [
    (r"iphone", "APP_IPHONE_67"),
    (r"ipad", "APP_IPAD_PRO_3GEN_129"),
    (r"macos", "APP_DESKTOP"),
]

LOCALES: dict[str, str] = {"en": "en-US", "de": "de-DE"}

# Apple accepts at most ten screenshots per set.
MAX_PER_SET = 10


# --------------------------------------------------------------------------
# Planning — pure, offline, and therefore the part that can be tested here.
# --------------------------------------------------------------------------


class Shot:
    """One PNG, with everything the API needs derived from its path."""

    def __init__(self, path: pathlib.Path, locale: str, display_type: str, order: int):
        self.path = path
        self.locale = locale
        self.display_type = display_type
        self.order = order

    @property
    def name(self) -> str:
        return self.path.name

    @property
    def size(self) -> int:
        return self.path.stat().st_size

    def checksum(self) -> str:
        return hashlib.md5(self.path.read_bytes()).hexdigest()  # noqa: S324 (Apple asks for MD5)

    def __repr__(self) -> str:  # pragma: no cover - debugging aid
        return f"Shot({self.path}, {self.locale}, {self.display_type}, {self.order})"


def display_type_for(device_dir: str) -> str | None:
    """`iPhone_17_Pro_Max` -> APP_IPHONE_67. Unknown families are skipped."""
    lowered = device_dir.lower()
    for pattern, display_type in DISPLAY_TYPES:
        if re.search(pattern, lowered):
            return display_type
    return None


def locale_for(file_name: str) -> str | None:
    """`en_02_map.png` -> `en-US`."""
    prefix = file_name.split("_", 1)[0]
    return LOCALES.get(prefix.lower())


def order_for(file_name: str) -> int:
    """The `02` in `en_02_map.png`; files without one sort last, by name."""
    match = re.match(r"^[A-Za-z]+_(\d+)", file_name)
    return int(match.group(1)) if match else 10_000


def collect(roots: list[pathlib.Path], warn=print) -> dict[tuple[str, str], list[Shot]]:
    """Every usable PNG under `roots`, grouped by (locale, displayType).

    The artifact may be unpacked with or without its `screenshots-ios/` wrapper
    directory, so the tree is walked recursively and the PNG's *parent*
    directory is taken as the device name.
    """
    groups: dict[tuple[str, str], list[Shot]] = {}
    for root in roots:
        if not root.exists():
            warn(f"warning: {root} does not exist")
            continue
        for path in sorted(root.rglob("*.png")):
            display_type = display_type_for(path.parent.name)
            if display_type is None:
                warn(f"skipping {path}: {path.parent.name} is not a supported Apple device family")
                continue
            locale = locale_for(path.name)
            if locale is None:
                warn(f"skipping {path}: file name does not start with a known locale prefix")
                continue
            groups.setdefault((locale, display_type), []).append(
                Shot(path, locale, display_type, order_for(path.name))
            )
    for shots in groups.values():
        shots.sort(key=lambda s: (s.order, s.name))
    return dict(sorted(groups.items()))


def version_string(pubspec: pathlib.Path = PUBSPEC) -> str:
    """`version: 0.1.0+1` -> `0.1.0`. The build number is not part of it."""
    for line in pubspec.read_text().splitlines():
        match = re.match(r"^version:\s*([0-9]+(?:\.[0-9]+)*)", line)
        if match:
            return match.group(1)
    raise SystemExit(f"no `version:` line in {pubspec}")


# --------------------------------------------------------------------------
# App Store Connect
# --------------------------------------------------------------------------


def _query(path: str, **params: str) -> str:
    """`filter[platform]` has to be percent-encoded; urlencode does that."""
    return f"{path}?{urllib.parse.urlencode(params)}"


def _errors(doc: dict) -> str:
    return "; ".join(
        f"{e.get('code', '')}: {e.get('detail', '')}" for e in doc.get("errors", [])
    ) or json.dumps(doc)[:400]


def editable_version(app_id: str) -> dict | None:
    """The version whose metadata can still be edited, if there is one."""
    path = _query(
        f"/v1/apps/{app_id}/appStoreVersions",
        **{
            "filter[platform]": PLATFORM,
            "filter[appStoreState]": ",".join(EDITABLE_STATES),
            "limit": "200",
        },
    )
    for version in client.paged(path):
        # The filter is server-side, but re-check: a stale filter enum would
        # otherwise let a read-only version through and every PATCH would 409.
        if version["attributes"].get("appStoreState") in EDITABLE_STATES:
            return version
    return None


def create_version(app_id: str, version: str) -> dict:
    """A fresh PREPARE_FOR_SUBMISSION version for `version`."""
    body = {
        "data": {
            "type": "appStoreVersions",
            "attributes": {"platform": PLATFORM, "versionString": version},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
        }
    }
    status, doc = client.call("POST", "/v1/appStoreVersions", body)
    if status in (200, 201):
        return doc["data"]
    if status == 409:
        # Either the version string is taken or an editable version appeared
        # between the GET and the POST. Both are answered by re-reading.
        found = editable_version(app_id)
        if found:
            print(f"  (409 on create: {_errors(doc)}) — reusing {found['id']}")
            return found
    raise SystemExit(f"POST /v1/appStoreVersions -> HTTP {status}: {_errors(doc)}")


def localization(version_id: str, locale: str, create: bool = True) -> dict | None:
    """The `appStoreVersionLocalization` for `locale`, created if missing.

    `create=False` (a dry run) looks it up and returns None instead — a dry run
    that quietly created half the resources would not be one.
    """
    existing = client.paged(f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations?limit=200")
    for loc in existing:
        if loc["attributes"].get("locale") == locale:
            return loc
    if not create:
        return None
    body = {
        "data": {
            "type": "appStoreVersionLocalizations",
            "attributes": {"locale": locale},
            "relationships": {
                "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}}
            },
        }
    }
    status, doc = client.call("POST", "/v1/appStoreVersionLocalizations", body)
    if status in (200, 201):
        return doc["data"]
    if status == 409:
        # "There is an entity with same 'locale'" — someone (or a previous run)
        # created it in the meantime.
        for loc in client.paged(
            f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations?limit=200"
        ):
            if loc["attributes"].get("locale") == locale:
                return loc
    raise SystemExit(f"POST /v1/appStoreVersionLocalizations ({locale}) -> HTTP {status}: {_errors(doc)}")


def screenshot_set(localization_id: str, display_type: str, create: bool = True) -> dict | None:
    """The `appScreenshotSet` for `display_type`, created if missing.

    `create=False` for a dry run, as with `localization`."""
    existing = client.paged(
        f"/v1/appStoreVersionLocalizations/{localization_id}/appScreenshotSets?limit=200"
    )
    for candidate in existing:
        if candidate["attributes"].get("screenshotDisplayType") == display_type:
            return candidate
    if not create:
        return None
    body = {
        "data": {
            "type": "appScreenshotSets",
            "attributes": {"screenshotDisplayType": display_type},
            "relationships": {
                "appStoreVersionLocalization": {
                    "data": {"type": "appStoreVersionLocalizations", "id": localization_id}
                }
            },
        }
    }
    status, doc = client.call("POST", "/v1/appScreenshotSets", body)
    if status in (200, 201):
        return doc["data"]
    if status == 409:
        for candidate in client.paged(
            f"/v1/appStoreVersionLocalizations/{localization_id}/appScreenshotSets?limit=200"
        ):
            if candidate["attributes"].get("screenshotDisplayType") == display_type:
                return candidate
        # A 409 on an unknown display type lists every valid value — the
        # cheapest way to find out what Apple renamed this time.
        raise SystemExit(
            f"POST /v1/appScreenshotSets ({display_type}) -> HTTP 409: {_errors(doc)}"
        )
    raise SystemExit(f"POST /v1/appScreenshotSets ({display_type}) -> HTTP {status}: {_errors(doc)}")


def set_screenshots(set_id: str) -> list[dict]:
    return client.paged(f"/v1/appScreenshotSets/{set_id}/appScreenshots?limit=200")


def delete_screenshots(shots: list[dict]) -> None:
    for shot in shots:
        status, doc = client.call("DELETE", f"/v1/appScreenshots/{shot['id']}")
        if status not in (200, 204):
            raise SystemExit(f"DELETE /v1/appScreenshots/{shot['id']} -> HTTP {status}: {_errors(doc)}")
        print(f"    deleted {shot['attributes'].get('fileName', shot['id'])}")


def reserve(set_id: str, shot: Shot) -> dict:
    body = {
        "data": {
            "type": "appScreenshots",
            "attributes": {"fileName": shot.name, "fileSize": shot.size},
            "relationships": {
                "appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}
            },
        }
    }
    status, doc = client.call("POST", "/v1/appScreenshots", body)
    if status not in (200, 201):
        raise SystemExit(f"POST /v1/appScreenshots ({shot.name}) -> HTTP {status}: {_errors(doc)}")
    return doc["data"]


def put_bytes(operations: list[dict], data: bytes, file_name: str) -> None:
    """PUT each chunk Apple asked for, to the URL and headers it returned.

    `urllib` has been seen dying mid-stream on the presigned S3 PUT on some
    machines; `curl --data-binary` is the proven fallback and is tried once per
    chunk before giving up.
    """
    for index, op in enumerate(operations, start=1):
        offset = int(op.get("offset") or 0)
        length = int(op.get("length") or (len(data) - offset))
        chunk = data[offset : offset + length]
        headers = {h["name"]: h["value"] for h in op.get("requestHeaders") or []}
        method = op.get("method", "PUT")
        request = urllib.request.Request(op["url"], data=chunk, method=method)
        for name, value in headers.items():
            request.add_header(name, value)
        try:
            with urllib.request.urlopen(request) as response:
                if response.status not in (200, 201, 204):
                    raise urllib.error.URLError(f"HTTP {response.status}")
            print(f"    chunk {index}/{len(operations)}: {len(chunk)} bytes")
            continue
        except (urllib.error.URLError, OSError) as exc:
            print(f"    chunk {index}: urllib failed ({exc}); retrying with curl", file=sys.stderr)
        _put_with_curl(op["url"], method, headers, chunk, file_name, index)


def _put_with_curl(url: str, method: str, headers: dict, chunk: bytes, file_name: str, index: int) -> None:
    import shutil
    import subprocess
    import tempfile

    if not shutil.which("curl"):
        raise SystemExit(f"urllib could not upload {file_name} chunk {index} and curl is not installed")
    with tempfile.NamedTemporaryFile(prefix="asc-chunk-", suffix=".bin") as handle:
        handle.write(chunk)
        handle.flush()
        command = ["curl", "-sS", "--fail", "-X", method, "--data-binary", f"@{handle.name}"]
        for name, value in headers.items():
            command += ["-H", f"{name}: {value}"]
        command.append(url)
        result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        raise SystemExit(
            f"curl could not upload {file_name} chunk {index}: {result.stderr.strip()}"
        )
    print(f"    chunk {index}: {len(chunk)} bytes (curl)")


def commit(screenshot_id: str, checksum: str, file_name: str) -> None:
    body = {
        "data": {
            "type": "appScreenshots",
            "id": screenshot_id,
            "attributes": {"uploaded": True, "sourceFileChecksum": checksum},
        }
    }
    status, doc = client.call("PATCH", f"/v1/appScreenshots/{screenshot_id}", body)
    if status not in (200, 201):
        raise SystemExit(f"PATCH /v1/appScreenshots/{screenshot_id} ({file_name}) -> HTTP {status}: {_errors(doc)}")


def wait_for_delivery(screenshot_id: str, file_name: str, timeout: int = 180) -> str:
    """Poll until Apple says the asset arrived. A FAILED state means the
    checksum or a byte range was wrong: delete the resource and redo."""
    deadline = time.time() + timeout
    state = "UNKNOWN"
    while time.time() < deadline:
        status, doc = client.call("GET", f"/v1/appScreenshots/{screenshot_id}")
        if status != 200:
            raise SystemExit(f"GET /v1/appScreenshots/{screenshot_id} -> HTTP {status}: {_errors(doc)}")
        delivery = doc.get("data", {}).get("attributes", {}).get("assetDeliveryState") or {}
        state = delivery.get("state", "UNKNOWN")
        if state in ("COMPLETE", "UPLOAD_COMPLETE"):
            return state
        if state == "FAILED" or delivery.get("errors"):
            raise SystemExit(
                f"{file_name}: asset delivery {state}: {json.dumps(delivery.get('errors', []))}"
            )
        time.sleep(3)
    print(f"    warning: {file_name} still {state} after {timeout}s", file=sys.stderr)
    return state


def reorder(set_id: str, ids: list[str]) -> None:
    """Best effort: put the set in the order the file names asked for.

    The documented verb has moved around (PATCH on the relationship now, POST
    historically), and a wrong order is cosmetic — so this never fails the run.
    """
    body = {"data": [{"type": "appScreenshots", "id": i} for i in ids]}
    path = f"/v1/appScreenshotSets/{set_id}/relationships/appScreenshots"
    status, doc = client.call("PATCH", path, body)
    if status not in (200, 204):
        status, doc = client.call("POST", path, body)
    if status not in (200, 204):
        print(f"    warning: could not set the display order ({status}): {_errors(doc)}", file=sys.stderr)


# --------------------------------------------------------------------------


def print_plan(groups: dict[tuple[str, str], list[Shot]]) -> None:
    for (locale, display_type), shots in groups.items():
        print(f"{locale}  {display_type}  ({len(shots)} images)")
        for shot in shots:
            print(f"  {shot.order:>3}  {shot.name:<28} {shot.size:>9} bytes  {shot.path}")
        if len(shots) > MAX_PER_SET:
            print(f"  warning: {len(shots)} images, App Store Connect accepts {MAX_PER_SET}")


def main(argv: list[str] | None = None) -> int:
    global PLATFORM
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("paths", nargs="+", type=pathlib.Path, help="directories holding <device>/<locale>_<nn>_<name>.png")
    parser.add_argument("--app-id", default=os.environ.get("ASC_APP_ID", ""), help="numeric app id (default: $ASC_APP_ID)")
    parser.add_argument("--version", default="", help="version string to create if no editable version exists (default: app/pubspec.yaml)")
    parser.add_argument("--platform", choices=("IOS", "MAC_OS"), default="IOS", help="App Store platform containing the editable version")
    parser.add_argument("--replace", action="store_true", help="delete the screenshots already in each set first")
    parser.add_argument("--dry-run", action="store_true", help="print the plan and touch nothing")
    args = parser.parse_args(argv)
    PLATFORM = args.platform

    groups = collect(args.paths)
    if not groups:
        print("no usable screenshots found", file=sys.stderr)
        return 1
    total = sum(len(s) for s in groups.values())
    print(f"== {total} screenshots in {len(groups)} sets")
    print_plan(groups)

    if not args.app_id:
        print("no app id: pass --app-id or set ASC_APP_ID", file=sys.stderr)
        return 0 if args.dry_run else 1

    wanted_version = args.version or version_string()

    if args.dry_run and not (
        os.environ.get("ASC_API_KEY_P8_BASE64")
        or (client.ROOT / ".appstoreconnect" / f"AuthKey_{client.KEY_ID}.p8").exists()
        or (pathlib.Path.home() / ".appstoreconnect" / "private_keys" / f"AuthKey_{client.KEY_ID}.p8").exists()
    ):
        print("\nno API key available; stopping after the local plan (dry run)")
        return 0

    print(f"\n== app {args.app_id}")
    version = editable_version(args.app_id)
    if version is None:
        if args.dry_run:
            print(f"would create appStoreVersion {wanted_version} ({PLATFORM})")
            return 0
        print(f"no editable version — creating {wanted_version} ({PLATFORM})")
        version = create_version(args.app_id, wanted_version)
    version_id = version["id"]
    print(
        f"version {version['attributes'].get('versionString')} "
        f"({version['attributes'].get('appStoreState')}) id={version_id}"
    )

    for (locale, display_type), shots in groups.items():
        print(f"\n== {locale} / {display_type}")
        loc = localization(version_id, locale, create=not args.dry_run)
        if loc is None:
            print(f"  would create the {locale} localization, its {display_type} set")
            for shot in shots:
                print(f"  would upload {shot.name} ({shot.size} bytes)")
            continue
        print(f"  localization {loc['id']}")
        target = screenshot_set(loc["id"], display_type, create=not args.dry_run)
        if target is None:
            print(f"  would create the {display_type} set")
            for shot in shots:
                print(f"  would upload {shot.name} ({shot.size} bytes)")
            continue
        set_id = target["id"]
        print(f"  set {set_id}")
        present = set_screenshots(set_id)
        if present:
            names = ", ".join(s["attributes"].get("fileName", s["id"]) for s in present)
            print(f"  already there: {names}")
        if args.replace and present:
            if args.dry_run:
                print(f"  would delete {len(present)} existing screenshots")
            else:
                delete_screenshots(present)
                present = []
        if len(present) + len(shots) > MAX_PER_SET:
            print(
                f"  warning: {len(present)} existing + {len(shots)} new exceeds the "
                f"{MAX_PER_SET} per set Apple allows; use --replace",
                file=sys.stderr,
            )
        if args.dry_run:
            for shot in shots:
                print(f"  would upload {shot.name} ({shot.size} bytes)")
            continue
        uploaded: list[str] = []
        for shot in shots:
            print(f"  {shot.name} ({shot.size} bytes)")
            reserved = reserve(set_id, shot)
            operations = reserved["attributes"].get("uploadOperations") or []
            if not operations:
                raise SystemExit(f"{shot.name}: Apple returned no uploadOperations")
            put_bytes(operations, shot.path.read_bytes(), shot.name)
            commit(reserved["id"], shot.checksum(), shot.name)
            state = wait_for_delivery(reserved["id"], shot.name)
            print(f"    {state}")
            uploaded.append(reserved["id"])
        ids = [s["id"] for s in present] + uploaded
        reorder(set_id, ids)

    print("\ndone. The version is not submitted for review — that stays a human decision.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
