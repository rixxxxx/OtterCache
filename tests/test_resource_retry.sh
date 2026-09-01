#!/usr/bin/env bash
# Tests for the transient-error retry logic and the "re-run backfills
# missing resources instead of skipping the whole cached installer" fix.
# No network involved — is_retryable_http_code() is a pure classifier, and
# installer_has_missing_resources() is exercised against local fixture
# files, not curl.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

source "$SCRIPT_DIR/lib/assert.sh"

# Guarded main() does not run on source.
source "$ROOT_DIR/ottercache"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# ── is_retryable_http_code ───────────────────────────────────────────────────
for code in 000 429 500 502 503 504 599; do
    assert_success "is_retryable_http_code treats $code as retryable" \
        is_retryable_http_code "$code"
done

for code in 200 301 302 400 401 403 404 410; do
    assert_failure "is_retryable_http_code treats $code as permanent" \
        is_retryable_http_code "$code"
done

# ── installer_has_missing_resources ──────────────────────────────────────────
HELPER_PY="$TMP_DIR/helper.py"
_write_helper_python > "$HELPER_PY"
PY_ERROR_LOG="$TMP_DIR/py_err.log"
: > "$PY_ERROR_LOG"

data_file="$TMP_DIR/installers.json"
cat > "$data_file" <<'EOF'
{
  "installers": [
    {
      "slug": "final-doom-gog-dosbox",
      "script": {
        "files": [
          {"tool": "https://example.com/innoextract-1.8-linux.tar.xz"}
        ]
      }
    }
  ]
}
EOF

inst_dir="$TMP_DIR/final-doom-gog_2024-04-03_dosbox_published"
mkdir -p "$inst_dir"

assert_success "installer_has_missing_resources detects a missing resource file" \
    installer_has_missing_resources "$data_file" "final-doom-gog-dosbox" "$inst_dir" "false"

: > "$inst_dir/innoextract-1.8-linux.tar.xz"
assert_failure "installer_has_missing_resources reports complete once the file exists" \
    installer_has_missing_resources "$data_file" "final-doom-gog-dosbox" "$inst_dir" "false"

rm -f "$inst_dir/innoextract-1.8-linux.tar.xz"
assert_failure "installer_has_missing_resources always reports complete when --no-resources is set" \
    installer_has_missing_resources "$data_file" "final-doom-gog-dosbox" "$inst_dir" "true"

# ── py() exit-code tracking / HELPER_ERROR_COUNT ─────────────────────────────
# py_tracked() used to exist for this but was never called anywhere, so
# HELPER_ERROR_COUNT stayed permanently 0 even when real Python failures
# occurred. Verify py() itself now tracks genuine helper failures (exit >=2)
# while leaving boolean-protocol commands' legitimate false answers (exit 1)
# uncounted -- that split is what makes unconditional tracking safe.
HELPER_ERROR_COUNT=0
py badcommand >/dev/null 2>&1
assert_eq "1" "$HELPER_ERROR_COUNT" \
    "py() counts an unknown-command failure (exit 2) toward HELPER_ERROR_COUNT"

HELPER_ERROR_COUNT=0
py has_game_id "$TMP_DIR/does-not-exist.json" >/dev/null 2>&1
assert_eq "0" "$HELPER_ERROR_COUNT" \
    "py() does not count a boolean-protocol command's legitimate false answer (exit 1)"

# ── installer_has_missing_resources surfaces real py() failures ─────────────
# Previously a Python crash while extracting URLs (e.g. a missing/corrupt
# data_file) was silently indistinguishable from "this installer legitimately
# has zero resources" -- neither logged nor counted. Verify it's now visible
# on both fronts.
HELPER_ERROR_COUNT=0
: > "$PY_ERROR_LOG"
broken_data_file="$TMP_DIR/does-not-exist.json"
assert_failure "installer_has_missing_resources treats an extraction failure as 'nothing missing' rather than crashing" \
    installer_has_missing_resources "$broken_data_file" "final-doom-gog-dosbox" "$inst_dir" "false"
assert_eq "1" "$HELPER_ERROR_COUNT" \
    "...but still increments HELPER_ERROR_COUNT so the failure isn't silent"
assert_contains "$(cat "$PY_ERROR_LOG")" "PY_ERROR extract_urls" \
    "...and logs the underlying Python error to PY_ERROR_LOG"

# ── human_size ────────────────────────────────────────────────────────────
assert_eq "9.0GB" "$(human_size 9563648000)" \
    "human_size formats a large (GB-scale) byte count via numfmt"
assert_eq "500B" "$(human_size 500)" \
    "human_size formats a sub-KB byte count"

report_results "test_resource_retry"
