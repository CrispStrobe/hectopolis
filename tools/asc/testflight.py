# SPDX-License-Identifier: AGPL-3.0-or-later
#!/usr/bin/env python3
"""Audit or prepare the newest Hectopolis build for external TestFlight."""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import sys
import time
import urllib.parse

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import client  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parents[2]
META = json.loads((ROOT / "data/store/metadata.json").read_text())


def query(path: str, **params: str) -> str:
    return f"{path}?{urllib.parse.urlencode(params)}"


def attributes(item: dict, *names: str) -> dict:
    values = item.get("attributes", {})
    return {name: values.get(name) for name in names}


def patch(resource_type: str, resource_id: str, attrs: dict) -> None:
    client.expect(
        "PATCH",
        f"/v1/{resource_type}/{resource_id}",
        {"data": {"type": resource_type, "id": resource_id, "attributes": attrs}},
    )


def upsert_localization(
    collection_path: str,
    resource_type: str,
    locale: str,
    attrs: dict,
    relationship_name: str,
    relationship_type: str,
    relationship_id: str,
) -> dict:
    existing = client.paged(collection_path)
    found = next((item for item in existing if item["attributes"].get("locale") == locale), None)
    if found:
        patch(resource_type, found["id"], attrs)
        return found
    body = {
        "data": {
            "type": resource_type,
            "attributes": {"locale": locale, **attrs},
            "relationships": {
                relationship_name: {
                    "data": {"type": relationship_type, "id": relationship_id}
                }
            },
        }
    }
    return client.expect("POST", f"/v1/{resource_type}", body)["data"]


def newest_build(app_id: str, build_number: str | None, wait_minutes: int) -> dict:
    deadline = time.time() + wait_minutes * 60
    while True:
        params = {"filter[app]": app_id, "sort": "-uploadedDate", "limit": "50"}
        if build_number:
            params["filter[version]"] = build_number
        builds = client.paged(query("/v1/builds", **params))
        if builds:
            build = builds[0]
            state = build["attributes"].get("processingState")
            print("build", build["id"], attributes(build, "version", "uploadedDate", "processingState"))
            if state in ("VALID", "FAILED", "INVALID"):
                if state != "VALID":
                    raise SystemExit(f"newest build processing state is {state}")
                return build
        if time.time() >= deadline:
            raise SystemExit("no valid matching build before the wait deadline")
        print("waiting for App Store Connect processing…", flush=True)
        time.sleep(30)


def external_group(app_id: str) -> dict:
    groups = client.paged(f"/v1/apps/{app_id}/betaGroups?limit=200")
    found = next((g for g in groups if g["attributes"].get("name") == "Public Beta"), None)
    if found:
        if found["attributes"].get("isInternalGroup"):
            raise SystemExit("Public Beta exists but is an internal group")
        return found
    body = {
        "data": {
            "type": "betaGroups",
            "attributes": {"name": "Public Beta", "isInternalGroup": False},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
        }
    }
    return client.expect("POST", "/v1/betaGroups", body)["data"]


def audit(app_id: str) -> None:
    app = client.expect("GET", f"/v1/apps/{app_id}")["data"]
    print("app", app_id, attributes(app, "name", "bundleId", "primaryLocale"))
    for path, label in [
        (f"/v1/apps/{app_id}/appStoreVersions?limit=50", "versions"),
        (f"/v1/apps/{app_id}/betaGroups?limit=50", "beta groups"),
        (query("/v1/builds", **{"filter[app]": app_id, "sort": "-uploadedDate", "limit": "10"}), "builds"),
    ]:
        print(label)
        for item in client.paged(path):
            print(" ", item["id"], item.get("attributes", {}))
    infos = client.paged(f"/v1/apps/{app_id}/appInfos?limit=50")
    for info in infos:
        print("app info", info["id"], info.get("attributes", {}))
        for suffix, label in [
            ("ageRatingDeclaration", "age rating"),
            ("appInfoLocalizations?limit=50", "info localizations"),
        ]:
            status, doc = client.call("GET", f"/v1/appInfos/{info['id']}/{suffix}")
            print(label, "HTTP", status, doc.get("data"))
    status, doc = client.call("GET", f"/v1/apps/{app_id}/appPriceSchedule")
    print("price schedule", "HTTP", status, doc.get("data"))
    for version in client.paged(f"/v1/apps/{app_id}/appStoreVersions?limit=50"):
        if version["attributes"].get("platform") != "IOS":
            continue
        version_id = version["id"]
        for suffix, label in [
            ("build", "attached build"),
            ("appStoreVersionLocalizations?limit=50", "version localizations"),
            ("appStoreReviewDetail", "review detail"),
        ]:
            status, doc = client.call("GET", f"/v1/appStoreVersions/{version_id}/{suffix}")
            print(label, "HTTP", status, doc.get("data"))


