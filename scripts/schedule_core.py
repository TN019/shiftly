"""Shared schedule and work-history logic for Shiftly (Python scripts)."""
from __future__ import annotations

import csv
import datetime as dt
import json
import os
from pathlib import Path

SUPPORTED_CONFIG_VERSION = 2


def repo_root() -> Path:
    env = (
        os.environ.get("SHIFTLY_ROOT")
        or os.environ.get("SHIFTY_ROOT")  # legacy
        or os.environ.get("SHIFTFLOW_ROOT")  # legacy
        or ""
    ).strip()
    if env:
        return Path(env).expanduser().resolve()
    return Path(__file__).resolve().parent.parent


def read_json(path: Path, default):
    if not path.exists():
        return default
    return json.loads(path.read_text(encoding="utf-8"))


def holiday_dates(root: Path) -> set[dt.date]:
    """Dates covered by public holidays (data/holidays.json items
    {start_date, end_date, name}; both ends inclusive)."""
    out: set[dt.date] = set()
    for item in read_json(root / "data/holidays.json", []):
        try:
            a = dt.date.fromisoformat(item.get("start_date", ""))
            b = dt.date.fromisoformat(item.get("end_date", ""))
        except ValueError:
            continue
        if b < a:
            a, b = b, a
        d = a
        while d <= b:
            out.add(d)
            d += dt.timedelta(days=1)
    return out


def planned_dates(cfg: dict, swaps: list, leave: list, start: dt.date, end: dt.date,
                  holidays: set | frozenset = frozenset()) -> set[dt.date]:
    wk = {"MO": 0, "TU": 1, "WE": 2, "TH": 3, "FR": 4, "SA": 5, "SU": 6}
    rules = sorted(cfg.get("rules", []), key=lambda r: r.get("effective_from", ""))

    def rule_for(day: dt.date):
        cur = None
        for r in rules:
            ef = r.get("effective_from")
            if not ef:
                continue
            try:
                if dt.date.fromisoformat(ef) <= day:
                    cur = r
            except ValueError:
                continue
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

    # Public holidays cancel rule days. Applied before swaps so an explicit
    # swap onto a holiday still wins (leave, applied last, removes anything).
    for h in holidays:
        shifts.discard(h)

    for s in swaps:
        fd = s.get("from_date")
        td = s.get("to_date")
        if not fd or not td:
            continue
        try:
            f = dt.date.fromisoformat(fd)
            t = dt.date.fromisoformat(td)
        except ValueError:
            continue
        if f in shifts:
            shifts.remove(f)
        if start <= t <= end:
            shifts.add(t)

    for lv in leave:
        sd = lv.get("start_date")
        ed = lv.get("end_date")
        if not sd or not ed:
            continue
        try:
            a = dt.date.fromisoformat(sd)
            b = dt.date.fromisoformat(ed)
        except ValueError:
            continue
        if b < a:
            a, b = b, a
        x = a
        while x <= b:
            shifts.discard(x)
            x += dt.timedelta(days=1)

    return shifts


def planned_days_detailed(cfg: dict, swaps: list, leave: list, start: dt.date, end: dt.date,
                          holidays: set | frozenset = frozenset()) -> list[dict]:
    """Like planned_dates, but with per-day provenance and shift type:
    [{"date": date, "source": "rule"|"swap", "shift_type": str}, ...] sorted.

    The shift type of a day is the type of the rule in effect on that day
    (config_version 2 rules carry "shift_type"; absent -> "default"). A
    swapped-in day uses the rule in effect on the day actually worked.
    """
    rules = sorted(cfg.get("rules", []), key=lambda r: r.get("effective_from", ""))

    def rule_for(day: dt.date):
        cur = None
        for r in rules:
            ef = r.get("effective_from")
            if not ef:
                continue
            try:
                if dt.date.fromisoformat(ef) <= day:
                    cur = r
            except ValueError:
                continue
        return cur

    def type_for(day: dt.date) -> str:
        r = rule_for(day)
        return (r or {}).get("shift_type") or "default"

    dates = planned_dates(cfg, swaps, leave, start, end, holidays)
    swap_targets = set()
    for s in swaps:
        td = s.get("to_date")
        try:
            if td and dt.date.fromisoformat(td) in dates:
                swap_targets.add(dt.date.fromisoformat(td))
        except ValueError:
            continue

    return [
        {
            "date": d,
            "source": "swap" if d in swap_targets else "rule",
            "shift_type": type_for(d),
        }
        for d in sorted(dates)
    ]


