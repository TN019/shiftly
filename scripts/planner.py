#!/usr/bin/env python3
"""Single planner entry point for AppleScript (and any other caller).

All schedule semantics live in schedule_core.py; this file is only argument
parsing and I/O. User input arrives as arguments — never interpolated into
code — so quotes/semicolons in input cannot execute anything.

Commands:
  shifts --start YYYY-MM-DD --end YYYY-MM-DD   lines: "YYYY-MM-DD|rule|day"
                                               (date|source|shift_type; source
                                               is rule or swap)
  sync-range                                   two lines: first, last
                                               (mode from SHIFTLY_SYNC_MODE
                                               or legacy names)
  config-summary                               four lines: calendar_name,
                                               event_title, start, end
  add-swap --from-date D --to-date D           append to data/swaps.json
  add-leave --start D --end D                  append to data/leave.json
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from schedule_core import holiday_dates, planned_days_detailed, read_json, repo_root, sync_range


def parse_iso(value: str) -> dt.date:
    try:
        return dt.date.fromisoformat(value)
    except ValueError:
        raise argparse.ArgumentTypeError(f"invalid date {value!r}, expected YYYY-MM-DD")


def load_overrides(root: Path) -> tuple[list, list]:
    swaps = read_json(root / "data/swaps.json", [])
    leave = read_json(root / "data/leave.json", [])
    return swaps, leave


def append_json_item(path: Path, item: dict) -> None:
    items = read_json(path, [])
    if not isinstance(items, list):
        raise ValueError(f"{path} does not contain a JSON array")
    items.append(item)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(items, indent=2) + "\n", encoding="utf-8")


def cmd_shifts(root: Path, args) -> None:
    cfg = read_json(root / "data/config.json", {})
    swaps, leave = load_overrides(root)
    holidays = holiday_dates(root)
    for day in planned_days_detailed(cfg, swaps, leave, args.start, args.end, holidays):
        print(f"{day['date'].isoformat()}|{day['source']}|{day['shift_type']}")


def cmd_sync_range(root: Path, _args) -> None:
    swaps, leave = load_overrides(root)
    mode = (
        os.environ.get("SHIFTLY_SYNC_MODE")
        or os.environ.get("SHIFTY_SYNC_MODE")  # legacy
        or os.environ.get("SHIFTFLOW_SYNC_MODE")  # legacy
        or ""
    )
    first, last = sync_range(swaps, leave, mode=mode)
    print(first.isoformat())
    print(last.isoformat())


def cmd_config_summary(root: Path, _args) -> None:
    cfg = read_json(root / "data/config.json", {})
    print(cfg.get("calendar_name", "Shifts"))
    print(cfg.get("event_title", "Work Schedule"))
    print(cfg.get("default_start_time", "10:00"))
    print(cfg.get("default_end_time", "18:30"))


def cmd_add_swap(root: Path, args) -> None:
    append_json_item(root / "data/swaps.json", {
        "from_date": args.from_date.isoformat(),
        "to_date": args.to_date.isoformat(),
    })


def cmd_add_leave(root: Path, args) -> None:
    append_json_item(root / "data/leave.json", {
        "start_date": args.start.isoformat(),
        "end_date": args.end.isoformat(),
    })


def main() -> None:
    parser = argparse.ArgumentParser(prog="planner.py")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("shifts")
    p.add_argument("--start", type=parse_iso, required=True)
    p.add_argument("--end", type=parse_iso, required=True)
    p.set_defaults(func=cmd_shifts)

    p = sub.add_parser("sync-range")
    p.set_defaults(func=cmd_sync_range)

    p = sub.add_parser("config-summary")
    p.set_defaults(func=cmd_config_summary)

    p = sub.add_parser("add-swap")
    p.add_argument("--from-date", type=parse_iso, required=True)
    p.add_argument("--to-date", type=parse_iso, required=True)
    p.set_defaults(func=cmd_add_swap)

    p = sub.add_parser("add-leave")
    p.add_argument("--start", type=parse_iso, required=True)
    p.add_argument("--end", type=parse_iso, required=True)
    p.set_defaults(func=cmd_add_leave)

    args = parser.parse_args()
    try:
        args.func(repo_root(), args)
    except Exception as e:  # clear message, non-zero exit, no traceback noise
        print(f"planner.py: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
