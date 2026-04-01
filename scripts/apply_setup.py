#!/usr/bin/env python3
"""Read JSON from stdin: {start, end, workdays: ["MO", ...]}. Merge into data/config.json."""
import datetime
import json
import pathlib
import sys

root = pathlib.Path(__file__).resolve().parent.parent
cfg_path = root / "data" / "config.json"
data = json.load(sys.stdin)
if cfg_path.exists():
    cfg = json.loads(cfg_path.read_text())
else:
    cfg = {
        "calendar_name": "Shifts",
        "event_title": "Work Schedule",
        "history_csv": "History.csv",
        "setup_completed": False,
        "rules": [],
    }
cfg["default_start_time"] = data["start"]
cfg["default_end_time"] = data["end"]
cfg["rules"] = [
    {"effective_from": datetime.date.today().isoformat(), "workdays": data["workdays"]}
]
cfg["setup_completed"] = True
cfg_path.write_text(json.dumps(cfg, indent=2) + "\n", encoding="utf-8")
