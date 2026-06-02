#!/usr/bin/env python3
"""Sync only Astro stores below keyword threshold; write 91-store summary."""
from __future__ import annotations

import json
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from astro_mcp import call, ping

ROOT = Path(__file__).resolve().parent.parent
STORES_JSON = ROOT / "scripts" / "astro-stores-2026.json"
CONFIG = ROOT / "scripts" / ".astro-app.json"
THRESHOLD = 20
GET_TIMEOUT = 45


def main() -> None:
    if not ping():
        raise SystemExit("error: Astro MCP not reachable")

    app_id = str(json.loads(CONFIG.read_text())["appId"])
    stores = [s["code"] for s in json.loads(STORES_JSON.read_text())["stores"]]
    need: list[tuple[str, int]] = []

    for i, code in enumerate(stores, 1):
        try:
            kws = call(
                "http://127.0.0.1:8089/mcp",
                "get_app_keywords",
                {"appId": app_id, "store": code},
                timeout=GET_TIMEOUT,
            )
            n = len(kws) if isinstance(kws, list) else 0
        except Exception as e:
            print(f"[audit {i}/91] {code}: err ({e}) — will try sync")
            need.append((code, 0))
            continue
        if n < THRESHOLD:
            print(f"[audit {i}/91] {code}: {n} keywords — needs sync")
            need.append((code, n))
        else:
            print(f"[audit {i}/91] {code}: {n} ok")
        time.sleep(0.3)

    print(f"\nSyncing {len(need)} store(s)...")
    failed: list[str] = []
    for j, (code, had) in enumerate(need, 1):
        print(f"\n[{j}/{len(need)}] sync {code} (had {had})")
        ok = False
        for attempt in range(1, 6):
            r = subprocess.run(
                [sys.executable, str(ROOT / "scripts" / "astro-sync-all-stores.py"), "--store", code],
                cwd=str(ROOT),
            )
            if r.returncode == 0:
                ok = True
                break
            time.sleep(attempt * 2)
        if not ok:
            failed.append(code)
            print(f"FAILED {code}")

    subprocess.run([sys.executable, str(ROOT / "scripts" / "astro-write-summary.py")], check=True)
    print(f"Done. Failed: {failed or 'none'}")


if __name__ == "__main__":
    main()
