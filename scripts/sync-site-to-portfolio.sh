#!/usr/bin/env bash
# Copy Bond marketing site (docs/) to jackwallner.com portfolio repo.
#
#   ./scripts/sync-site-to-portfolio.sh
#   ./scripts/sync-site-to-portfolio.sh /path/to/portfolio

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORTFOLIO="${1:-$HOME/portfolio}"
DEST="$PORTFOLIO/docs/bond"

if [[ ! -d "$PORTFOLIO/docs" ]]; then
  echo "Portfolio repo not found at $PORTFOLIO" >&2
  exit 1
fi

mkdir -p "$DEST"
# The public site is HTML/CSS/assets only — never ship internal markdown
# (ASO notes, triage, review prompts). Excluding all *.md keeps working
# notes from leaking onto jackwallner.com/bond/.
rsync -a --delete --delete-excluded \
  --exclude '.DS_Store' \
  --exclude '*.md' \
  "$ROOT/docs/" "$DEST/"

echo "Synced Bond site → $DEST"
echo "Commit and push portfolio main to publish at https://jackwallner.com/bond/"
