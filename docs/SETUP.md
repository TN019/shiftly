# Shiftly — Setup & Technical Reference

> Product overview: [README](../README.md) · 中文：[README.zh-Hans](../README.zh-Hans.md)
> Formerly **Shifty**. See [Migrating from Shifty](#migrating-from-shifty) if you had an older install.

This document covers installation details, project-root resolution, the
AppleScript backup menu, scheduled sync, data files, and migration notes.

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

**First run:** the app asks for a **storage folder** and provisions the standard layout under it — `app/data` (the data root), `app/meetings`, `logs`, `notes` — writing the absolute paths into `config.json`; a folder that already is a data root (its `data/config.json` exists) is adopted as is. Each location can be relocated later from **Settings → Storage**: a change *moves* the existing content and leaves nothing behind. Set the weekly schedule, press **Sync Now** — macOS asks for Calendar access on the first sync. The chosen folder is remembered; the `SHIFTLY_ROOT` environment variable still wins when set.

The Python helper scripts are bundled into the app, so no repo checkout is needed at the data folder (a `scripts/` directory at the data root takes precedence when present).

**Desktop widgets:** `build_app.sh` also compiles a WidgetKit extension into `Contents/PlugIns/ShiftlyWidgets.appex` with plain `swiftc` — no Xcode. Three things make a hand-built appex loadable: the **`com.apple.security.app-sandbox` entitlement** (WidgetKit refuses unsandboxed extensions), `CFBundleSupportedPlatforms = [MacOSX]`, and linking with **`-e _NSExtensionMain`** (a plain Swift `@main` entry dies with "Unrecognized extension type"). The app feeds the widgets by writing a snapshot JSON into the `group.com.shiftly.app` container and calling `WidgetCenter.reloadAllTimelines()`. Add the widgets via right-click on the desktop → Edit Widgets → search "Shiftly"; the chips deep-link back through the `shiftly://` URL scheme (`start-work`, `meetings`, `new-note`, `open`).

**Meetings / Scripto:** recordings land in `<meetings_dir>/dd-mm-yy | hh-mm/dd-mm-yy.mp4` (AAC). On macOS 15+ a recording captures the **microphone and the Mac's system audio** (Core Audio process tap), so both sides of an online meeting (DingTalk, Zoom, Tencent Meeting, …) are recorded even with headphones on — the first recording triggers a *System Audio Recording* privacy prompt (separate from Microphone); declining it degrades recordings to mic-only. While recording, a hidden `.dd-mm-yy.system.m4a` side-track sits next to the mic file and is mixed in when the recording stops. Transcribe / Translate run [Scripto](https://github.com/TN019/scripto) headlessly via `uv run scripto-cli run <audio> --format srt [--translate --target zh|en]`; point **Settings → Meetings → Scripto folder** at your Scripto checkout (the folder with `pyproject.toml`), or press **Install automatically** — it clones Scripto next to the Shiftly checkout when the app runs from one, otherwise into `~/Library/Application Support/Shiftly/scripto`, pre-warms the Python env with `uv sync`, and sets the folder (needs `git`; transcription needs `uv`; an existing checkout at the destination is adopted, not re-cloned). Subtitles (`*.en.srt`, `*.zh.srt`) land next to each recording and play back inside the app with cue highlighting. Translation additionally needs a local Ollama, per Scripto's own requirements.

**Scheduled sync:** the in-app **Auto-sync** setting (hourly / 6h / 12h / daily) syncs while the app is open. Pair it with **Settings → Auto-launch** so Shiftly starts itself — either **At login** (SMAppService) or **On workdays** at a chosen time. The workday option installs a per-user LaunchAgent (`~/Library/LaunchAgents/com.shiftly.workday-launch.plist`) with one `StartCalendarInterval` entry per scheduled workday; it's regenerated automatically whenever the work schedule changes. For syncing without the app running at all, use the [launchd template](#scheduled-sync-launchagent) instead — the two approaches are independent.

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

Sync is bidirectional and incremental: only events recorded in `data/sync_state.json` are touched, and edits made in Calendar are read back into the data files (see [SYNC_DESIGN.md](SYNC_DESIGN.md)). Events from the old AppleScript engine (tagged `[SF_SYNC]` in notes) are claimed on first sync.

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

Schemas: [DATA_AND_API.md](DATA_AND_API.md).

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

See the repository [README](../README.md#license) — PolyForm Noncommercial 1.0.0.
