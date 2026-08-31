# OtterCache

[![License: GPL v2](https://img.shields.io/badge/License-GPL%20v2-blue.svg)](https://github.com/rixxxxx/ottercache/blob/main/LICENSE)
[![Shell: Bash](https://img.shields.io/badge/shell-bash-4EAA25?logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Platform: Linux](https://img.shields.io/badge/platform-Linux-FCC624?logo=linux&logoColor=black)](https://kernel.org)
[![Lutris](https://img.shields.io/badge/Lutris-compatible-FF6600?logo=lutris&logoColor=white)](https://lutris.net)
[![LGOGDownloader](https://img.shields.io/badge/LGOGDownloader-3.18.279b883-informational)](https://github.com/Sude-/lgogdownloader)
[![GOG](https://img.shields.io/badge/GOG-DRM--free-86328A?logo=gog.com&logoColor=white)](https://www.gog.com)

Cache your Lutris installer scripts and all referenced resources locally — so your GOG games run fully offline, no internet required, ever.

## Motivation

GOG sells DRM-free games, but getting them to run on Linux still requires the right configuration: DOSBox settings, Wine prefixes, ScummVM game IDs, patches, and more. Lutris maintains a community database of installer scripts that handle all of this automatically.

The problem: Lutris fetches those scripts on demand from `lutris.net`. If you want to play offline — on a travel laptop, in a cabin, or simply without depending on an external service — you need those scripts locally.

`OtterCache` bridges that gap. It scans your locally downloaded GOG library, looks up every game on `lutris.net`, and saves the installer scripts along with all referenced resources (patches, configuration files, helper binaries) to disk.

## How it works

```
LGOGDownloader          OtterCache                          Lutris (offline)
──────────────    →     ────────────────────────────────    ────────────────
Downloads your          1. Fetches installer scripts        Installs & runs
GOG library to          2. Downloads deeplink resources     your games using
~/GOG-Backup/           3. Rewrites scripts to use          local scripts and
                           local file:// URIs               local resources
```

## Prerequisites

### 1. Lutris

Lutris is the game manager that uses the installer scripts fetched by this tool.

```bash
# Ubuntu / Debian
sudo apt install lutris

# Fedora
sudo dnf install lutris

# Arch
sudo pacman -S lutris
```

Or download the latest version from [https://lutris.net/downloads](https://lutris.net/downloads).

> After installation, open Lutris at least once so it sets up its directory structure before you import any scripts.

### 2. LGOGDownloader

Used to download your GOG library. Tested with **version 3.18.279b883**.

```
https://github.com/Sude-/lgogdownloader.git
```

Run the following to download your full library:

```bash
lgogdownloader \
  --download \
  --directory ~/GOG-Backup/ \
  --platform all \
  --language all \
  --include all \
  --retries 3 \
  --threads 1 \
  --report ~/GOG-Backup/download-report.log \
  --check-free-space true \
  --no-fast-status-check \
  --automatic-xml-creation \
  --xml-directory ~/GOG-Backup/lgogdownloader-gog-xml \
  --limit-rate 0 \
  --save-serials \
  --save-game-details-json \
  --save-product-json \
  --save-logo \
  --save-icon \
  --save-changelogs \
  --include-hidden-products \
  --progress-interval 1000
```

> **Important:** `--save-product-json` is required. `ottercache` relies on the generated `product_*.json` files as its primary game detection source. Without them, game names are guessed from installer filenames, which is less reliable.

### 3. Runtime dependencies

| Dependency | Install |
|---|---|
| `curl` | `sudo apt install curl` |
| `python3` | `sudo apt install python3` |
| `python3-yaml` | `sudo apt install python3-yaml` (required — YAML generation follows the Lutris spec; `check_dependencies()` refuses to start without it) |

## Installation

```bash
git clone https://github.com/rixxxxx/ottercache.git
cd ottercache
chmod +x ottercache.sh
```

## Usage

```
ottercache.sh --gog-dir <path> --output-dir <path> [OPTIONS]
```

### Required arguments

| Argument | Description |
|---|---|
| `-g`, `--gog-dir <path>` | Directory containing your downloaded GOG library |
| `-o`, `--output-dir <path>` | Target directory for scripts and resources |

### Options

| Option | Description |
|---|---|
| `-d`, `--dry-run` | Show what would be done without writing any files |
| `-f`, `--force` | Overwrite existing files |
| `-q`, `--quiet` | Suppress all output except errors and the final summary |
| `--no-resources` | Fetch installer scripts only, skip deeplink downloads |
| `--api-delay <sec>` | Pause between API requests (default: `1`) |
| `-O`, `--slug-overrides <path>` | JSON file mapping GOG titles to Lutris slugs (see [Slug resolution](#slug-resolution)) |
| `-h`, `--help` | Show help |

### Examples

**Dry run — preview what would be fetched:**
```bash
./ottercache.sh \
  --gog-dir ~/GOG-Backup \
  --output-dir ~/OtterCache \
  --dry-run
```

**Full run:**
```bash
./ottercache.sh \
  --gog-dir ~/GOG-Backup \
  --output-dir ~/OtterCache
```

**Scripts only, no resource downloads:**
```bash
./ottercache.sh \
  --gog-dir ~/GOG-Backup \
  --output-dir ~/OtterCache \
  --no-resources
```

**Re-run after a partial failure, overwriting existing files:**
```bash
./ottercache.sh \
  --gog-dir ~/GOG-Backup \
  --output-dir ~/OtterCache \
  --force
```

## Output structure

```
~/OtterCache/
├── fallout-gog_2024-04-27_wine_published/
│   ├── fallout-gog.json                # Raw API response
│   ├── fallout-gog.yaml                # Original Lutris installer script
│   ├── fallout-gog_offline.yaml        # Rewritten for offline use ✓
│   └── cnc-ddraw.zip                   # Deeplink resource (local)
├── dungeon-keeper-gog-keeperfx_2026-04-19_wine_published/
│   ├── dungeon-keeper-gog-keeperfx.json
│   ├── dungeon-keeper-gog-keeperfx.yaml
│   ├── dungeon-keeper-gog-keeperfx_offline.yaml
│   └── keeperfx_1_3_2_complete.7z
└── reports/
    ├── run_2026-04-28_23-26.log
    └── summary_2026-04-28_23-26.txt
```

Each installer folder contains two YAML files:

| File | Description |
|---|---|
| `<slug>.yaml` | Original script with remote HTTP URLs |
| `<slug>_offline.yaml` | Rewritten script with local `file://` URIs — **use this one** |

## Offline installation workflow

Once `ottercache` has completed, install a game fully offline:

1. Open Lutris
2. Click **+** → **Install a game from a local script**
3. Select the `*_offline.yaml` from the corresponding installer folder
4. When prompted for the GOG installer file, point Lutris to the matching `setup_*.exe` or `*.sh` in your `~/GOG-Backup/` directory

> All deeplink resources (patches, tools, configuration files) are loaded from
> local disk via `file://` URIs — no internet connection required.

## Game detection

`ottercache` detects games from your GOG library using three sources, in order of priority:

1. **`product_*.json` files** — exact titles from GOG metadata (most reliable)
2. **Installer filenames** — parsed from `setup_*.exe` and `*.sh` files
3. **Subdirectory names** — last resort fallback

Games are deduplicated at two levels: by normalized title (case-insensitive) and by Lutris slug, so no game is processed twice even if it appears under different names across sources.

## Slug resolution

GOG product titles and Lutris slugs often don't match textually. `ottercache` resolves a slug for each detected game through, in order:

1. **Direct slug candidates** — the title is transformed into a handful of slug-shaped guesses (dropping `(YYYY)`, subtitles, trademark symbols, edition suffixes like "Definitive Edition", and swapping roman/arabic numerals or `&`/`and`), and each is tried directly against `games/<slug>/installers`. A match is only accepted if the returned game name has enough token overlap with the GOG title (≥ 60%) — this rejects generic slugs like `star-wars` silently swallowing a specific title like *Star Wars: Rebel Assault 1*.
2. **Name search fallback** — if no direct candidate matches, the title (and a year-stripped variant) is searched via `games?search=`. Exact slug/name matches win; if none exist, the best token-overlap match is used, but only if it also clears the 60% threshold. An ambiguous search with no confident match is reported as "not found" rather than guessed.
3. **Manual overrides** (`--slug-overrides <path>`) — checked *before* steps 1–2. Point it at a JSON file mapping normalized GOG titles to Lutris slugs:

   ```json
   {
     "beneath a steel sky": "beneath-a-steel-sky",
     "the witcher 3 wild hunt goty edition": "the-witcher-3-wild-hunt"
   }
   ```

   Keys must be normalized the same way `ottercache` normalizes titles internally: lowercased, whitespace collapsed. Use this for titles where the GOG name and Lutris slug have no meaningful textual relationship the automatic heuristics could ever bridge.

If a game still can't be resolved, it's listed under "Skipped games" in the run summary with the reason (not found / API error) — add an override entry for it and re-run.

## Reports

Every run produces a summary in `<output-dir>/reports/` containing:

- Total games detected and installers saved
- Skipped games (not found on `lutris.net` or no installer available)
- Broken links (404, timeout, etc.) with full URLs
- Download errors

## Testing

`ottercache` ships a small, framework-free test suite under `tests/` that
checks the behavior documented in this README (CLI flags, dry-run never
writing files, game-detection priority/dedup rules, etc.) plus the embedded
Python helper's individual commands, using local fixtures — no network
access or `lutris.net` account required.

```bash
./tests/run_tests.sh
```

Everything runs against `curl`-free fixtures except two YAML-related checks,
which are skipped automatically (not failed) if `python3-yaml` isn't
installed on the host.

## Known limitations

- **Lutris coverage:** Not every GOG game has a community installer on `lutris.net`. Skipped games are listed in the summary.
- **Broken deeplinks:** Some installer scripts reference files that have since moved or been deleted. These are flagged in the report.
- **Rate limiting:** `lutris.net` may throttle requests. Increase `--api-delay` if you see frequent API errors.
- **Online required for fetching:** `ottercache` itself requires internet access to query `lutris.net`. The resulting scripts and resources work fully offline.

## License

This project is licensed under the [GNU General Public License v2.0](https://github.com/rixxxxx/ottercache/blob/main/LICENSE).

```
OtterCache – Cache Lutris scripts & resources for offline GOG gaming
Copyright (C) 2026  rixxxxx

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.
```
