#!/bin/bash
# Incremental Astro sync: drop researched junk, add curated keywords.
set -euo pipefail
cd "$(dirname "$0")/.."
export PYTHONPATH="$(pwd)/scripts:${PYTHONPATH:-}"

python3 scripts/astro-build-keywords.py

python3 <<'PY'
import json
import time
from pathlib import Path

from astro_curate_keywords import REMOVED_PHRASES
from astro_mcp import add_keywords, remove_keywords

mcp = "http://127.0.0.1:8089/mcp"
app_id = "101"
store = "us"

print(f"==> Removing {len(REMOVED_PHRASES)} low-intent keywords (batches of 8)...")
for i in range(0, len(REMOVED_PHRASES), 8):
    batch = REMOVED_PHRASES[i : i + 8]
    try:
        remove_keywords(mcp, app_id, store, batch)
        print(f"    batch {i//8 + 1}: {len(batch)} ok")
    except Exception as e:
        print(f"    batch {i//8 + 1}: {e}")
    time.sleep(0.8)

data = json.loads(Path("scripts/astro-keywords-us.json").read_text())
new_kws = data["keywords"]
print(f"==> Adding {len(new_kws)} curated keywords...")
result = add_keywords(mcp, app_id, store, new_kws)
for i, batch in enumerate(result["batches"]):
    if isinstance(batch, dict):
        print(f"    batch {i+1}: added={batch.get('added')} skipped={batch.get('skipped')}")
print("==> Done. Refresh keyword metrics in Astro UI (get_app_keywords can be slow via MCP).")
PY
