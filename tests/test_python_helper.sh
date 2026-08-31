#!/usr/bin/env bash
# Tests for the cmd_* commands of the embedded Python helper
# (_write_helper_python() in ottercache). No network involved.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
FIXTURES="$SCRIPT_DIR/fixtures"

# shellcheck source=lib/assert.sh
source "$SCRIPT_DIR/lib/assert.sh"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# Extract the embedded Python helper without running main() (guarded by
# `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]` at the bottom of ottercache).
source "$ROOT_DIR/ottercache"
HELPER_PY="$TMP_DIR/helper.py"
_write_helper_python > "$HELPER_PY"

py() {
    python3 "$HELPER_PY" "$@"
}

# ── python syntax sanity ───────────────────────────────────────────────────
assert_success "embedded python helper parses without SyntaxError" \
    python3 -c "import ast; ast.parse(open('$HELPER_PY').read())"

# ── product_title ───────────────────────────────────────────────────────────
assert_eq "Half-Life 2" "$(py product_title "$FIXTURES/product_sample.json")" \
    "product_title reads the title field"

assert_eq "" "$(py product_title "$FIXTURES/product_null_title.json")" \
    "product_title returns empty string for null title (no crash)"

assert_eq "123" "$(py product_title "$FIXTURES/product_non_string_title.json")" \
    "product_title stringifies a non-string title (no crash)"

assert_success "product_title tolerates non-UTF-8 bytes in the file" \
    py product_title "$FIXTURES/product_invalid_utf8.json"

# ── slug_candidates (regression test for the reconstructed function) ───────
slug_out=$(py slug_candidates "Star Wars: Rebel Assault (1994)")
assert_contains "$slug_out" "star-wars-rebel-assault-1994" \
    "slug_candidates includes the full-title slug"
assert_contains "$slug_out" "star-wars" \
    "slug_candidates includes the subtitle-dropped fallback slug"

tm_out=$(py slug_candidates "Fallout Tactics™")
assert_contains "$tm_out" "fallout-tacticstm" \
    "slug_candidates emits the trademark-kept variant"
assert_contains "$tm_out" "fallout-tactics" \
    "slug_candidates emits the trademark-stripped variant"

roman_out=$(py slug_candidates "Torchlight II")
assert_contains "$roman_out" "torchlight-ii" \
    "slug_candidates keeps the roman-numeral slug as-is"
assert_contains "$roman_out" "torchlight-2" \
    "slug_candidates emits the arabic-numeral variant for a roman numeral"

ampersand_out=$(py slug_candidates "Dungeons & Dragons: Dark Alliance")
assert_contains "$ampersand_out" "dungeons-dragons-dark-alliance" \
    "slug_candidates emits the '&'-stripped variant"
assert_contains "$ampersand_out" "dungeons-and-dragons-dark-alliance" \
    "slug_candidates emits the '&'-spelled-out-as-'and' variant"

edition_out=$(py slug_candidates "The Witcher 3: Wild Hunt - Game of the Year Edition")
assert_contains "$edition_out" "the-witcher-3-wild-hunt" \
    "slug_candidates drops a trailing 'Game of the Year Edition' suffix"

# ── search_names ────────────────────────────────────────────────────────────
names_out=$(py search_names "Fallout (1997)")
assert_eq "2" "$(echo "$names_out" | grep -c .)" \
    "search_names dedupes to the two distinct name variants"
assert_contains "$names_out" "Fallout (1997)" "search_names keeps the full title"
assert_contains "$names_out" "Fallout" "search_names includes the year-dropped title"

# ── url_encode / url_to_filename / extract_gog_id ──────────────────────────
assert_eq "Half-Life%202" "$(py url_encode "Half-Life 2")" \
    "url_encode percent-encodes spaces"

assert_eq "patch.zip" "$(py url_to_filename "https://example.com/dir/patch.zip")" \
    "url_to_filename extracts the basename"

assert_eq "resource_unknown" "$(py url_to_filename "https://example.com/dir/")" \
    "url_to_filename falls back when there is no filename"

assert_eq "1207658930" "$(py extract_gog_id "setup_halflife2_1207658930_(64bit)_1.5.exe")" \
    "extract_gog_id extracts a 10-digit id from a filename"

assert_eq "" "$(py extract_gog_id "setup_halflife2.exe")" \
    "extract_gog_id prints nothing when no id is present"

# ── has_game_id ──────────────────────────────────────────────────────────────
assert_success "has_game_id succeeds when installers response has an id field" \
    py has_game_id "$FIXTURES/installers_sample.json"

echo '{"count": 0}' > "$TMP_DIR/no_id.json"
assert_failure "has_game_id fails when there is no id field" \
    py has_game_id "$TMP_DIR/no_id.json"

