# ShiftFlow

ShiftFlow keeps a dedicated **Shifts** calendar in Apple Calendar in sync with your work schedule: repeating rules, one-off swaps, leave ranges, and optional import from a CSV history file. Everything runs locally on macOS.

You can drive it from the **SwiftUI app** (single window) or from the **AppleScript menu**; both read and write the same files under `data/`.

## Requirements

- macOS 13 or later (Swift app target)
- Calendar permission for Automation when using scripts or anything that talks to Calendar

## First-time setup

1. Copy the template and edit as needed:

   ```bash
   cp data/config.example.json data/config.json
   ```

2. Set `setup_completed` to `false` if you want the AppleScript setup wizard on first `main.applescript` run; the Swift app expects a valid `config.json` at the paths below.

3. Optionally place **`History.csv`** at the repository root (or set `history_csv` in config). The sync script imports it once and leaves a marker at `data/meta.history_imported`.

**Repository layout note:** `ShiftFlowApp` uses a fixed `rootPath` in `Sources/ShiftFlowApp/main.swift`. If your clone is not at that path, change `rootPath` to your checkout (or symlink) before building the app. The AppleScript entry points resolve paths relative to the script location.

## Swift app (recommended)

Single window: sync status, weekly schedule + effective date, swap/leave overrides (with a collapsible current list), **Sync Now**, and **Open Calendar**.

```bash
cd ShiftFlowApp
swift run
```

To produce an app bundle, open the package in Xcode and archive, or add an app target as you prefer.

## AppleScript menu

Looping menu until **Exit**:

```bash
osascript scripts/main.applescript
```

Sections: **Schedule** (rules and hours), **Overrides** (swap/leave), **Sync**, **Reports** (calls `report.py`).

Direct sync without the menu:

```bash
osascript scripts/sync.applescript
```

## How sync chooses a date range

| Trigger | Window |
|--------|--------|
| Manual / menu / `sync.applescript` | From **today** through the **last day of the current month** |
| With overrides | Extends to cover the latest `to_date` (swaps) or `end_date` (leave) in JSON |
| LaunchAgent with `SHIFTFLOW_SYNC_MODE=next_month` | **Next full calendar month** |

Only events tagged for ShiftFlow (e.g. `[SF_SYNC]` in the script logic) are replaced in that window; history import is one-time.

## Data files

| Path | Role |
|------|------|
| `data/config.json` | Calendar name, event title, default times, `rules`, `setup_completed`, optional `history_csv` |
| `data/swaps.json` | Date swaps applied when generating shifts |
| `data/leave.json` | Leave ranges |
| `data/meta.json` | Last sync time/status (written by sync) |
| `data/logs/sync.log` | Sync log from AppleScript |
| `data/config.example.json` | Checked-in template for new installs |

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/main.applescript` | Grouped GUI menu and first-run setup flow |
| `scripts/sync.applescript` | Sync engine (Calendar read/write, history import) |
| `scripts/report.py` | Weekly/monthly hours summary |
| `scripts/apply_setup.py` | Setup helper: merge stdin JSON into `config.json` |
| `scripts/needs_setup.py` | Exit code indicates whether setup wizard should run |

Supporting libraries live alongside as `scripts/*.applescript` fragments included by the main scripts.

## Scheduled sync (LaunchAgent)

1. Copy `launchd/com.shiftflow.sync.plist` to `~/Library/LaunchAgents/`.
2. Edit **all** absolute paths inside the plist (`ProgramArguments`, `StandardOutPath`, `StandardErrorPath`) to match your machine and clone location.
3. Load:

   ```bash
   launchctl load ~/Library/LaunchAgents/com.shiftflow.sync.plist
   ```

Default schedule: **day 28 at 00:00**, `SHIFTFLOW_SYNC_MODE=next_month`, `RunAtLoad` false.

## Export AppleScript as an app

1. Open **Script Editor**, open `scripts/main.applescript`.
2. **File → Export…**, format **Application**, save e.g. as `ShiftFlow.app`.
3. Grant Automation access to Calendar when prompted.

## License

See `LICENSE` in the repository root.
