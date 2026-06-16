#!/usr/bin/env python3
"""Minimal App Store Connect API client for Bond.

Reads creds from ~/.baseball_credentials (ASC_API_KEY_ID, ASC_ISSUER_ID,
ASC_KEY_PATH). Subcommands:

  status                  show app version state + latest builds
  submit  [build_number]  assign build to the editable version and submit for review

No external deps beyond PyJWT + cryptography + requests (urllib fallback).
"""
import os
import re
import sys
import json
import time
import datetime
import urllib.request
import urllib.error

import jwt

BUNDLE_ID = "com.jackwallner.bond"
BASE = "https://api.appstoreconnect.apple.com/v1"


def load_creds():
    path = os.path.expanduser("~/.baseball_credentials")
    vals = {}
    with open(path) as f:
        for line in f:
            m = re.match(r"\s*(?:export\s+)?(ASC_[A-Z_]+)=(.+)", line)
            if m and not line.lstrip().startswith("#"):
                vals[m.group(1)] = m.group(2).strip().strip('"').strip("'")
    return vals


def make_token(creds):
    key = open(os.path.expanduser(os.path.expandvars(creds["ASC_KEY_PATH"]))).read()
    now = int(time.time())
    payload = {
        "iss": creds["ASC_ISSUER_ID"],
        "iat": now,
        "exp": now + 20 * 60,
        "aud": "appstoreconnect-v1",
    }
    return jwt.encode(payload, key, algorithm="ES256",
                      headers={"kid": creds["ASC_API_KEY_ID"], "typ": "JWT"})


TOKEN = None


def req(method, path, body=None, params=None):
    url = path if path.startswith("http") else BASE + path
    if params:
        from urllib.parse import urlencode
        url += "?" + urlencode(params)
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(url, data=data, method=method)
    r.add_header("Authorization", "Bearer " + TOKEN)
    r.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(r) as resp:
            raw = resp.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        print(f"HTTP {e.code} {method} {url}", file=sys.stderr)
        print(e.read().decode(), file=sys.stderr)
        raise


def app_id():
    d = req("GET", "/apps", params={"filter[bundleId]": BUNDLE_ID})
    return d["data"][0]["id"]


def editable_version(aid):
    d = req("GET", f"/apps/{aid}/appStoreVersions",
            params={"limit": 5})
    return d["data"]


def builds(aid, n=5):
    d = req("GET", "/builds",
            params={"filter[app]": aid, "limit": n,
                    "sort": "-version",
                    "fields[builds]": "version,processingState,uploadedDate,expired"})
    return d["data"]


def cmd_status():
    aid = app_id()
    print(f"app id: {aid}")
    print("\n=== App Store Versions ===")
    for v in editable_version(aid):
        a = v["attributes"]
        print(f"  {a['versionString']}  state={a['appStoreState']}  platform={a['platform']}  id={v['id']}")
    print("\n=== Recent builds ===")
    for b in builds(aid):
        a = b["attributes"]
        print(f"  build {a['version']}  {a['processingState']}  expired={a.get('expired')}  uploaded={a.get('uploadedDate')}  id={b['id']}")


def find_build(aid, version):
    for b in builds(aid, 10):
        if b["attributes"]["version"] == str(version):
            return b
    return None


FIX_NOTE = (
    "Re: Guideline 5.6.1 rejection. We removed the review prompt that asked "
    "users whether they were enjoying the app and only routed positive users "
    "to the App Store rating. The app now uses Apple's native StoreKit rating "
    "prompt (requestReview()) with no sentiment pre-screening, and Settings "
    "offers two ungated options shown to every user: \"Rate Bond on the App "
    "Store\" and \"Send Feedback.\" No user reviews are filtered."
)


