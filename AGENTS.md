# AGENTS.md

## Project overview

OtterCache is a single Bash script (`ottercache`) that backs up Lutris installer
scripts and their referenced resources for locally-owned GOG games, so the
games can be installed and run fully offline. It scans a GOG library
downloaded via LGOGDownloader, looks each game up on the `lutris.net` API,
downloads the installer script plus any deeplink resources (patches, tools,
config files), and rewrites the script to use local `file://` URIs instead of
remote HTTP URLs.

See `README.md` for user-facing docs (installation, CLI usage, output layout,
offline install workflow). Read it before making behavioral changes — it is
the source of truth for documented flags and output structure.

## Repo layout

- `ottercache` — the entire application: a single Bash script (`set -uo
  pipefail`, no `set -e`). There is no build step or package manifest.
- `tests/` — the automated test suite (plain Bash, no framework). See
  "Testing changes" below.
- `README.md` — user documentation.
- `LICENSE` — GPLv2.

There is no separate Python file on disk: a Python helper script is generated
at runtime by `_write_helper_python()` (a heredoc inside `ottercache`) and
written to a temp file (`$HELPER_PY`, via `mktemp`), then invoked through the
`py()` / `py_tracked()` wrappers. If you need to change Python-side logic
(YAML parsing/generation, JSON handling, slug/name matching), edit the
heredoc inside `_write_helper_python()` in `ottercache`, not a separate file.

## Script structure

`ottercache` is organized into clearly banner-commented sections
(`# ── Section name ──`), roughly in this order:

1. Constants, colors, logging helpers (`log_info`, `log_ok`, `log_warn`,
   `log_error`, `log_skip`, `log_dryrun`, `print_header`, `print_section`)
2. Global state (`declare -A GAMES=()`, arrays for broken links, errors,
   skipped/duplicate games, etc.)
3. `_write_helper_python()` — the embedded Python helper
4. `py()` / `py_tracked()` — wrappers to invoke the helper
5. CLI: `print_usage`, `parse_args`
6. Setup: `setup_output_dirs`, `acquire_lock` / `release_lock` (flock-based),
   `start_logging`, `setup_helper_python`, `cleanup` (registered via `trap
   cleanup EXIT`), `check_dependencies`
7. String/HTTP helpers: `normalize_key`, `to_safe_name`, `http_get`,
   `check_url_status`, `is_http_success`
8. Game detection: `extract_gog_id_from_filename`,
   `extract_game_name_from_filename`, `detect_games` (priority: `product_*.json`
   → installer filenames → subdirectory names; dedupes by normalized title and
   by Lutris slug)
9. Core workflow: `process_game`, `prune_old_installer_dirs`,
   `localize_all_installers`
10. Reporting: `write_report`, `print_summary`
11. `main()` — orchestrates the whole run; the script ends with a source
    guard, `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then main "$@"; fi`, so
    that `tests/` can `source ottercache` to unit-test individual functions
    without triggering a real run. Preserve this guard — don't replace it
    with an unconditional `main "$@"`.

## Conventions

