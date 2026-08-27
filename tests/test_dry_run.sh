#!/usr/bin/env bash
# Verifies the AGENTS.md requirement: "--dry-run must never write files (other
# than a temp stderr-capture log)". Exercises the actual dry-run-guarded
# functions (setup_output_dirs, acquire_lock, detect_games) directly rather
# than through the full CLI, since check_dependencies() would otherwise fail
# in any environment without python3-yaml installed — unrelated to what
# dry-run itself is supposed to guarantee.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

source "$SCRIPT_DIR/lib/assert.sh"

# Guarded main() does not run on source.
source "$ROOT_DIR/ottercache"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

GOG_DIR="$TMP_DIR/gog"
mkdir -p "$GOG_DIR"
cat > "$GOG_DIR/product_1.json" <<'JSON'
{"title": "Dry Run Game"}
JSON

OUTPUT_DIR="$TMP_DIR/output"   # deliberately does not exist yet
DRY_RUN=true

HELPER_PY="$TMP_DIR/helper.py"
_write_helper_python > "$HELPER_PY"

setup_output_dirs
assert_failure "setup_output_dirs does not create the output directory in dry-run" \
    test -e "$OUTPUT_DIR"

acquire_lock
assert_failure "acquire_lock does not create a lock file in dry-run" \
    test -e "$OUTPUT_DIR/reports/.ottercache.lock"

declare -A GAMES=()
detect_games >/dev/null 2>&1
assert_failure "detect_games does not write detected_games.txt in dry-run" \
    test -e "$DIR_REPORTS/detected_games.txt"

assert_failure "output directory tree still does not exist after a full dry-run detection pass" \
    test -e "$OUTPUT_DIR"

report_results "test_dry_run"
