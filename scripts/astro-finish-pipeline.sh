#!/bin/bash
# Finish Bond Astro go pipeline (MCP-aware).
set -uo pipefail
cd "$(dirname "$0")/.."
LOG="scripts/astro-pipeline.log"
exec >>"$LOG" 2>&1
echo ""
echo "=== $(date -u +%Y-%m-%dT%H:%M:%SZ) astro-finish-pipeline ==="

python3 scripts/astro-write-summary.py

if python3 -c "from scripts.astro_mcp import ping; import sys; sys.exit(0 if ping() else 1)"; then
  PYTHONUNBUFFERED=1 python3 scripts/astro-sync-remaining.py || true
  echo "=== prune all stores ==="
  ./scripts/astro-prune-all-stores.sh || true
  echo "=== tier-1 second pass ==="
  python3 scripts/astro-tier1-second-pass.py || true
  python3 scripts/astro-competitor-scan.py || true
else
  echo "warn: MCP offline — skipped sync/prune/tier1"
fi

python3 scripts/astro-write-summary.py
echo "=== DONE $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
