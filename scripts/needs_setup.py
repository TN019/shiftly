#!/usr/bin/env python3
"""Print 1 if first-time setup is required, else 0."""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from schedule_core import repo_root

cfg_path = repo_root() / "data" / "config.json"
if not cfg_path.exists():
    print("1")
else:
    cfg = json.loads(cfg_path.read_text())
    need = not cfg.get("setup_completed", True)
    print("1" if need else "0")
