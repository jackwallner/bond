#!/usr/bin/env python3
"""Attach a build to an App Store version and submit it for review.

fastlane deliver's submit path hangs forever on "Waiting for the build to show
up in the build list" (the legacy Tunes API can't see API-uploaded builds), so
this drives the ASC reviewSubmissions API directly.

Usage:
  ./scripts/asc-submit-for-review.py --version 1.0.6 --build 38 [--dry-run]
"""
from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from asc_lib import (
    ASCClient,
    bearer_token,
    bundle_id_from_appfile,
    find_app,
    find_version_by_string,
    list_all,
    load_credentials,
)


def retry(label: str, call, attempts: int = 5, delay: int = 8):
    """ASC's reviewSubmission endpoints return sporadic 500s that clear on retry."""
    for attempt in range(1, attempts + 1):
        try:
            return call()
        except RuntimeError as e:
            if attempt == attempts or "500" not in str(e):
                raise
            print(f"  {label}: attempt {attempt} hit a 500, retrying in {delay}s")
            time.sleep(delay)


def find_build(client: ASCClient, app_id: str, build_number: str) -> dict:
    builds = list_all(
        client, f"/builds?filter[app]={app_id}&filter[version]={build_number}&limit=10"
    )
    if not builds:
        raise SystemExit(f"error: build {build_number} not found for app {app_id}")
    build = builds[0]
    state = build["attributes"].get("processingState")
    if state != "VALID":
        raise SystemExit(f"error: build {build_number} is {state}, not VALID yet")
    return build


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", required=True, help="marketing version, e.g. 1.0.6")
    parser.add_argument("--build", required=True, help="build number, e.g. 38")
    parser.add_argument(
        "--release-type",
        default="AFTER_APPROVAL",
        choices=["AFTER_APPROVAL", "MANUAL", "SCHEDULED"],
    )
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    client = ASCClient(bearer_token(*load_credentials()))
    app = find_app(client, bundle_id_from_appfile())
    app_id = app["id"]

    version = find_version_by_string(client, app_id, args.version)
    if not version:
        raise SystemExit(f"error: no App Store version {args.version}")
    version_id = version["id"]
    state = version["attributes"].get("appStoreState")
    if state != "PREPARE_FOR_SUBMISSION":
        raise SystemExit(f"error: {args.version} is {state}, not PREPARE_FOR_SUBMISSION")

    build = find_build(client, app_id, args.build)

    open_subs = [
        s
        for s in list_all(client, f"/reviewSubmissions?filter[app]={app_id}&limit=50")
        if s["attributes"].get("state") in {"READY_FOR_REVIEW", "WAITING_FOR_REVIEW", "IN_REVIEW"}
    ]

    print(f"app       {app_id} ({app['attributes'].get('name')})")
    print(f"version   {args.version} [{version_id}] state={state}")
    print(f"build     {args.build} [{build['id']}] state=VALID")
    print(f"release   {args.release_type}")
    print(f"open review submissions: {[s['attributes'].get('state') for s in open_subs] or 'none'}")

    if open_subs:
        raise SystemExit("error: an open review submission already exists; resolve it first")
    if args.dry_run:
        print("\ndry run, nothing submitted")
        return

    client.patch(
        f"/appStoreVersions/{version_id}/relationships/build",
        {"data": {"type": "builds", "id": build["id"]}},
    )
    print("attached build")

    client.patch(
        f"/appStoreVersions/{version_id}",
        {
            "data": {
                "type": "appStoreVersions",
                "id": version_id,
                "attributes": {"releaseType": args.release_type},
            }
        },
    )
    print(f"set releaseType {args.release_type}")

    submission = retry(
        "create submission",
        lambda: client.post(
            "/reviewSubmissions",
            {
                "data": {
                    "type": "reviewSubmissions",
                    "attributes": {"platform": "IOS"},
                    "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
                }
            },
        ),
    )["data"]
    submission_id = submission["id"]
    print(f"created reviewSubmission {submission_id}")

    retry(
        "add item",
        lambda: client.post(
            "/reviewSubmissionItems",
            {
                "data": {
                    "type": "reviewSubmissionItems",
                    "relationships": {
                        "reviewSubmission": {
                            "data": {"type": "reviewSubmissions", "id": submission_id}
                        },
                        "appStoreVersion": {
                            "data": {"type": "appStoreVersions", "id": version_id}
                        },
                    },
                }
            },
        ),
    )
    print("added version to submission")

    result = retry(
        "submit",
        lambda: client.patch(
            f"/reviewSubmissions/{submission_id}",
            {
                "data": {
                    "type": "reviewSubmissions",
                    "id": submission_id,
                    "attributes": {"submitted": True},
                }
            },
        ),
    )
    print(f"submitted; state={result['data']['attributes'].get('state')}")


if __name__ == "__main__":
    main()