def prepare_external(app_id: str, build_number: str | None, wait_minutes: int) -> None:
    app = client.expect("GET", f"/v1/apps/{app_id}")["data"]
    primary = app["attributes"]["primaryLocale"]
    if primary not in META["locales"]:
        raise SystemExit(f"metadata is missing primary locale {primary}")
    build = newest_build(app_id, build_number, wait_minutes)
    build_id = build["id"]
    if build["attributes"].get("usesNonExemptEncryption") is not False:
        patch("builds", build_id, {"usesNonExemptEncryption": False})
    else:
        print("export compliance already resolved: exempt")

    contact = META["contact"]
    patch(
        "betaAppReviewDetails",
        app_id,
        {
            "contactFirstName": contact["firstName"],
            "contactLastName": contact["lastName"],
            "contactPhone": contact["phone"],
            "contactEmail": contact["email"],
            "demoAccountRequired": False,
            "notes": "No account or login is required. The app works offline and collects no data.",
        },
    )
    for locale, copy in META["locales"].items():
        upsert_localization(
            f"/v1/apps/{app_id}/betaAppLocalizations?limit=200",
            "betaAppLocalizations",
            locale,
            {
                "description": copy["betaDescription"],
                "feedbackEmail": contact["email"],
                "marketingUrl": META["marketingUrl"],
                "privacyPolicyUrl": META["privacyPolicyUrl"],
            },
            "app",
            "apps",
            app_id,
        )
        upsert_localization(
            f"/v1/builds/{build_id}/betaBuildLocalizations?limit=200",
            "betaBuildLocalizations",
            locale,
            {"whatsNew": copy["whatsNew"]},
            "build",
            "builds",
            build_id,
        )

    group = external_group(app_id)
    status, doc = client.call(
        "POST",
        f"/v1/betaGroups/{group['id']}/relationships/builds",
        {"data": [{"type": "builds", "id": build_id}]},
    )
    if status not in (200, 204, 409):
        raise SystemExit(f"assign build to Public Beta -> HTTP {status}: {doc}")

    status, existing = client.call("GET", f"/v1/builds/{build_id}/betaAppReviewSubmission")
    if status == 200 and existing.get("data"):
        print("beta review already exists", existing["data"].get("attributes", {}))
    else:
        submission = client.expect(
            "POST",
            "/v1/betaAppReviewSubmissions",
            {
                "data": {
                    "type": "betaAppReviewSubmissions",
                    "relationships": {"build": {"data": {"type": "builds", "id": build_id}}},
                }
            },
        )["data"]
        print("submitted external beta review", submission["id"], submission["attributes"])
    print("Public Beta group", group["id"], "build", build_id)


def prepare_store(app_id: str, build_number: str | None, wait_minutes: int) -> None:
    """Complete API-editable fields needed before full App Store review."""
    versions = client.paged(f"/v1/apps/{app_id}/appStoreVersions?limit=50")
    candidates = [
        version
        for version in versions
        if version["attributes"].get("platform") == "IOS"
        and version["attributes"].get("appStoreState") == "PREPARE_FOR_SUBMISSION"
    ]
    if len(candidates) != 1:
        raise SystemExit(
            f"expected one editable iOS App Store version, found {len(candidates)}"
        )
    version = candidates[0]
    build = newest_build(app_id, build_number, wait_minutes)

    infos = client.paged(f"/v1/apps/{app_id}/appInfos?limit=50")
    if len(infos) != 1:
        raise SystemExit(f"expected one app info, found {len(infos)}")
    rating_id = infos[0]["id"]
    no_content_rating = {
        "advertising": False,
        "alcoholTobaccoOrDrugUseOrReferences": "NONE",
        "contests": "NONE",
        "gambling": False,
        "gamblingSimulated": "NONE",
        "gunsOrOtherWeapons": "NONE",
        "healthOrWellnessTopics": False,
        "lootBox": False,
        "medicalOrTreatmentInformation": "NONE",
        "messagingAndChat": False,
        "parentalControls": False,
        "profanityOrCrudeHumor": "NONE",
        "ageAssurance": False,
        "sexualContentGraphicAndNudity": "NONE",
        "sexualContentOrNudity": "NONE",
        "socialMedia": False,
        "socialMediaAgeRestricted": False,
        "horrorOrFearThemes": "NONE",
        "matureOrSuggestiveThemes": "NONE",
        "unrestrictedWebAccess": False,
        "userGeneratedContent": False,
        "violenceCartoonOrFantasy": "NONE",
        "violenceRealisticProlongedGraphicOrSadistic": "NONE",
        "violenceRealistic": "NONE",
    }
    patch("ageRatingDeclarations", rating_id, no_content_rating)
    print("age rating questionnaire completed: no objectionable content")

    schedule = client.expect("GET", f"/v1/apps/{app_id}/appPriceSchedule")["data"]
    # Apple's `related` manualPrices URL currently 404s even though the
    # relationship is present. The relationship-link endpoint returns the
    # same appPrice identifiers reliably.
    prices = client.paged(
        f"/v1/appPriceSchedules/{schedule['id']}/relationships/manualPrices?limit=200"
    )
    if not prices:
        raise SystemExit("price schedule has no manual base price; review it in ASC")
    price_points = []
    for price in prices:
        point = client.expect(
            "GET", f"/v1/appPrices/{price['id']}/appPricePoint"
        )["data"]
        price_points.append(point["attributes"].get("customerPrice"))
    if not any(str(value) in ("0", "0.0", "0.00") for value in price_points):
        raise SystemExit(f"existing price schedule is not free: {price_points}")
    print("price schedule verified free", price_points)

    client.expect(
        "PATCH",
        f"/v1/appStoreVersions/{version['id']}/relationships/build",
        {"data": {"type": "builds", "id": build["id"]}},
    )
    print(
        "attached build",
        build["attributes"].get("version"),
        "to iOS version",
        version["attributes"].get("versionString"),
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "action", choices=("audit", "ready-store", "submit-external")
    )
    parser.add_argument("--build-number")
    parser.add_argument("--wait-minutes", type=int, default=30)
    args = parser.parse_args()
    app_id = os.environ.get("ASC_APP_ID") or client.app_id(META["bundleId"])
    if not app_id:
        raise SystemExit("Hectopolis app record not found")
    if args.action == "audit":
        audit(app_id)
    elif args.action == "ready-store":
        prepare_store(app_id, args.build_number, args.wait_minutes)
    else:
        prepare_external(app_id, args.build_number, args.wait_minutes)


if __name__ == "__main__":
    main()
