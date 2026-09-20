# SPDX-License-Identifier: AGPL-3.0-or-later
#!/usr/bin/env python3
"""List, or turn on, the public TestFlight links of every app on the account.

    python3 tools/asc/beta_links.py list
    python3 tools/asc/beta_links.py enable --app <appId> [--app <appId> ...]
    python3 tools/asc/beta_links.py enable --all --confirm

`list` is read-only and reports, per app and external group, whether a public
link exists and whether the group can actually serve one: a public link only
does something if the group holds a build whose beta review Apple has approved.

`enable` is not. A public link is a URL anyone can use to join the beta, and a
URL that has been handed out cannot be recalled by turning the flag off again.
So it takes explicit app ids, and `--all` additionally requires `--confirm`.

This walks the whole account rather than ASC_APP_ID, because the question it
answers is about the portfolio.
"""

from __future__ import annotations

import argparse
import pathlib
import sys
import urllib.parse

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import client  # noqa: E402


def query(path: str, **params: str) -> str:
    return f"{path}?{urllib.parse.urlencode(params)}"


def approved_build(group_id: str) -> tuple[str | None, str]:
    """The newest build in the group, and what beta review made of it."""
    builds = client.paged(query(f"/v1/betaGroups/{group_id}/builds",
                                sort="-uploadedDate", limit="10"))
    if not builds:
        return None, "no build in the group"
    for build in builds:
        version = build["attributes"].get("version")
        status, doc = client.call(
            "GET", f"/v1/builds/{build['id']}/betaAppReviewSubmission")
        data = doc.get("data") if status == 200 else None
        state = (data or {}).get("attributes", {}).get("betaReviewState")
        if state == "APPROVED":
            return version, "approved"
        if state:
            return version, state.lower().replace("_", " ")
    newest = builds[0]["attributes"].get("version")
    return newest, "never submitted for beta review"


def groups_of(app_id: str) -> list[dict]:
    return client.paged(query(f"/v1/apps/{app_id}/betaGroups", limit="50"))


def report(apps: list[dict]) -> int:
    linked = 0
    for app in apps:
        attrs = app["attributes"]
        print(f"\n{attrs.get('name')}  ({attrs.get('bundleId')})  id {app['id']}")
        external = [g for g in groups_of(app["id"])
                    if not g["attributes"].get("isInternalGroup")]
        if not external:
            print("   no external group — nothing to make public")
            continue
        for group in external:
            g = group["attributes"]
            version, review = approved_build(group["id"])
            state = "ON " if g.get("publicLinkEnabled") else "off"
            print(f"   [{state}] {g.get('name')}")
            print(f"         build {version or '—'}: {review}")
            if g.get("publicLink"):
                linked += 1
                print(f"         {g['publicLink']}")
            elif g.get("publicLinkEnabled"):
                print("         enabled but Apple has issued no URL yet")
    print(f"\n{linked} public link(s) across {len(apps)} app(s)")
    return 0


def enable(apps: list[dict], wanted: set[str]) -> int:
    failures = 0
    for app in apps:
        if app["id"] not in wanted:
            continue
        name = app["attributes"].get("name")
        for group in groups_of(app["id"]):
            g = group["attributes"]
            if g.get("isInternalGroup"):
                continue
            version, review = approved_build(group["id"])
            if review != "approved":
                print(f"{name}: {g.get('name')} skipped — build "
                      f"{version or '—'} is {review}; a public link would "
                      f"hand out a URL that installs nothing")
                failures += 1
                continue
            status, doc = client.call(
                "PATCH", f"/v1/betaGroups/{group['id']}",
                {"data": {"type": "betaGroups", "id": group["id"],
                          "attributes": {"publicLinkEnabled": True}}})
            if status not in (200, 204):
                print(f"{name}: {g.get('name')} -> HTTP {status}: {doc}")
                failures += 1
                continue
            link = (doc.get("data", {}).get("attributes", {}) or {}).get("publicLink")
            print(f"{name}: {g.get('name')} -> {link or 'enabled, URL pending'}")
    return 1 if failures else 0


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("list", "enable"))
    parser.add_argument("--app", action="append", default=[],
                        help="app id to enable; repeatable")
    parser.add_argument("--all", action="store_true",
                        help="every app on the account (needs --confirm)")
    parser.add_argument("--confirm", action="store_true")
    args = parser.parse_args()

    apps = client.paged(query("/v1/apps", limit="200", sort="name"))
    if not apps:
        raise SystemExit("no apps on this account")
    if args.action == "list":
        raise SystemExit(report(apps))

    if args.all:
        if not args.confirm:
            raise SystemExit(
                "--all opens a public beta for every app on the account. "
                "Re-run with --confirm if that is really the intent.")
        wanted = {app["id"] for app in apps}
    elif args.app:
        wanted = set(args.app)
        unknown = wanted - {app["id"] for app in apps}
        if unknown:
            raise SystemExit(f"not apps on this account: {sorted(unknown)}")
    else:
        raise SystemExit("enable needs --app <id> (repeatable) or --all")
    raise SystemExit(enable(apps, wanted))


if __name__ == "__main__":
    main()
