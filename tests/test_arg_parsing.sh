#!/usr/bin/env bash
# Tests for parse_args() in ottercache, invoked as a real subprocess so the
# script's own `main "$@"` entry point (guarded, still runs for real CLI
# calls) is exercised exactly as a user would experience it.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
OTTERCACHE="$ROOT_DIR/ottercache"

source "$SCRIPT_DIR/lib/assert.sh"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

run() {
    # run <out-var> <err-var> <exit-var> -- args...
    local out_file err_file
    out_file=$(mktemp) err_file=$(mktemp)
    "$OTTERCACHE" "$@" >"$out_file" 2>"$err_file"
    local rc=$?
    RUN_STDOUT=$(cat "$out_file")
    RUN_STDERR=$(cat "$err_file")
    RUN_EXIT=$rc
    rm -f "$out_file" "$err_file"
}

# ── no arguments ──────────────────────────────────────────────────────────────
run
assert_eq "0" "$RUN_EXIT" "no arguments exits 0"
assert_contains "$RUN_STDOUT" "USAGE" "no arguments prints usage to stdout"

# ── --help / -h ───────────────────────────────────────────────────────────────
run --help
assert_eq "0" "$RUN_EXIT" "--help exits 0"
assert_contains "$RUN_STDOUT" "USAGE" "--help prints usage to stdout"

run -h
assert_eq "0" "$RUN_EXIT" "-h exits 0"

# ── missing required flags ───────────────────────────────────────────────────
run --output-dir "$TMP_DIR/out"
assert_eq "1" "$RUN_EXIT" "missing --gog-dir exits 1"
assert_contains "$RUN_STDERR" "--gog-dir is required" "missing --gog-dir reports the correct error"

run --gog-dir "$TMP_DIR"
assert_eq "1" "$RUN_EXIT" "missing --output-dir exits 1"
assert_contains "$RUN_STDERR" "--output-dir is required" "missing --output-dir reports the correct error"

# ── --gog-dir must exist ─────────────────────────────────────────────────────
run --gog-dir "$TMP_DIR/does-not-exist" --output-dir "$TMP_DIR/out"
assert_eq "1" "$RUN_EXIT" "nonexistent --gog-dir exits 1"
assert_contains "$RUN_STDERR" "GOG directory not found" "nonexistent --gog-dir reports the correct error"

# ── unknown flag ──────────────────────────────────────────────────────────────
run --gog-dir "$TMP_DIR" --output-dir "$TMP_DIR/out" --totally-bogus-flag
assert_eq "1" "$RUN_EXIT" "unknown flag exits 1"
assert_contains "$RUN_STDERR" "Unknown argument: --totally-bogus-flag" "unknown flag is named in the error"

# ── --prune-anyway without --prune-old just warns (doesn't hard-fail parsing) ─
# Note: we only assert on the warning text here, not on the overall process
# exit code — that also depends on check_dependencies() (e.g. whether
# python3-yaml is installed on the host), which is out of scope for this
# argument-parsing test.
run --gog-dir "$TMP_DIR" --output-dir "$TMP_DIR/out2" --prune-anyway --dry-run
assert_contains "$RUN_STDERR" "--prune-anyway has no effect without --prune-old" \
    "--prune-anyway without --prune-old warns instead of hard-failing"

report_results "test_arg_parsing"
