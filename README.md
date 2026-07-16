# Shiftly

> Formerly **Shifty**. See [Migrating from Shifty](#migrating-from-shifty) if you had an older install.

Shiftly keeps a dedicated **Shifts** calendar in Apple Calendar in sync with your work schedule: repeating rules, one-off swaps, leave ranges, and optional import from a CSV history file. Everything runs locally on macOS.

You can drive it from the **SwiftUI app** (single window) or from the **AppleScript menu**; both read and write the same files under `data/`.

Roadmap (schedule + pay visualization + Markdown work log, bidirectional calendar sync): see [docs/PLAN.md](docs/PLAN.md).

## Requirements

- macOS 13 or later (Swift app target)
- Calendar permission for Automation when using scripts or anything that talks to Calendar
- Python 3 (for helper scripts invoked by the app and AppleScript)

## Project root (`SHIFTLY_ROOT`)

All tools need a single **repository root** (the folder that contains `data/` and `scripts/`).

| How you run | How the root is found |
|-------------|------------------------|
| **Environment** | Prefer **`SHIFTLY_ROOT`**. Legacy **`SHIFTY_ROOT`** and **`SHIFTFLOW_ROOT`** are still accepted. |
| **AppleScript** | `osascript /path/to/scripts/main.applescript` (or `sync.applescript`): parent of `scripts/` is used (`path to me` → `dirname` twice). |
| **Python** | `scripts/*.py` use `SHIFTLY_ROOT` / legacy names, else `Path(__file__).resolve().parent.parent`. |
| **Swift app** | `SHIFTLY_ROOT` or legacy names, else walk upward from the executable (e.g. `swift run` → `.build/...`) or from the source file until `data/config.json` or `data/config.example.json` exists. |

Subprocesses spawned by the app and AppleScript set `SHIFTLY_ROOT` **and** the legacy names to the same path so embedded scripts keep working.

**LaunchAgent:** see `launchd/com.shiftly.sync.plist`. Replace every **`/CHANGE_ME/Shiftly`** with your install path.

## First-time setup

1. Create `data/config.json` (the whole `data/` directory is gitignored):

   ```json
   {
     "config_version": 1,
     "calendar_name": "Shifts",
     "event_title": "Work Schedule",
     "default_start_time": "10:00",
     "default_end_time": "18:30",
     "history_csv": "History.csv",
     "setup_completed": false,
     "rules": []
   }
   ```

2. Keep `setup_completed` as `false` if you want the AppleScript setup wizard on first `main.applescript` run.

3. Optionally place **`History.csv`** at the repository root (or set `history_csv` in config). The sync script imports it once and leaves a marker at `data/meta.history_imported`.

`config.json` includes **`config_version`** (currently `1`). Older files without it are treated as version 1; the Swift app may write `config_version` when you save the schedule.

## Swift app (recommended)

Single window: sync status, weekly schedule + effective date, swap/leave overrides (collapsible list), **Work history**, **Sync Now**, and **Open Calendar**.

```bash
cd ShiftlyApp
swift run
```

The built executable is **`ShiftlyApp`**.

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
| LaunchAgent with `SHIFTLY_SYNC_MODE=next_month` (legacy `SHIFTY_SYNC_MODE` / `SHIFTFLOW_SYNC_MODE`) | **Next full calendar month** |

Only events tagged for Shiftly (e.g. `[SF_SYNC]` in the script logic) are replaced in that window; history import is one-time.

## Work history (logic)

`scripts/work_history.py` prints JSON: each past day (on or before today) that appears in either the **planned** schedule (rules + swaps + leave) or **History.csv** (`Name` column as `YYYY-MM-DD`). **`ordinal`** is 1-based in chronological order. The Swift UI shows **Day N**, **ISO date**, and a localized weekday.

## Data files

| Path | Role |
|------|------|
| `data/config.json` | `config_version`, calendar name, title, times, `rules`, `setup_completed`, optional `history_csv` |
| `data/swaps.json` | Date swaps applied when generating shifts |
| `data/leave.json` | Leave ranges |
| `data/meta.json` | Last sync time/status (written by sync) |
| `data/logs/sync.log` | Sync log from AppleScript |

Schemas: [docs/DATA_AND_API.md](docs/DATA_AND_API.md).

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/main.applescript` | Grouped GUI menu and first-run setup flow |
| `scripts/sync.applescript` | Sync engine (Calendar read/write, history import) |
| `scripts/schedule_core.py` | Shared planning + work-history logic for Python |
| `scripts/work_history.py` | JSON list of past work days (used by the Swift app) |
| `scripts/report.py` | Weekly/monthly hours summary |
| `scripts/apply_setup.py` | Setup helper: merge stdin JSON into `config.json` |
| `scripts/needs_setup.py` | Exit code indicates whether setup wizard should run |

Supporting libraries live alongside as `scripts/*.applescript` fragments included by the main scripts.

## Tests

```bash
python3 scripts/test_schedule_core.py -v
```

## Scheduled sync (LaunchAgent)

1. Copy `launchd/com.shiftly.sync.plist` to `~/Library/LaunchAgents/` (e.g. same filename).
2. Replace every **`/CHANGE_ME/Shiftly`** with your install path; align `SHIFTLY_ROOT` (and the legacy variables) with that root.
3. If you previously used **`com.shifty.sync`** or **`com.shiftflow.sync`**, unload them first (see [Migrating from Shifty](#migrating-from-shifty)).
4. Load:

   ```bash
   launchctl load ~/Library/LaunchAgents/com.shiftly.sync.plist
   ```

Default schedule: **day 28 at 00:00**, `SHIFTLY_SYNC_MODE=next_month`, `RunAtLoad` false.

## Export AppleScript as an app

1. Open **Script Editor**, open `scripts/main.applescript`.
2. **File → Export…**, format **Application**, save e.g. as **`Shiftly.app`**.
3. Grant Automation access to Calendar when prompted.

If `path to me` does not resolve as expected for your exported app, set **`SHIFTLY_ROOT`** in the environment.

## Migrating from Shifty

Your data and synced calendar events are untouched by the rename; only names change.

1. **Environment variable:** switch to `SHIFTLY_ROOT`. Old `SHIFTY_ROOT` / `SHIFTFLOW_ROOT` still work.
2. **LaunchAgent:** unload the old job and install the new one:

   ```bash
   launchctl unload ~/Library/LaunchAgents/com.shifty.sync.plist 2>/dev/null
   launchctl unload ~/Library/LaunchAgents/com.shiftflow.sync.plist 2>/dev/null
   rm -f ~/Library/LaunchAgents/com.shifty.sync.plist ~/Library/LaunchAgents/com.shiftflow.sync.plist
   ```

   Then follow [Scheduled sync](#scheduled-sync-launchagent) with `com.shiftly.sync.plist`.
3. **Built executable:** now `ShiftlyApp` (was `ShiftyApp`); the Swift package folder is `ShiftlyApp/`.
4. **Git remote:** the GitHub repository is now `TN019/shiftly` (GitHub redirects the old URL).

## License

See `LICENSE` in the repository root.
