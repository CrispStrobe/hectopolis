# SPDX-License-Identifier: AGPL-3.0-or-later
#!/usr/bin/env python3
"""Apply the version-controlled Hectopolis App Store listing."""

from __future__ import annotations

import json
import os
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import client  # noqa: E402
import upload_screenshots  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parents[2]
META = json.loads((ROOT / "data/store/metadata.json").read_text())


def patch(resource_type: str, resource_id: str, *, attrs=None, relationships=None):
    data = {"type": resource_type, "id": resource_id}
    if attrs is not None:
        data["attributes"] = attrs
    if relationships is not None:
        data["relationships"] = relationships
    return client.expect("PATCH", f"/v1/{resource_type}/{resource_id}", {"data": data})


def upsert(collection: str, resource_type: str, locale: str, attrs: dict, parent: tuple[str, str, str]):
    for item in client.paged(collection):
        if item["attributes"].get("locale") == locale:
            patch(resource_type, item["id"], attrs=attrs)
            return item
    relationship, parent_type, parent_id = parent
    body = {
        "data": {
            "type": resource_type,
            "attributes": {"locale": locale, **attrs},
            "relationships": {relationship: {"data": {"type": parent_type, "id": parent_id}}},
        }
    }
    return client.expect("POST", f"/v1/{resource_type}", body)["data"]


def editable_info(app_id: str) -> dict:
    infos = client.paged(f"/v1/apps/{app_id}/appInfos?limit=50")
    editable = [
        info
        for info in infos
        if info["attributes"].get("appStoreState") not in ("READY_FOR_SALE", "REPLACED_WITH_NEW_VERSION")
    ]
    if not editable:
        raise SystemExit("no editable appInfo")
    return editable[0]


def review_details(version_id: str) -> None:
    contact = META["contact"]
    attrs = {
        "contactFirstName": contact["firstName"],
        "contactLastName": contact["lastName"],
        "contactPhone": contact["phone"],
        "contactEmail": contact["email"],
        "demoAccountRequired": False,
        "notes": "No account or login is required. The app is fully usable offline. Start any scenario and place tiles to review all features.",
    }
    status, doc = client.call("GET", f"/v1/appStoreVersions/{version_id}/appStoreReviewDetail")
    if status == 200 and doc.get("data"):
        patch("appStoreReviewDetails", doc["data"]["id"], attrs=attrs)
        return
    body = {
        "data": {
            "type": "appStoreReviewDetails",
            "attributes": attrs,
            "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}}},
        }
    }
    client.expect("POST", "/v1/appStoreReviewDetails", body)


def main() -> None:
    app_id = os.environ.get("ASC_APP_ID") or client.app_id(META["bundleId"])
    if not app_id:
        raise SystemExit("Hectopolis app record not found")
    versions = client.paged(f"/v1/apps/{app_id}/appStoreVersions?limit=50")
    version = next(
        (v for v in versions if v["attributes"].get("platform") == "IOS" and v["attributes"].get("appStoreState") == "PREPARE_FOR_SUBMISSION"),
        None,
    )
    if version is None:
        version = upload_screenshots.editable_version(app_id)
    if version is None:
        version = upload_screenshots.create_version(app_id, META["version"])
    version_id = version["id"]
    patch(
        "appStoreVersions",
        version_id,
        attrs={
            "versionString": META["version"],
            "copyright": META["copyright"],
            "usesIdfa": False,
        },
    )

    for locale, copy in META["locales"].items():
        loc = upload_screenshots.localization(version_id, locale, create=True)
        patch(
            "appStoreVersionLocalizations",
            loc["id"],
            attrs={
                "description": copy["description"],
                "keywords": copy["keywords"],
                "promotionalText": copy["promotionalText"],
                "supportUrl": META["supportUrl"],
                "marketingUrl": META["marketingUrl"],
            },
        )

    info = editable_info(app_id)
    info_id = info["id"]
    patch(
        "appInfos",
        info_id,
        relationships={
            "primaryCategory": {"data": {"type": "appCategories", "id": META["category"]}},
            "primarySubcategoryOne": {"data": {"type": "appCategories", "id": META["subcategory"]}},
        },
    )
    for locale, copy in META["locales"].items():
        upsert(
            f"/v1/appInfos/{info_id}/appInfoLocalizations?limit=100",
            "appInfoLocalizations",
            locale,
            {"subtitle": copy["subtitle"], "privacyPolicyUrl": META["privacyPolicyUrl"]},
            ("appInfo", "appInfos", info_id),
        )
    review_details(version_id)
    print("listing applied", {"app": app_id, "version": version_id, "appInfo": info_id})
    print("remaining browser-only gate: App Privacy must say Data Not Collected")


if __name__ == "__main__":
    main()
