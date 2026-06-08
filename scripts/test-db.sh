#!/usr/bin/env bash
# Apply the Bond migrations + run the RPC lifecycle tests against a throwaway
# local Postgres cluster. No Docker, no Supabase platform, no network.
#
# Requires postgresql@17:  brew install postgresql@17
# Override the binary dir with PGBIN=/path/to/pg/bin if needed.
set -euo pipefail

PGBIN="${PGBIN:-/opt/homebrew/opt/postgresql@17/bin}"
[[ -x "$PGBIN/initdb" ]] || PGBIN="$(dirname "$(command -v initdb)")"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIG="$ROOT/supabase/migrations"
TESTS="$ROOT/supabase/tests"

TMP="$(mktemp -d)"
DATADIR="$TMP/pgdata"
SOCK="$TMP/sock"; mkdir -p "$SOCK"
PORT=54399
DB=bond_test

cleanup() {
  "$PGBIN/pg_ctl" -D "$DATADIR" -m immediate stop >/dev/null 2>&1 || true
  rm -rf "$TMP"
}
trap cleanup EXIT

echo "==> initdb"
"$PGBIN/initdb" -D "$DATADIR" -U postgres --auth=trust >/dev/null

echo "==> start postgres (port $PORT)"
"$PGBIN/pg_ctl" -D "$DATADIR" -o "-p $PORT -k $SOCK -c listen_addresses=''" -w start >/dev/null

PSQL=( "$PGBIN/psql" -v ON_ERROR_STOP=1 -h "$SOCK" -p "$PORT" -U postgres -X -q )
"${PSQL[@]}" -d postgres -c "create database $DB" >/dev/null

echo "==> apply stubs + migrations"
"${PSQL[@]}" -d "$DB" -f "$TESTS/_stubs.sql" >/dev/null
for f in "$MIG"/*.sql; do
  echo "    - $(basename "$f")"
  "${PSQL[@]}" -d "$DB" -f "$f" >/dev/null
done

echo "==> run tests"
"${PSQL[@]}" -d "$DB" -f "$TESTS/rpc_lifecycle_test.sql"

echo "==> OK"
