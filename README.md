# Shiftly

> Formerly **Shifty**. See [Migrating from Shifty](#migrating-from-shifty) if you had an older install.

Shiftly keeps a dedicated **Shifts** calendar in Apple Calendar in sync with your work schedule: repeating rules, one-off swaps, leave ranges, and optional import from a CSV history file. Everything runs locally on macOS.

You can drive it from the **SwiftUI app** (single window) or from the **AppleScript menu**; both read and write the same files under `data/`.

Roadmap (schedule + pay visualization + Markdown work log, bidirectional calendar sync): see [docs/PLAN.md](docs/PLAN.md).

## Requirements

- macOS 13 or later (Swift app target)
- Calendar access (EventKit): macOS prompts on the first sync from the app
- Python 3 (for helper scripts invoked by the app and AppleScript)

## Project root (`SHIFTLY_ROOT`)

All tools need a single **repository root** (the folder that contains `data/` and `scripts/`).

| How you run | How the root is found |
|-------------|------------------------|
| **Environment** | Prefer **`SHIFTLY_ROOT`**. Legacy **`SHIFTY_ROOT`** and **`SHIFTFLOW_ROOT`** are still accepted. |
| **AppleScript** | `osascript /path/to/scripts/main.applescript`: parent of `scripts/` is used (`path to me` → `dirname` twice). |
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

## Shiftly.app (recommended, no terminal)

Build a double-clickable app bundle (ad-hoc signed, local use):

```bash
scripts/build_app.sh          # → dist/Shiftly.app
```

Move `dist/Shiftly.app` to `/Applications` (or anywhere) and double-click.

**First run:** the app asks for a **data folder** (a starter `data/config.json` is created if the folder is empty; an existing Shiftly data folder is picked up as is). Set the weekly schedule, press **Sync Now** — macOS asks for Calendar access on the first sync. The chosen folder is remembered; the `SHIFTLY_ROOT` environment variable still wins when set.

The Python helper scripts are bundled into the app, so no repo checkout is needed at the data folder (a `scripts/` directory at the data root takes precedence when present).

**Scheduled sync:** the in-app **Auto-sync** setting (hourly / 6h / 12h / daily) syncs while the app is open; enable **Launch at login** so it resumes after a reboot. For syncing without the app running, use the [launchd template](#scheduled-sync-launchagent) instead — the two approaches are independent.

## Swift app from a checkout (development)

Single window: sync status, weekly schedule + effective date, swap/leave overrides (collapsible list), sync report with undo, **Work history**, **Sync Now**, and **Open Calendar**.

```bash
cd ShiftlyApp
swift run
```

The built executable is **`ShiftlyApp`**.

## AppleScript menu

Looping menu until **Exit**:

```bash
osascript scripts/main.applescript
```

Sections: **Schedule** (rules and hours), **Overrides** (swap/leave), **Sync**, **Reports** (calls `report.py`).

The menu's **Sync Now** runs the app binary headlessly (`Shiftly --sync`, same EventKit engine as the GUI); it looks for `dist/Shiftly.app`, `/Applications/Shiftly.app`, then a local `swift build` product. Direct sync without the menu:

```bash
/Applications/Shiftly.app/Contents/MacOS/Shiftly --sync
```

## How sync chooses a date range

| Trigger | Window |
|--------|--------|
| Manual (app / menu / `--sync`) | From **today** through the **last day of the current month** |
| With overrides | Extends to cover the latest `to_date` (swaps) or `end_date` (leave) in JSON |
| LaunchAgent with `SHIFTLY_SYNC_MODE=next_month` (legacy `SHIFTY_SYNC_MODE` / `SHIFTFLOW_SYNC_MODE`) | **Next full calendar month** |

Sync is bidirectional and incremental: only events recorded in `data/sync_state.json` are touched, and edits made in Calendar are read back into the data files (see [docs/SYNC_DESIGN.md](docs/SYNC_DESIGN.md)). Events from the old AppleScript engine (tagged `[SF_SYNC]` in notes) are claimed on first sync.

## Work history (logic)

`scripts/work_history.py` prints JSON: each past day (on or before today) that appears in either the **planned** schedule (rules + swaps + leave) or **History.csv** (`Name` column as `YYYY-MM-DD`). **`ordinal`** is 1-based in chronological order. The Swift UI shows **Day N**, **ISO date**, and a localized weekday.

## Data files

| Path | Role |
|------|------|
| `data/config.json` | `config_version`, calendar name, title, times, `rules`, `setup_completed`, optional `history_csv` |
| `data/swaps.json` | Date swaps applied when generating shifts |
| `data/leave.json` | Leave ranges |
| `data/meta.json` | Last sync time/status/error (written by sync) |
| `data/overrides.json` | Per-day time overrides read back from Calendar |
| `data/manual_shifts.json` | Shifts created directly in Calendar |
| `data/sync_state.json` | Event mapping (engine-private) |
| `data/last_sync_report.json` | Last sync summary (engine-private) |
| `data/readback_log.json` | Readback journal with undo flags (engine-private) |

Schemas: [docs/DATA_AND_API.md](docs/DATA_AND_API.md).

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/main.applescript` | Grouped GUI menu (backup entry point) |
| `scripts/planner.py` | CLI over the scheduling core (used by the app and the menu) |
| `scripts/schedule_core.py` | Shared planning + work-history logic for Python |
| `scripts/work_history.py` | JSON list of past work days (used by the Swift app) |
| `scripts/report.py` | Weekly/monthly hours summary |
| `scripts/apply_setup.py` | Setup helper: merge stdin JSON into `config.json` |
| `scripts/needs_setup.py` | Exit code indicates whether setup wizard should run |
| `scripts/build_app.sh` | Build `dist/Shiftly.app` |
| `scripts/test.sh` | Run the whole test suite |

## Tests

```bash
scripts/test.sh          # python + applescript syntax + swift build & test
```

## Scheduled sync (LaunchAgent)

The LaunchAgent runs `Shiftly --sync` headlessly — the same EventKit engine as the app. Grant Calendar access once by syncing from the app before loading the job.

1. Install `Shiftly.app` to `/Applications` (`scripts/build_app.sh`) and sync once from the UI.
2. Copy `launchd/com.shiftly.sync.plist` to `~/Library/LaunchAgents/`.
3. Replace **`/CHANGE_ME/ShiftlyData`** with your data folder (the one that contains `data/`).
4. Load:

   ```bash
   launchctl load ~/Library/LaunchAgents/com.shiftly.sync.plist
   ```

Default schedule: **day 28 at 00:00**, `SHIFTLY_SYNC_MODE=next_month`, `RunAtLoad` false.

## Migrating from Shifty

Your data and synced calendar events are untouched by the rename; only names change.

1. **Environment variable:** switch to `SHIFTLY_ROOT`. Old `SHIFTY_ROOT` / `SHIFTFLOW_ROOT` still work.
2. **LaunchAgent:** unload any old job and install the new one:

   ```bash
   launchctl unload ~/Library/LaunchAgents/com.shifty.sync.plist 2>/dev/null
   launchctl unload ~/Library/LaunchAgents/com.shiftflow.sync.plist 2>/dev/null
   rm -f ~/Library/LaunchAgents/com.shifty.sync.plist ~/Library/LaunchAgents/com.shiftflow.sync.plist
   ```

   Then follow [Scheduled sync](#scheduled-sync-launchagent) with `com.shiftly.sync.plist` (it now runs `Shiftly --sync` instead of the removed `sync.applescript`).
3. **Built executable:** now `ShiftlyApp` (was `ShiftyApp`); the Swift package folder is `ShiftlyApp/`.
4. **Git remote:** the GitHub repository is now `TN019/shiftly` (GitHub redirects the old URL).
5. **History.csv:** still feeds the work-history list, but is no longer imported into the calendar as events (that one-time import was part of the removed AppleScript engine). Previously imported events are left alone — they sit in the past, outside the sync window.

## License

See `LICENSE` in the repository root.
