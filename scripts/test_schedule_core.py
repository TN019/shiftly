#!/usr/bin/env python3
import datetime as dt
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from report import shift_hours
from schedule_core import (
    earliest_anchor_date,
    month_end,
    planned_dates,
    planned_days_detailed,
    read_json,
    sync_range,
    work_history_payload,
)

RULE_MO_TU = {"rules": [{"effective_from": "2026-01-01", "workdays": ["MO", "TU"]}]}


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
        swaps = [{"from_date": "2026-01-05", "to_date": "2026-01-07"}]
        start, end = dt.date(2026, 1, 5), dt.date(2026, 1, 10)
        s = planned_dates(RULE_MO_TU, swaps, [], start, end)
        self.assertIn(dt.date(2026, 1, 7), s)
        self.assertNotIn(dt.date(2026, 1, 5), s)

    def test_swap_chain(self):
        # A(1/5)->B(1/7), then B(1/7)->C(1/9): shift ends up on 1/9 only.
        swaps = [
            {"from_date": "2026-01-05", "to_date": "2026-01-07"},
            {"from_date": "2026-01-07", "to_date": "2026-01-09"},
        ]
        start, end = dt.date(2026, 1, 5), dt.date(2026, 1, 10)
        s = planned_dates(RULE_MO_TU, swaps, [], start, end)
        self.assertNotIn(dt.date(2026, 1, 5), s)
        self.assertNotIn(dt.date(2026, 1, 7), s)
        self.assertIn(dt.date(2026, 1, 9), s)

    def test_swap_to_outside_window(self):
        # Swapped-out day disappears; target beyond the window is not added.
        swaps = [{"from_date": "2026-01-05", "to_date": "2026-02-20"}]
        start, end = dt.date(2026, 1, 1), dt.date(2026, 1, 31)
        s = planned_dates(RULE_MO_TU, swaps, [], start, end)
        self.assertNotIn(dt.date(2026, 1, 5), s)
        self.assertNotIn(dt.date(2026, 2, 20), s)

    def test_swap_into_leave_day(self):
        # Leave is applied after swaps: swapping into a leave day is voided.
        swaps = [{"from_date": "2026-01-05", "to_date": "2026-01-08"}]
        leave = [{"start_date": "2026-01-08", "end_date": "2026-01-08"}]
        start, end = dt.date(2026, 1, 5), dt.date(2026, 1, 10)
        s = planned_dates(RULE_MO_TU, swaps, leave, start, end)
        self.assertNotIn(dt.date(2026, 1, 5), s)
        self.assertNotIn(dt.date(2026, 1, 8), s)

    def test_leave_crossing_month(self):
        leave = [{"start_date": "2026-01-30", "end_date": "2026-02-03"}]
        start, end = dt.date(2026, 1, 26), dt.date(2026, 2, 9)
        s = planned_dates(RULE_MO_TU, [], leave, start, end)
        # Mon 2/2 and Tue 2/3 fall inside the leave range; Mon 1/26 survives.
        self.assertIn(dt.date(2026, 1, 26), s)
        self.assertNotIn(dt.date(2026, 2, 2), s)
        self.assertNotIn(dt.date(2026, 2, 3), s)
        self.assertIn(dt.date(2026, 2, 9), s)

    def test_leave_reversed_range(self):
        # start/end swapped in the data is normalized.
        leave = [{"start_date": "2026-01-06", "end_date": "2026-01-05"}]
        start, end = dt.date(2026, 1, 5), dt.date(2026, 1, 6)
        s = planned_dates(RULE_MO_TU, [], leave, start, end)
        self.assertEqual(s, set())

    def test_rule_switch_boundary(self):
        # New rule applies from its effective_from day (inclusive).
        cfg = {"rules": [
            {"effective_from": "2026-01-01", "workdays": ["MO"]},
            {"effective_from": "2026-01-12", "workdays": ["TU"]},
        ]}
        start, end = dt.date(2026, 1, 5), dt.date(2026, 1, 18)
        s = planned_dates(cfg, [], [], start, end)
        self.assertIn(dt.date(2026, 1, 5), s)      # Mon, old rule
        self.assertNotIn(dt.date(2026, 1, 12), s)  # Mon, new rule active
        self.assertIn(dt.date(2026, 1, 13), s)     # Tue, new rule

    def test_malformed_overrides_ignored(self):
        swaps = [{"from_date": "not-a-date", "to_date": "2026-01-07"}, {}]
        leave = [{"start_date": "2026-01-06", "end_date": "garbage"}]
        start, end = dt.date(2026, 1, 5), dt.date(2026, 1, 6)
        s = planned_dates(RULE_MO_TU, swaps, leave, start, end)
        self.assertEqual(s, {dt.date(2026, 1, 5), dt.date(2026, 1, 6)})