# ── find_slug_in_results ────────────────────────────────────────────────────
assert_eq "sample-game" \
    "$(py find_slug_in_results "Sample Game" "$FIXTURES/search_results_sample.json")" \
    "find_slug_in_results matches on exact slug"

assert_failure "find_slug_in_results rejects an ambiguous search with no confident match" \
    py find_slug_in_results "My Specific Game Name" "$FIXTURES/search_results_ambiguous.json"
assert_eq "" \
    "$(py find_slug_in_results "My Specific Game Name" "$FIXTURES/search_results_ambiguous.json" 2>/dev/null)" \
    "find_slug_in_results prints nothing for an ambiguous search (no results[0] guess)"

assert_eq "star-wars-rebel-assault-collection" \
    "$(py find_slug_in_results "Rebel Assault I & II" "$FIXTURES/search_results_fuzzy.json")" \
    "find_slug_in_results falls back to the best token-overlap match above threshold"

# ── verify_slug_match ────────────────────────────────────────────────────────
assert_success "verify_slug_match accepts a close name match" \
    py verify_slug_match "$FIXTURES/installers_sample.json" "Sample Game"

assert_failure "verify_slug_match rejects a generic slug swallowing a specific title" \
    py verify_slug_match "$FIXTURES/installers_generic_slug.json" "Star Wars Rebel Assault 1"

# ── override_get ─────────────────────────────────────────────────────────────
assert_eq "beneath-a-steel-sky" \
    "$(py override_get "$FIXTURES/slug_overrides_sample.json" "beneath a steel sky")" \
    "override_get returns the mapped slug for a known key"

assert_eq "" \
    "$(py override_get "$FIXTURES/slug_overrides_sample.json" "some other game")" \
    "override_get returns empty for an unmapped key"

assert_eq "" \
    "$(py override_get "$TMP_DIR/does-not-exist.json" "beneath a steel sky")" \
    "override_get returns empty (not an error) when the overrides file doesn't exist yet"

# ── parse_installers ─────────────────────────────────────────────────────────
installers_out=$(py parse_installers "$FIXTURES/installers_sample.json")
assert_contains "$installers_out" \
    "$(printf 'sample-game-wine\twine\t2024-01-01\tpublished')" \
    "parse_installers emits a TSV row for the published wine installer"
assert_contains "$installers_out" \
    "$(printf 'sample-game-dosbox\tdosbox\t2024-02-01\tunpublished')" \
    "parse_installers emits a TSV row for the unpublished dosbox installer"

# ── extract_urls ─────────────────────────────────────────────────────────────
urls_out=$(py extract_urls "$FIXTURES/installers_sample.json" "sample-game-wine")
assert_contains "$urls_out" "https://example.com/patch.zip" \
    "extract_urls finds the patch resource URL"
assert_contains "$urls_out" "https://example.com/tool.7z" \
    "extract_urls finds the tool resource URL"

# ── save_installer_json ──────────────────────────────────────────────────────
dest_dir="$TMP_DIR/save_json"
mkdir -p "$dest_dir"
py save_installer_json "$FIXTURES/installers_sample.json" "sample-game-wine" "$dest_dir"
assert_file_exists "$dest_dir/sample-game-wine.json" \
    "save_installer_json writes <slug>.json to the destination directory"

# ── save_installer_yaml / localize_yaml (require PyYAML) ───────────────────
if python3 -c "import yaml" >/dev/null 2>&1; then
    yaml_dest="$TMP_DIR/sample-game-wine.yaml"
    assert_success "save_installer_yaml writes a spec-compliant YAML file" \
        py save_installer_yaml "$FIXTURES/installers_sample.json" "sample-game-wine" "$yaml_dest"
    assert_file_exists "$yaml_dest" "save_installer_yaml output file exists"
    yaml_content=$(cat "$yaml_dest" 2>/dev/null || true)
    assert_contains "$yaml_content" "game_slug: sample-game" \
        "save_installer_yaml injects the required game_slug field"

    resource_dir="$TMP_DIR/resources"
    mkdir -p "$resource_dir"
    : > "$resource_dir/patch.zip"
    offline_yaml="$TMP_DIR/offline.yaml"
    patched_count=$(py localize_yaml "$FIXTURES/content_sample.yaml" "$resource_dir" "$offline_yaml")
    assert_eq "1" "$patched_count" \
        "localize_yaml patches exactly the one URL with a local resource on disk"
    offline_content=$(cat "$offline_yaml" 2>/dev/null || true)
    assert_contains "$offline_content" "file://" \
        "localize_yaml rewrites the matched URL to a file:// URI"
    assert_contains "$offline_content" "https://example.com/tool.7z" \
        "localize_yaml leaves URLs without a local resource untouched"
else
    _skip "save_installer_yaml (PyYAML not installed in this environment)"
    _skip "localize_yaml (PyYAML not installed in this environment)"
fi

report_results "test_python_helper"