def set_review_note(vid):
    d = req("GET", f"/appStoreVersions/{vid}/appStoreReviewDetail")
    detail = d.get("data")
    if detail:
        did = detail["id"]
        existing = (detail["attributes"].get("notes") or "").strip()
        if "5.6.1" in existing:
            print("review note already present; leaving as-is")
            return
        notes = (existing + "\n\n" + FIX_NOTE).strip() if existing else FIX_NOTE
        req("PATCH", f"/appStoreReviewDetails/{did}",
            body={"data": {"type": "appStoreReviewDetails", "id": did,
                           "attributes": {"notes": notes}}})
        print("updated review notes")
    else:
        req("POST", "/appStoreReviewDetails", body={
            "data": {"type": "appStoreReviewDetails",
                     "attributes": {"notes": FIX_NOTE},
                     "relationships": {"appStoreVersion": {
                         "data": {"type": "appStoreVersions", "id": vid}}}}})
        print("created review detail with note")


def cmd_submit(version):
    aid = app_id()
    versions = editable_version(aid)
    # editable states accept a new build + submission
    editable_states = {
        "PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED",
        "METADATA_REJECTED", "INVALID_BINARY",
    }
    target = None
    for v in versions:
        if v["attributes"]["appStoreState"] in editable_states:
            target = v
            break
    if not target:
        print("No editable app store version found. States:")
        for v in versions:
            print("  ", v["attributes"]["versionString"], v["attributes"]["appStoreState"])
        sys.exit(1)
    vid = target["id"]
    vstr = target["attributes"]["versionString"]
    print(f"target version {vstr} ({target['attributes']['appStoreState']}) id={vid}")

    b = find_build(aid, version)
    if not b:
        print(f"Build {version} not found yet.")
        sys.exit(2)
    if b["attributes"]["processingState"] != "VALID":
        print(f"Build {version} processingState={b['attributes']['processingState']} (need VALID). Try again later.")
        sys.exit(3)
    bid = b["id"]
    print(f"build {version} VALID id={bid}")

    # Attach build to version
    req("PATCH", f"/appStoreVersions/{vid}/relationships/build",
        body={"data": {"type": "builds", "id": bid}})
    print("attached build to version")

    # Add a review note explaining the 5.6.1 fix (preserve any demo-account fields).
    set_review_note(vid)

    # Create review submission for the app + add the version as an item.
    # ASC requires platform on the reviewSubmission.
    platform = target["attributes"]["platform"]
    try:
        sub = req("POST", "/reviewSubmissions", body={
            "data": {
                "type": "reviewSubmissions",
                "attributes": {"platform": platform},
                "relationships": {"app": {"data": {"type": "apps", "id": aid}}},
            }
        })
    except urllib.error.HTTPError:
        # An open submission may already exist; find it.
        existing = req("GET", "/reviewSubmissions",
                       params={"filter[app]": aid, "filter[state]": "READY_FOR_REVIEW,COMPLETING"})
        if not existing.get("data"):
            existing = req("GET", "/reviewSubmissions", params={"filter[app]": aid, "limit": 5})
        sub = {"data": existing["data"][0]}
        print("reusing existing review submission", sub["data"]["id"])
    sid = sub["data"]["id"]
    print(f"review submission id={sid} state={sub['data']['attributes'].get('state')}")

    # Add the version to the submission (idempotent-ish: ignore if already there)
    try:
        item = req("POST", "/reviewSubmissionItems", body={
            "data": {
                "type": "reviewSubmissionItems",
                "relationships": {
                    "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sid}},
                    "appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}},
                },
            }
        })
        print("added version to submission item", item["data"]["id"])
    except urllib.error.HTTPError:
        print("submission item may already exist; continuing")

    # Submit (state -> WAITING_FOR_REVIEW)
    req("PATCH", f"/reviewSubmissions/{sid}", body={
        "data": {"type": "reviewSubmissions", "id": sid,
                 "attributes": {"submitted": True}}
    })
    print("SUBMITTED for review.")


def main():
    global TOKEN
    creds = load_creds()
    TOKEN = make_token(creds)
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
    if cmd == "status":
        cmd_status()
    elif cmd == "submit":
        ver = sys.argv[2] if len(sys.argv) > 2 else "60"
        cmd_submit(ver)
    else:
        print(__doc__)
        sys.exit(1)


if __name__ == "__main__":
    main()