class TestPlannedDaysDetailed(unittest.TestCase):
    def test_source_and_type(self):
        cfg = {"rules": [
            {"effective_from": "2026-01-01", "workdays": ["MO", "TU"], "shift_type": "day"},
            {"effective_from": "2026-01-12", "workdays": ["MO", "TU"], "shift_type": "night"},
        ]}
        swaps = [{"from_date": "2026-01-06", "to_date": "2026-01-08"}]
        days = planned_days_detailed(cfg, swaps, [], dt.date(2026, 1, 5), dt.date(2026, 1, 13))
        by_date = {d["date"].isoformat(): d for d in days}
        self.assertEqual(by_date["2026-01-05"]["source"], "rule")
        self.assertEqual(by_date["2026-01-05"]["shift_type"], "day")
        self.assertEqual(by_date["2026-01-08"]["source"], "swap")
        self.assertEqual(by_date["2026-01-08"]["shift_type"], "day", "swap-in day uses the rule active that day")
        self.assertEqual(by_date["2026-01-12"]["shift_type"], "night", "new rule from its effective day")
        self.assertNotIn("2026-01-06", by_date)

    def test_missing_type_defaults(self):
        cfg = {"rules": [{"effective_from": "2026-01-01", "workdays": ["MO"]}]}
        days = planned_days_detailed(cfg, [], [], dt.date(2026, 1, 5), dt.date(2026, 1, 5))
        self.assertEqual(days[0]["shift_type"], "default")


class TestSyncRange(unittest.TestCase):
    TODAY = dt.date(2026, 7, 16)

    def test_default_window(self):
        first, last = sync_range([], [], today=self.TODAY)
        self.assertEqual((first, last), (self.TODAY, dt.date(2026, 7, 31)))

    def test_next_month_mode(self):
        first, last = sync_range([], [], today=self.TODAY, mode="next_month")
        self.assertEqual((first, last), (dt.date(2026, 8, 1), dt.date(2026, 8, 31)))

    def test_next_month_mode_december(self):
        first, last = sync_range([], [], today=dt.date(2026, 12, 5), mode="next_month")
        self.assertEqual((first, last), (dt.date(2027, 1, 1), dt.date(2027, 1, 31)))

    def test_extends_to_latest_override(self):
        swaps = [{"from_date": "2026-07-20", "to_date": "2026-09-02"}]
        leave = [{"start_date": "2026-08-10", "end_date": "2026-08-15"}]
        first, last = sync_range(swaps, leave, today=self.TODAY)
        self.assertEqual(last, dt.date(2026, 9, 2))

    def test_bad_override_dates_ignored(self):
        swaps = [{"to_date": "oops"}]
        first, last = sync_range(swaps, [], today=self.TODAY)
        self.assertEqual(last, dt.date(2026, 7, 31))

    def test_month_end_december(self):
        self.assertEqual(month_end(dt.date(2026, 12, 5)), dt.date(2026, 12, 31))


class TestReportHours(unittest.TestCase):
    def test_regular_shift(self):
        self.assertAlmostEqual(shift_hours("10:00", "18:30"), 8.5)

    def test_cross_midnight(self):
        self.assertAlmostEqual(shift_hours("22:00", "06:00"), 8.0)


class TestReadJson(unittest.TestCase):
    def test_missing_file_returns_default(self):
        self.assertEqual(read_json(Path("/nonexistent/x.json"), []), [])

    def test_empty_array(self):
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            f.write("[]")
        try:
            self.assertEqual(read_json(Path(f.name), None), [])
        finally:
            os.unlink(f.name)

    def test_corrupt_json_raises(self):
        # Corrupt data must fail loudly, never silently become the default
        # (a silent default would wipe user data on the next write).
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            f.write('{"broken": ')
        try:
            with self.assertRaises(json.JSONDecodeError):
                read_json(Path(f.name), {})
        finally:
            os.unlink(f.name)


