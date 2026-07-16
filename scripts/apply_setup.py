#!/usr/bin/env python3
"""Read JSON from stdin: {start, end, workdays: ["MO", ...]}. Merge into data/config.json."""
import datetime
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from schedule_core import repo_root

cfg_path = repo_root() / "data" / "config.json"
data = json.load(sys.stdin)
if cfg_path.exists():
    cfg = json.loads(cfg_path.read_text())
else:
    cfg = {
        "config_version": 1,
        "calendar_name": "Shifts",
        "event_title": "Work Schedule",
        "history_csv": "History.csv",
        "setup_completed": False,
        "rules": [],
    }
cfg["default_start_time"] = data["start"]
cfg["default_end_time"] = data["end"]

# Upsert today's rule; never wipe the effective_from history.
today = datetime.date.today().isoformat()
rules = [r for r in cfg.get("rules", []) if isinstance(r, dict)]
existing = next((r for r in rules if r.get("effective_from") == today), None)
if existing is not None:
    existing["workdays"] = data["workdays"]
else:
    rules.append({"effective_from": today, "workdays": data["workdays"]})
rules.sort(key=lambda r: r.get("effective_from", ""))
cfg["rules"] = rules

cfg["setup_completed"] = True
if "config_version" not in cfg:
    cfg["config_version"] = 1
cfg_path.write_text(json.dumps(cfg, indent=2) + "\n", encoding="utf-8")
