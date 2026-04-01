#!/usr/bin/env python3
import argparse
import csv
import datetime as dt
import json
from pathlib import Path


ROOT = Path("/Users/tn/Dev/Local/ShiftFlow")


def read_json(path: Path, default):
    if not path.exists():
        return default
    return json.loads(path.read_text())


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


def month_end(day: dt.date) -> dt.date:
    if day.month == 12:
        return dt.date(day.year + 1, 1, 1) - dt.timedelta(days=1)
    return dt.date(day.year, day.month + 1, 1) - dt.timedelta(days=1)


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


def planned_dates(cfg: dict, swaps: list, leave: list, start: dt.date, end: dt.date) -> set[dt.date]:
    wk = {"MO": 0, "TU": 1, "WE": 2, "TH": 3, "FR": 4, "SA": 5, "SU": 6}
    rules = sorted(cfg.get("rules", []), key=lambda r: r.get("effective_from", ""))

    def rule_for(day: dt.date):
        cur = None
        for r in rules:
            ef = r.get("effective_from")
            if not ef:
                continue
            if dt.date.fromisoformat(ef) <= day:
                cur = r
        return cur

    shifts: set[dt.date] = set()
    d = start
    while d <= end:
        rule = rule_for(d)
        if rule:
            workdays = {wk[x] for x in rule.get("workdays", []) if x in wk}
            if d.weekday() in workdays:
                shifts.add(d)
        d += dt.timedelta(days=1)

    for s in swaps:
        fd = s.get("from_date")
        td = s.get("to_date")
        if not fd or not td:
            continue
        f = dt.date.fromisoformat(fd)
        t = dt.date.fromisoformat(td)
        if f in shifts:
            shifts.remove(f)
        if start <= t <= end:
            shifts.add(t)

    for lv in leave:
        sd = lv.get("start_date")
        ed = lv.get("end_date")
        if not sd or not ed:
            continue
        a = dt.date.fromisoformat(sd)
        b = dt.date.fromisoformat(ed)
        if b < a:
            a, b = b, a
        x = a
        while x <= b:
            shifts.discard(x)
            x += dt.timedelta(days=1)

    return shifts


def history_dates(history_csv: Path, start: dt.date, end: dt.date) -> set[dt.date]:
    if not history_csv.exists():
        return set()
    out = set()
    with history_csv.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            raw = row.get("Name", "")
            try:
                d = dt.date.fromisoformat(raw)
            except Exception:
                continue
            if start <= d <= end:
                out.add(d)
    return out


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--period", choices=["week", "month"], default="week")
    args = parser.parse_args()

    cfg = read_json(ROOT / "data/config.json", {})
    swaps = read_json(ROOT / "data/swaps.json", [])
    leave = read_json(ROOT / "data/leave.json", [])

    start, end = resolve_range(args.period)
    planned = planned_dates(cfg, swaps, leave, start, end)
    history = history_dates(ROOT / cfg.get("history_csv", "History.csv"), start, end)
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
