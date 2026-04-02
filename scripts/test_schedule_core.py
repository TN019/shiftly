#!/usr/bin/env python3
import datetime as dt
import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from schedule_core import earliest_anchor_date, planned_dates, work_history_payload


class TestPlannedDates(unittest.TestCase):
    def test_empty_rules(self):
        cfg = {"rules": []}
        day = dt.date(2026, 1, 5)
        self.assertEqual(planned_dates(cfg, [], [], day, day), set())

    def test_one_weekday(self):
        cfg = {"rules": [{"effective_from": "2026-01-01", "workdays": ["MO"]}]}
        mon = dt.date(2026, 1, 5)
        tue = dt.date(2026, 1, 6)
        self.assertEqual(planned_dates(cfg, [], [], mon, tue), {mon})

    def test_swap_moves_shift(self):
        cfg = {"rules": [{"effective_from": "2026-01-01", "workdays": ["MO", "TU"]}]}
        swaps = [{"from_date": "2026-01-05", "to_date": "2026-01-07"}]
        start, end = dt.date(2026, 1, 5), dt.date(2026, 1, 10)
        s = planned_dates(cfg, swaps, [], start, end)
        self.assertIn(dt.date(2026, 1, 7), s)
        self.assertNotIn(dt.date(2026, 1, 5), s)


class TestAnchor(unittest.TestCase):
    def test_rules_only(self):
        cfg = {"rules": [{"effective_from": "2025-06-01", "workdays": ["MO"]}]}
        p = Path("/nonexistent/history.csv")
        self.assertEqual(earliest_anchor_date(cfg, p), dt.date(2025, 6, 1))


class TestWorkHistoryIntegration(unittest.TestCase):
    def test_fixture_repo(self):
        root = Path(__file__).resolve().parent.parent
        if not (root / "data" / "config.json").exists():
            self.skipTest("no data/config.json")
        data = work_history_payload(root)
        self.assertIsInstance(data, list)
        if data:
            row = data[0]
            self.assertIn("ymd", row)
            self.assertIn("ordinal", row)
            self.assertEqual(row["ordinal"], 1)


if __name__ == "__main__":
    unittest.main()
