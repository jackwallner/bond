#!/usr/bin/env python3
"""Build _summary.json from per-store plan files (91 stores)."""
from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "scripts" / "astro-keywords-by-store"
STORES_JSON = ROOT / "scripts" / "astro-stores-2026.json"
CONFIG = ROOT / "scripts" / ".astro-app.json"

stores = json.loads(STORES_JSON.read_text())["stores"]
app_id = json.loads(CONFIG.read_text()).get("appId", "101") if CONFIG.exists() else "101"

summary_stores: dict = {}
for entry in stores:
    code = entry["code"]
    p = OUT / f"{code}.json"
    if not p.exists():
        summary_stores[code] = {"missing": True}
        continue
    data = json.loads(p.read_text())
    summary_stores[code] = {
        "locales": data.get("locales", []),
        "planned": data.get("keywordCount", 0),
        "keywords": data.get("keywordCount", 0),
    }

summary = {
    "syncedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "appId": app_id,
    "storeCount": len(stores),
    "stores": summary_stores,
}
(OUT / "_summary.json").write_text(json.dumps(summary, indent=2) + "\n")
print(f"Wrote _summary.json — {len(summary_stores)} stores, storeCount={summary['storeCount']}")
