#!/usr/bin/env python3
"""Ensure Bond has keywords in Astro for all 91 stores (≥MIN keywords each)."""
from __future__ import annotations

import json
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from astro_mcp import call, ping

ROOT = Path(__file__).resolve().parent.parent
STORES_JSON = ROOT / "scripts" / "astro-stores-2026.json"
CONFIG = ROOT / "scripts" / ".astro-app.json"
OUT = ROOT / "scripts" / "astro-keywords-by-store"
MCP = "http://127.0.0.1:8089/mcp"
MIN_KEYWORDS = 20
GET_TIMEOUT = 50
MAX_PASSES = 4


def count_keywords(app_id: str, store: str) -> int | None:
    try:
        kws = call(MCP, "get_app_keywords", {"appId": app_id, "store": store}, timeout=GET_TIMEOUT)
        return len(kws) if isinstance(kws, list) else 0
    except Exception:
        return None


def sync_store(store: str) -> bool:
    r = subprocess.run(
        [sys.executable, str(ROOT / "scripts" / "astro-sync-all-stores.py"), "--store", store],
        cwd=str(ROOT),
    )
    return r.returncode == 0


def write_summary(app_id: str, counts: dict[str, int | None]) -> None:
    stores_meta = {s["code"]: s for s in json.loads(STORES_JSON.read_text())["stores"]}
    summary_stores: dict = {}
    ok = 0
    for code, entry in stores_meta.items():
        n = counts.get(code)
        plan_path = OUT / f"{code}.json"
        planned = 0
        locales: list[str] = entry.get("fallbackLocales", [])
        if plan_path.exists():
            data = json.loads(plan_path.read_text())
            planned = data.get("keywordCount", 0)
            locales = data.get("locales", locales)
        summary_stores[code] = {
            "locales": locales,
            "planned": planned,
            "inAstro": n,
            "ok": n is not None and n >= MIN_KEYWORDS,
        }
        if n is not None and n >= MIN_KEYWORDS:
            ok += 1
    summary = {
        "syncedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "appId": app_id,
        "storeCount": 91,
        "okCount": ok,
        "minKeywords": MIN_KEYWORDS,
        "stores": summary_stores,
    }
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "_summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(f"summary: {ok}/91 stores with >={MIN_KEYWORDS} keywords in Astro")


def main() -> None:
    if not ping(MCP):
        raise SystemExit("error: Astro MCP not reachable — open Astro app")

    app_id = str(json.loads(CONFIG.read_text())["appId"])
    stores = [s["code"] for s in json.loads(STORES_JSON.read_text())["stores"]]
    counts: dict[str, int | None] = {}

    for pass_num in range(1, MAX_PASSES + 1):
        print(f"\n=== pass {pass_num}/{MAX_PASSES} ===")
        need: list[str] = []
        for i, code in enumerate(stores, 1):
            n = count_keywords(app_id, code)
            counts[code] = n
            if n is None or n < MIN_KEYWORDS:
                need.append(code)
                print(f"[{i}/91] {code}: {n if n is not None else 'err'} — sync")
            else:
                print(f"[{i}/91] {code}: {n} ok")
            time.sleep(0.2)

        write_summary(app_id, counts)
        ok = sum(1 for c in stores if counts.get(c) is not None and counts[c] >= MIN_KEYWORDS)
        if ok == 91:
            print("\n91/91 complete")
            return

        print(f"\nSyncing {len(need)} store(s)...")
        for j, code in enumerate(need, 1):
            print(f"  [{j}/{len(need)}] {code}")
            for attempt in range(1, 6):
                if not ping(MCP):
                    time.sleep(5)
                if sync_store(code):
                    break
                time.sleep(attempt * 2)
            n = count_keywords(app_id, code)
            counts[code] = n
            time.sleep(1)

        write_summary(app_id, counts)
        ok = sum(1 for c in stores if counts.get(c) is not None and counts[c] >= MIN_KEYWORDS)
        print(f"After pass {pass_num}: {ok}/91")
        if ok == 91:
            print("\n91/91 complete")
            return

    ok = sum(1 for c in stores if counts.get(c) is not None and counts[c] >= MIN_KEYWORDS)
    low = [c for c in stores if counts.get(c) is None or counts[c] < MIN_KEYWORDS]
    print(f"\nStopped at {ok}/91. Still low: {low}")
    raise SystemExit(1 if ok < 91 else 0)


if __name__ == "__main__":
    main()
