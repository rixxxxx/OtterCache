#!/usr/bin/env bash
# Unit tests for the pure bash string helpers in ottercache
# (normalize_key, to_safe_name, is_http_success, make_dir_name,
# extract_game_name_from_filename). No network, no filesystem writes.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

source "$SCRIPT_DIR/lib/assert.sh"

# Guarded by `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]` at the bottom of
# ottercache, so sourcing here only defines functions/globals — main() does
# not run.
source "$ROOT_DIR/ottercache"

# ── normalize_key ────────────────────────────────────────────────────────────
assert_eq "half life 2" "$(normalize_key '  Half  Life 2  ')" \
    "normalize_key lowercases, collapses whitespace and trims"
assert_eq "half life 2" "$(normalize_key 'HALF LIFE 2')" \
    "normalize_key is case-insensitive"

# ── to_safe_name ──────────────────────────────────────────────────────────────
assert_eq "star-wars-rebel-assault" "$(to_safe_name 'Star Wars: Rebel Assault!')" \
    "to_safe_name replaces non [a-z0-9._-] chars and collapses dashes"
assert_eq "baldur-s-gate-ii-enhanced" "$(to_safe_name "Baldur's Gate II -- Enhanced")" \
    "to_safe_name replaces apostrophes with dashes and collapses repeated dashes"

# ── is_http_success ──────────────────────────────────────────────────────────
assert_success "is_http_success accepts 200" is_http_success 200
assert_success "is_http_success accepts 206 (partial content)" is_http_success 206
assert_success "is_http_success accepts 301/302 redirects" is_http_success 301
assert_failure "is_http_success rejects 404" is_http_success 404
assert_failure "is_http_success rejects 500" is_http_success 500

# ── make_dir_name ─────────────────────────────────────────────────────────────
assert_eq "half-life-2_2023-01-01_wine_published" \
    "$(make_dir_name 'Half Life 2' '2023-01-01' 'Wine' 'Published')" \
    "make_dir_name joins slug/date/runner/status via to_safe_name"

# ── extract_game_name_from_filename ──────────────────────────────────────────
assert_eq "the witcher 3 wild hunt" \
    "$(extract_game_name_from_filename 'gog_the_witcher_3_wild_hunt_2.0.0.123.sh' '')" \
    "extract_game_name_from_filename strips gog_ prefix and version suffix"

assert_eq "fallout 2" \
    "$(extract_game_name_from_filename 'setup_fallout_2_1.02.exe' '')" \
    "extract_game_name_from_filename strips setup_ prefix, extension and trailing version digits"

# Known quirk: the gog_id-removal sed (`s/[_. -]*[[(]*${gog_id}[)]]*.*//`)
# requires a literal ')' right after the id to consume the id itself, so an
# id followed by "_(64bit)" (underscore, not paren) is not stripped. Asserting
# the actual current behavior here so a future fix is a visible test change,
# not a silent regression.
assert_eq "stardew valley 1207658930 (64bit)" \
    "$(extract_game_name_from_filename 'setup_stardew_valley_1207658930_(64bit)_1.5.6.exe' '1207658930')" \
    "extract_game_name_from_filename (documents current gog-id-in-filename quirk)"

report_results "test_bash_string_helpers"