def month_end(day: dt.date) -> dt.date:
    if day.month == 12:
        return dt.date(day.year + 1, 1, 1) - dt.timedelta(days=1)
    return dt.date(day.year, day.month + 1, 1) - dt.timedelta(days=1)


def sync_range(swaps: list, leave: list, today: dt.date | None = None, mode: str = "",
               earliest: dt.date | None = None) -> tuple[dt.date, dt.date]:
    """Sync window: earliest anchor (or today)..month end, so the whole
    schedule history lives in the calendar too — or the whole next month
    for mode 'next_month'. Extended to cover the latest override date."""
    today = today or dt.date.today()
    if mode == "next_month":
        first = dt.date(today.year + (1 if today.month == 12 else 0),
                        1 if today.month == 12 else today.month + 1, 1)
        last = month_end(first)
    else:
        first = today
        last = month_end(today)
        if earliest is not None and earliest < first:
            first = earliest

    def date_or_none(s):
        try:
            return dt.date.fromisoformat(s)
        except (TypeError, ValueError):
            return None

    for s in swaps:
        t = date_or_none(s.get("to_date", ""))
        if t and t > last:
            last = t
    for lv in leave:
        e = date_or_none(lv.get("end_date", ""))
        if e and e > last:
            last = e
    return first, last


def history_dates_in_range(history_csv: Path, start: dt.date, end: dt.date) -> set[dt.date]:
    if not history_csv.exists():
        return set()
    out: set[dt.date] = set()
    with history_csv.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            raw = row.get("Name", "")
            try:
                d = dt.date.fromisoformat(raw)
            except ValueError:
                continue
            if start <= d <= end:
                out.add(d)
    return out


def all_history_dates(history_csv: Path) -> set[dt.date]:
    if not history_csv.exists():
        return set()
    out: set[dt.date] = set()
    with history_csv.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            raw = row.get("Name", "")
            try:
                out.add(dt.date.fromisoformat(raw))
            except ValueError:
                continue
    return out


def resolve_history_path(root: Path, cfg: dict) -> Path:
    rel = cfg.get("history_csv", "History.csv")
    p = Path(rel)
    if p.is_absolute():
        return p
    return root / p


def earliest_anchor_date(cfg: dict, history_csv: Path) -> dt.date:
    today = dt.date.today()
    candidates: list[dt.date] = []
    for r in cfg.get("rules", []):
        ef = r.get("effective_from")
        if not ef:
            continue
        try:
            candidates.append(dt.date.fromisoformat(ef))
        except ValueError:
            continue
    candidates.extend(all_history_dates(history_csv))
    if not candidates:
        return today
    return min(candidates)


def manual_shift_dates(root: Path) -> set[dt.date]:
    """Dates of manual shifts (calendar readbacks and history imports)."""
    out: set[dt.date] = set()
    for item in read_json(root / "data/manual_shifts.json", []):
        try:
            out.add(dt.date.fromisoformat(item.get("date", "")))
        except ValueError:
            continue
    return out


def work_history_payload(root: Path | None = None) -> list[dict]:
    root = root or repo_root()
    cfg = read_json(root / "data/config.json", {})
    ver = cfg.get("config_version", 1)
    if isinstance(ver, int) and ver > SUPPORTED_CONFIG_VERSION:
        raise ValueError(f"Unsupported config_version {ver} (max {SUPPORTED_CONFIG_VERSION})")
    swaps = read_json(root / "data/swaps.json", [])
    leave = read_json(root / "data/leave.json", [])
    history_path = resolve_history_path(root, cfg)
    manual = manual_shift_dates(root)
    today = dt.date.today()
    start = earliest_anchor_date(cfg, history_path)
    if manual:
        start = min(start, min(manual))
    if start > today:
        start = today
    planned = planned_dates(cfg, swaps, leave, start, today, holiday_dates(root))
    hist = all_history_dates(history_path)
    combined = sorted(d for d in (planned | hist | manual) if d <= today)
    return [{"ymd": d.isoformat(), "ordinal": n} for n, d in enumerate(combined, start=1)]
