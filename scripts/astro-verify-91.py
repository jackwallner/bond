#!/usr/bin/env python3
"""Quick verify all 91 Astro stores have >=MIN keywords; update _summary.json."""
from __future__ import annotations

import json
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
MIN = 20
TIMEOUT = 40


def main() -> None:
    if not ping(MCP):
        raise SystemExit("MCP offline")
    app_id = str(json.loads(CONFIG.read_text())["appId"])
    stores = json.loads(STORES_JSON.read_text())["stores"]
    summary_stores: dict = {}
    ok = 0
    low: list[str] = []
    for i, entry in enumerate(stores, 1):
        code = entry["code"]
        plan = OUT / f"{code}.json"
        planned = json.loads(plan.read_text()).get("keywordCount", 0) if plan.exists() else 0
        locales = json.loads(plan.read_text()).get("locales", []) if plan.exists() else entry.get("fallbackLocales", [])
        n = None
        for attempt in range(3):
            try:
                kws = call(MCP, "get_app_keywords", {"appId": app_id, "store": code}, timeout=TIMEOUT)
                n = len(kws) if isinstance(kws, list) else 0
                break
            except Exception as e:
                err = e
                if attempt < 2:
                    time.sleep(2 * (attempt + 1))
        if n is None:
            print(f"[{i}/91] {code}: err {err}")
        is_ok = n is not None and n >= MIN
        if is_ok:
            ok += 1
            print(f"[{i}/91] {code}: {n} ok")
        else:
            low.append(code)
            print(f"[{i}/91] {code}: {n} LOW")
        summary_stores[code] = {"locales": locales, "planned": planned, "inAstro": n, "ok": is_ok}
        time.sleep(0.15)
    summary = {
        "syncedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "appId": app_id,
        "storeCount": 91,
        "okCount": ok,
        "minKeywords": MIN,
        "stores": summary_stores,
    }
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "_summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(f"\n{ok}/91 ok. Low: {low or 'none'}")
    raise SystemExit(0 if ok == 91 else 1)


if __name__ == "__main__":
    main()