- Bash strict-ish mode: `set -uo pipefail` (deliberately no `set -e` — the
  script handles errors explicitly via return codes and counters like
  `HELPER_ERROR_COUNT`, so don't add `set -e`).
- All logging goes to stderr (`>&2`) so stdout stays clean for any value
  returned via command substitution.
- Use the existing `log_*` helpers for all user-facing output instead of raw
  `echo`.
- Locking: `acquire_lock` takes an exclusive `flock` on
  `<output_dir>/reports/.ottercache.lock` using the `{LOCK_FD}>file` bash 4.1+
  syntax specifically to avoid `eval`/double-expansion issues — preserve that
  pattern if you touch locking code.
- Respect `$DRY_RUN` and `$QUIET` throughout: dry-run must never write files
  (other than a temp stderr-capture log), and quiet mode suppresses info/skip
  logs via `suppress_info_in_quiet_mode` function-overriding.
- Two YAML files are produced per installer: `<slug>.yaml` (original, remote
  URLs) and `<slug>_offline.yaml` (rewritten, local `file://` URIs). Keep both
  in sync with any change to script/YAML generation.

## Dependencies

Runtime: `curl`, `python3` (3.6+), `python3-yaml` (PyYAML — required, not
optional, since YAML generation follows the Lutris spec), `flock`
(util-linux), GNU coreutils, `bash` 4+. `check_dependencies()` verifies these
at startup — update it if you add a new dependency.

## Testing changes

There is a small automated test suite under `tests/`, plain Bash with no
external framework (bats/shellcheck are not assumed to be installed):

```bash
./tests/run_tests.sh
```

Structure:

- `tests/lib/assert.sh` — minimal assertion helpers (`assert_eq`,
  `assert_success`, `assert_failure`, `assert_contains`, `assert_file_exists`,
  …) plus `report_results`, which prints a per-file pass/fail summary and
  returns non-zero on any failure. **Do not name a helper `print_summary`** —
  that collides with `ottercache`'s own `print_summary()` once a test file
  sources the script, silently replacing it.
- `tests/test_bash_string_helpers.sh` — sources `ottercache` (safe thanks to
  the source guard) and unit-tests pure string helpers (`normalize_key`,
  `to_safe_name`, `is_http_success`, `make_dir_name`,
  `extract_game_name_from_filename`).
- `tests/test_arg_parsing.sh` — invokes `ottercache` as a real subprocess and
  asserts exit codes / stderr for `parse_args()` (missing required flags,
  unknown flags, `--help`, `--prune-anyway` without `--prune-old`, …).
- `tests/test_game_detection.sh` — fixture-based tests for
  `detect_games()`'s documented priority order (`product_*.json` >
  installer filenames > subdirectory names) and dedup-by-normalized-title
  behavior. Runs `detect_games` in a subshell since it calls `exit 1` when
  zero games are found.
- `tests/test_dry_run.sh` — verifies `--dry-run` never writes files (calls
  `setup_output_dirs`/`acquire_lock`/`detect_games` directly rather than
  through the full CLI, since `check_dependencies()` would otherwise fail on
  any host without PyYAML installed — unrelated to what dry-run itself
  guarantees).
- `tests/test_python_helper.sh` — extracts the embedded Python helper via
  `_write_helper_python()` into a temp file and exercises its `cmd_*`
  commands as subprocesses against fixtures in `tests/fixtures/`.
  `save_installer_yaml`/`localize_yaml` tests self-skip (print `SKIP`, don't
  fail) when `python3 -c "import yaml"` fails, since PyYAML is not always
  present in every dev/CI environment.
- `run_tests.sh` runs every `tests/test_*.sh`, aggregates counts, and exits
  non-zero if anything failed.

Network-dependent functions (`http_get`, `check_url_status`,
`resolve_slug_by_name`, `resolve_game_slug`, `fetch_installer_data`,
`download_resource(s)`) are intentionally **not** covered by this suite — no
`curl` mocking yet. For end-to-end validation involving the real `lutris.net`
API:

```bash
./ottercache --gog-dir <path-to-a-small-GOG-library> --output-dir <tmp-dir> --dry-run
```

Dry-run exercises game detection, API lookups, and reporting without writing
files. For a full run, use a small/test `--output-dir` and check the
generated `reports/summary_*.txt` and `run_*.log` under it. Use `--api-delay`
to avoid hammering `lutris.net` during iterative testing.

## Notes for agents

- This is a single ~1500+ line script; when editing, use `grep -n` to jump to
  the relevant `# ── Section ──` banner rather than reading the whole file.
- After editing `ottercache`, run `./tests/run_tests.sh` — it's fast, network-
  free, and catches embedded-Python syntax errors (see `_write_helper_python`)
  that `bash -n ottercache` cannot, since the Python heredoc is opaque to bash.
- Do not fetch or hardcode credentials — the script only talks to the public
  `lutris.net` API and the user's local filesystem.
- Concurrency is intentionally restrictive (single instance per
  `--output-dir`); don't remove the lock without understanding why it's there
  (see comment block at the top of `ottercache`).
