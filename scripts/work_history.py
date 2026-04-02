#!/usr/bin/env python3
"""Emit JSON array of past work days: [{\"ymd\": \"YYYY-MM-DD\", \"ordinal\": N}, ...]."""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from schedule_core import work_history_payload


def main() -> None:
    try:
        data = work_history_payload()
    except Exception as e:
        print(str(e), file=sys.stderr)
        sys.exit(1)
    print(json.dumps(data))


if __name__ == "__main__":
    main()
