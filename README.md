# lutris-gog-fetch

Back up Lutris installer scripts and deeplink resources for your entire GOG library — so you can install and run your games fully offline via [Lutris](https://lutris.net).

## Motivation

GOG sells DRM-free games, but getting them to run on Linux still requires the right configuration: DOSBox settings, Wine prefixes, ScummVM game IDs, patches, and more. Lutris maintains a community database of installer scripts that handle all of this automatically.

The problem: Lutris fetches those scripts on demand from `lutris.net`. If you want to play offline — on a travel laptop, in a cabin, or simply without depending on an external service — you need those scripts locally.

`lutris-gog-fetch` bridges that gap. It scans your locally downloaded GOG library, looks up every game on `lutris.net`, and saves the installer scripts along with all referenced resources (patches, configuration files, helper binaries) to disk.

## How it works

```
LGOGDownloader          lutris-gog-fetch          Lutris (offline)
──────────────    →     ────────────────    →     ────────────────
Downloads your          Fetches installer          Installs & runs
GOG library to          scripts + resources        your games from
~/GOG-Backup/           from lutris.net            local scripts
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

> **Important:** `--save-product-json` is required. `lutris-gog-fetch` relies on the generated `product_*.json` files as its primary game detection source. Without them, game names are guessed from installer filenames, which is less reliable.

### 3. Runtime dependencies

| Dependency | Install |
|---|---|
| `curl` | `sudo apt install curl` |
| `python3` | `sudo apt install python3` |
| `python3-yaml` | `sudo apt install python3-yaml` (optional, fallback active) |

## Installation

```bash
git clone https://github.com/youruser/lutris-gog-fetch.git
cd lutris-gog-fetch
chmod +x lutris-gog-fetch.sh
```

## Usage

```
lutris-gog-fetch --gog-dir <path> --output-dir <path> [OPTIONS]
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
| `-h`, `--help` | Show help |

### Examples

**Dry run — preview what would be fetched:**
```bash
./lutris-gog-fetch.sh \
  --gog-dir ~/GOG-Backup \
  --output-dir ~/Lutris-Scripts \
  --dry-run
```

**Full run:**
```bash
./lutris-gog-fetch.sh \
  --gog-dir ~/GOG-Backup \
  --output-dir ~/Lutris-Scripts
```

**Scripts only, no resource downloads:**
```bash
./lutris-gog-fetch.sh \
  --gog-dir ~/GOG-Backup \
  --output-dir ~/Lutris-Scripts \
  --no-resources
```

**Re-run after a partial failure, overwriting existing files:**
```bash
./lutris-gog-fetch.sh \
  --gog-dir ~/GOG-Backup \
  --output-dir ~/Lutris-Scripts \
  --force
```

## Output structure

```
~/Lutris-Scripts/
├── fallout-gog_2024-04-27_wine_published/
│   ├── fallout-gog.json          # Raw API response
│   ├── fallout-gog.yaml          # Lutris installer script (YAML)
│   └── cnc-ddraw.zip             # Deeplink resource
├── dungeon-keeper-gog-keeperfx_2026-04-19_wine_published/
│   ├── dungeon-keeper-gog-keeperfx.json
│   ├── dungeon-keeper-gog-keeperfx.yaml
│   └── keeperfx_1_3_2_complete.7z
└── reports/
    ├── run_2026-04-28_23-26.log  # Full run log
    └── summary_2026-04-28_23-26.txt
```

Each installer gets its own folder named `<slug>_<updated>_<runner>_<status>`. Multiple installers per game (e.g. vanilla GOG, modded, DOSBox, Wine) are saved separately.

## Game detection

`lutris-gog-fetch` detects games from your GOG library using three sources, in order of priority:

1. **`product_*.json` files** — exact titles from GOG metadata (most reliable)
2. **Installer filenames** — parsed from `setup_*.exe` and `*.sh` files
3. **Subdirectory names** — last resort fallback

Games are deduplicated at two levels: by normalized title (case-insensitive) and by Lutris slug, so no game is processed twice even if it appears under different names across sources.

## Reports

Every run produces a summary in `<output-dir>/reports/` containing:

- Total games detected and installers saved
- Skipped games (not found on `lutris.net` or no installer available)
- Broken links (404, timeout, etc.) with full URLs
- Download errors

## Known limitations

- **Lutris coverage:** Not every GOG game has a community installer on `lutris.net`. Skipped games are listed in the summary.
- **Broken deeplinks:** Some installer scripts reference files that have since moved or been deleted. These are flagged in the report.
- **Rate limiting:** `lutris.net` may throttle requests. Increase `--api-delay` if you see frequent API errors.
- **Online required for fetching:** `lutris-gog-fetch` itself requires internet access to query `lutris.net`. The resulting scripts and resources work fully offline.

## License

MIT
