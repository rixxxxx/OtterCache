#!/usr/bin/env bash
# Runs every tests/test_*.sh file, aggregates PASS/FAIL counts, and exits
# non-zero if anything failed. No external test framework required.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

total_pass=0
total_fail=0
any_failed=0

for test_file in "$SCRIPT_DIR"/test_*.sh; do
    [[ -e "$test_file" ]] || continue
    name=$(basename "$test_file")
    echo "── $name ──"
    output=$(bash "$test_file")
    rc=$?
    echo "$output"
    summary_line=$(echo "$output" | tail -n 1)
    passed=$(echo "$summary_line" | grep -oE '[0-9]+ passed' | grep -oE '[0-9]+' || echo 0)
    failed=$(echo "$summary_line" | grep -oE '[0-9]+ failed' | grep -oE '[0-9]+' || echo 0)
    total_pass=$((total_pass + passed))
    total_fail=$((total_fail + failed))
    [[ "$rc" -ne 0 ]] && any_failed=1
    echo
done

echo "════════════════════════════════════════"
echo "TOTAL: $total_pass passed, $total_fail failed"

exit "$any_failed"
