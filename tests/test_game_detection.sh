#!/usr/bin/env bash
# Tests for game detection (detect_games / scan_product_json_files /
# scan_installer_files / scan_subdirectories) and its documented priority
# order + dedup rules (AGENTS.md: product_*.json > installer filenames >
# subdirectory names; dedup by normalized title).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

source "$SCRIPT_DIR/lib/assert.sh"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# Guarded main() does not run on source.
source "$ROOT_DIR/ottercache"

HELPER_PY="$TMP_DIR/helper.py"
_write_helper_python > "$HELPER_PY"
PY_ERROR_LOG="$TMP_DIR/py_errors.log"
: > "$PY_ERROR_LOG"
DRY_RUN=true

# Runs detect_games() against $1 (a fixture GOG_DIR) in a subshell (detect_games
# calls `exit 1` when zero games are found, which must not kill the test
# runner) and prints every detected game's display name, one per line.
detect_in() {
    (
        GOG_DIR="$1"
        declare -A GAMES=()
        detect_games >/dev/null 2>&1
        printf '%s\n' "${GAMES[@]}"
    )
}

# ── priority: product_*.json wins over filenames and directory names ───────
prio_dir="$TMP_DIR/priority"
mkdir -p "$prio_dir/Some Other Dir Name"
cat > "$prio_dir/product_123.json" <<'JSON'
{"title": "Priority Game"}
JSON
: > "$prio_dir/setup_totally_different_name_999999999.exe"

prio_out=$(detect_in "$prio_dir")
assert_eq "Priority Game" "$prio_out" \
    "product_*.json is used exclusively when present (filenames/dirs ignored)"

# ── fallback: installer filename scan when no product_*.json exists ────────
# Filenames without an embedded 9-10 digit GOG id are skipped entirely by
# scan_installer_files (extract_gog_id_from_filename returns empty ->
# `continue`), so the fixture must include one, like real lgogdownloader output.
fname_dir="$TMP_DIR/fname_fallback"
mkdir -p "$fname_dir"
: > "$fname_dir/setup_fallout_2_1234567890.exe"

fname_out=$(detect_in "$fname_dir")
assert_eq "fallout 2" "$fname_out" \
    "falls back to installer filename parsing when no product_*.json exists"

# ── fallback: subdirectory name scan as last resort ─────────────────────────
dir_dir="$TMP_DIR/dir_fallback"
mkdir -p "$dir_dir/Some_Game_GOTY"

dir_out=$(detect_in "$dir_dir")
assert_eq "Some Game" "$dir_out" \
    "falls back to subdirectory names when no product_*.json or installer files exist"

# ── dedup: same title (different case/whitespace) across product_*.json files ─
dedup_dir="$TMP_DIR/dedup"
mkdir -p "$dedup_dir"
cat > "$dedup_dir/product_1.json" <<'JSON'
{"title": "Half-Life 2"}
JSON
cat > "$dedup_dir/product_2.json" <<'JSON'
{"title": "  half-life 2  "}
JSON

dedup_out=$(detect_in "$dedup_dir")
dedup_count=$(echo "$dedup_out" | grep -c .)
assert_eq "1" "$dedup_count" \
    "games with the same normalized title are deduplicated across product_*.json files"

report_results "test_game_detection"
