#!/usr/bin/env python3
import argparse
import datetime as dt
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from schedule_core import (
    history_dates_in_range,
    month_end,
    planned_dates,
    read_json,
    repo_root,
    resolve_history_path,
)


def parse_hhmm(value: str) -> tuple[int, int]:
    hh, mm = value.split(":")
    return int(hh), int(mm)


def shift_hours(start: str, end: str) -> float:
    sh, sm = parse_hhmm(start)
    eh, em = parse_hhmm(end)
    a = sh * 60 + sm
    b = eh * 60 + em
    if b < a:
        b += 24 * 60
    return (b - a) / 60.0


def resolve_range(period: str) -> tuple[dt.date, dt.date]:
    today = dt.date.today()
    if period == "week":
        start = today - dt.timedelta(days=today.weekday())
        end = start + dt.timedelta(days=6)
    elif period == "month":
        start = dt.date(today.year, today.month, 1)
        end = month_end(today)
    else:
        start = today
        end = today
    return start, end


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--period", choices=["week", "month"], default="week")
    args = parser.parse_args()

    root = repo_root()
    cfg = read_json(root / "data/config.json", {})
    swaps = read_json(root / "data/swaps.json", [])
    leave = read_json(root / "data/leave.json", [])

    start, end = resolve_range(args.period)
    planned = planned_dates(cfg, swaps, leave, start, end)
    history_path = resolve_history_path(root, cfg)
    history = history_dates_in_range(history_path, start, end)
    combined = sorted(planned | history)

    hours_each = shift_hours(cfg.get("default_start_time", "10:00"), cfg.get("default_end_time", "18:30"))
    total_hours = len(combined) * hours_each

    title = "Weekly" if args.period == "week" else "Monthly"
    lines = [
        f"{title} hours report",
        f"Range: {start.isoformat()} -> {end.isoformat()}",
        f"Shifts: {len(combined)}",
        f"Hours per shift: {hours_each:.2f}",
        f"Total hours: {total_hours:.2f}",
        "",
        "Dates:",
    ]
    for d in combined[:40]:
        lines.append(f"- {d.isoformat()} ({d.strftime('%a')})")
    if len(combined) > 40:
        lines.append(f"... and {len(combined) - 40} more")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