class TestPlannerCLI(unittest.TestCase):
    """End-to-end checks of scripts/planner.py against a temp repo root."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        (root / "data").mkdir()
        (root / "data/config.json").write_text(json.dumps({
            "config_version": 1,
            "calendar_name": "Shifts",
            "event_title": "Work Schedule",
            "default_start_time": "10:00",
            "default_end_time": "18:30",
            "setup_completed": True,
            "rules": [{"effective_from": "2026-01-01", "workdays": ["MO", "TU"]}],
        }))
        (root / "data/swaps.json").write_text("[]")
        (root / "data/leave.json").write_text("[]")
        self.root = root

    def tearDown(self):
        self.tmp.cleanup()

    def run_planner(self, *args, expect_ok=True):
        env = dict(os.environ, SHIFTLY_ROOT=str(self.root))
        proc = subprocess.run(
            [sys.executable, str(Path(__file__).parent / "planner.py"), *args],
            capture_output=True, text=True, env=env,
        )
        if expect_ok:
            self.assertEqual(proc.returncode, 0, proc.stderr)
        return proc

    def test_shifts_output(self):
        out = self.run_planner("shifts", "--start", "2026-01-05", "--end", "2026-01-11").stdout
        self.assertEqual(out.splitlines(), ["2026-01-05|rule|default", "2026-01-06|rule|default"])

    def test_config_summary(self):
        out = self.run_planner("config-summary").stdout.splitlines()
        self.assertEqual(out, ["Shifts", "Work Schedule", "10:00", "18:30"])

    def test_sync_range_lines(self):
        out = self.run_planner("sync-range").stdout.splitlines()
        self.assertEqual(len(out), 2)
        dt.date.fromisoformat(out[0])
        dt.date.fromisoformat(out[1])

    def test_add_swap_and_leave(self):
        self.run_planner("add-swap", "--from-date", "2026-01-05", "--to-date", "2026-01-07")
        self.run_planner("add-leave", "--start", "2026-01-08", "--end", "2026-01-09")
        swaps = json.loads((self.root / "data/swaps.json").read_text())
        leave = json.loads((self.root / "data/leave.json").read_text())
        self.assertEqual(swaps, [{"from_date": "2026-01-05", "to_date": "2026-01-07"}])
        self.assertEqual(leave, [{"start_date": "2026-01-08", "end_date": "2026-01-09"}])

    def test_add_swap_rejects_injection_input(self):
        # Malicious/broken input must fail validation, not execute or write.
        evil = "2026-01-05'); import os; os.system('true'); ('"
        proc = self.run_planner("add-swap", "--from-date", evil,
                                "--to-date", "2026-01-07", expect_ok=False)
        self.assertNotEqual(proc.returncode, 0)
        self.assertEqual(json.loads((self.root / "data/swaps.json").read_text()), [])

    def test_add_swap_creates_missing_file(self):
        (self.root / "data/swaps.json").unlink()
        self.run_planner("add-swap", "--from-date", "2026-01-05", "--to-date", "2026-01-07")
        swaps = json.loads((self.root / "data/swaps.json").read_text())
        self.assertEqual(len(swaps), 1)


class TestManualShiftHistory(unittest.TestCase):
    def test_manual_dates_join_history_and_anchor(self):
        import tempfile, os as _os
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "data").mkdir()
            (root / "data/config.json").write_text(json.dumps({
                "config_version": 2, "calendar_name": "S", "event_title": "W",
                "default_start_time": "10:00", "default_end_time": "18:30",
                "rules": [{"effective_from": "2026-07-01", "workdays": ["MO"]}],
            }))
            (root / "data/swaps.json").write_text("[]")
            (root / "data/leave.json").write_text("[]")
            (root / "data/manual_shifts.json").write_text(json.dumps([
                {"date": "2026-02-24", "start": "09:00", "end": "17:00", "source": "import"},
                {"date": "2026-03-03", "start": "09:00", "end": "17:00", "source": "import"},
                {"date": "bad-date", "start": "0:0", "end": "0:0", "source": "import"},
            ]))
            rows = work_history_payload(root)
            ymds = [r["ymd"] for r in rows]
            self.assertIn("2026-02-24", ymds)
            self.assertIn("2026-03-03", ymds)
            self.assertEqual(rows[0]["ymd"], "2026-02-24", "Day 1 = earliest imported day")
            self.assertEqual(rows[0]["ordinal"], 1)


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
