#!/bin/bash
# Wait for Astro MCP, finish remaining stores, verify 91/91, prune, tier-1.
set -uo pipefail
cd "$(dirname "$0")/.."
LOG=scripts/astro-pipeline.log
REMAINING=(hu ro nz np iq cl cz)

exec >>"$LOG" 2>&1
echo ""
echo "=== $(date -u +%Y-%m-%dT%H:%M:%SZ) astro-finish-remaining ==="

until python3 -c "from scripts.astro_mcp import ping; import sys; sys.exit(0 if ping() else 1)"; do
  echo "waiting for Astro MCP..."
  sleep 15
done

for s in "${REMAINING[@]}"; do
  echo "sync $s"
  for attempt in 1 2 3 4 5; do
    PYTHONUNBUFFERED=1 python3 scripts/astro-sync-all-stores.py --store "$s" && break
    sleep $((attempt * 3))
  done
  sleep 1
done

until PYTHONUNBUFFERED=1 python3 scripts/astro-verify-91.py; do
  echo "verify failed — retrying low stores..."
  python3 - <<'PY'
import json, subprocess, sys
from pathlib import Path
s = json.load(open("scripts/astro-keywords-by-store/_summary.json"))
low = [c for c, v in s["stores"].items() if not v.get("ok")]
for code in low:
    subprocess.run([sys.executable, "scripts/astro-sync-all-stores.py", "--store", code])
PY
  sleep 5
done

echo "=== prune ==="
./scripts/astro-prune-all-stores.sh || true
echo "=== tier-1 ==="
python3 scripts/astro-tier1-second-pass.py || true
python3 scripts/astro-write-summary.py
echo "=== FINISHED $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
