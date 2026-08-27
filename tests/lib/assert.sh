#!/usr/bin/env bash
# Minimal, dependency-free assertion helpers for OtterCache's test suite.
# Sourced by each tests/test_*.sh file; counters are per-process.

TESTS_RUN=0
TESTS_FAILED=0

_pass() {
    TESTS_RUN=$((TESTS_RUN + 1))
    printf '  \033[0;32mPASS\033[0m %s\n' "$1"
}

_fail() {
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf '  \033[0;31mFAIL\033[0m %s\n' "$1" >&2
}

_skip() {
    printf '  \033[2mSKIP\033[0m %s\n' "$1"
}

assert_eq() {
    local expected="$1" actual="$2" desc="$3"
    if [[ "$expected" == "$actual" ]]; then
        _pass "$desc"
    else
        _fail "$desc — expected [$expected], got [$actual]"
    fi
}

assert_contains() {
    local haystack="$1" needle="$2" desc="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        _pass "$desc"
    else
        _fail "$desc — expected to find [$needle] in [$haystack]"
    fi
}

assert_success() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        _pass "$desc"
    else
        _fail "$desc — command failed: $*"
    fi
}

assert_failure() {
    local desc="$1"; shift
    if ! "$@" >/dev/null 2>&1; then
        _pass "$desc"
    else
        _fail "$desc — command unexpectedly succeeded: $*"
    fi
}

assert_file_exists() {
    local path="$1" desc="$2"
    if [[ -f "$path" ]]; then
        _pass "$desc"
    else
        _fail "$desc — file not found: $path"
    fi
}

assert_file_not_exists() {
    local path="$1" desc="$2"
    if [[ ! -f "$path" ]]; then
        _pass "$desc"
    else
        _fail "$desc — file unexpectedly exists: $path"
    fi
}

assert_dir_empty() {
    local path="$1" desc="$2"
    if [[ -z "$(find "$path" -mindepth 1 2>/dev/null)" ]]; then
        _pass "$desc"
    else
        _fail "$desc — directory not empty: $path"
    fi
}

# Prints "<name>: X passed, Y failed (of Z)" and returns non-zero if any failed.
# Named report_results (not print_summary) to avoid colliding with
# ottercache's own print_summary() function once a test file sources ottercache.
report_results() {
    local name="$1"
    printf '%s: %d passed, %d failed (of %d)\n' \
        "$name" "$((TESTS_RUN - TESTS_FAILED))" "$TESTS_FAILED" "$TESTS_RUN"
    [[ "$TESTS_FAILED" -eq 0 ]]
}
