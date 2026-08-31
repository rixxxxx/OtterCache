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

NO_RESOURCES=false
assert_success "installer_has_missing_resources detects a missing resource file" \
    installer_has_missing_resources "$data_file" "final-doom-gog-dosbox" "$inst_dir"

: > "$inst_dir/innoextract-1.8-linux.tar.xz"
assert_failure "installer_has_missing_resources reports complete once the file exists" \
    installer_has_missing_resources "$data_file" "final-doom-gog-dosbox" "$inst_dir"

rm -f "$inst_dir/innoextract-1.8-linux.tar.xz"
NO_RESOURCES=true
assert_failure "installer_has_missing_resources always reports complete when --no-resources is set" \
    installer_has_missing_resources "$data_file" "final-doom-gog-dosbox" "$inst_dir"
NO_RESOURCES=false

# ── human_size ────────────────────────────────────────────────────────────
assert_eq "9.0GB" "$(human_size 9563648000)" \
    "human_size formats a large (GB-scale) byte count via numfmt"
assert_eq "500B" "$(human_size 500)" \
    "human_size formats a sub-KB byte count"

report_results "test_resource_retry"
