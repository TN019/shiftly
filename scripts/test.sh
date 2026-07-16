#!/bin/bash
# Run the whole Shiftly test suite locally (no CI).
#   scripts/test.sh          - python + applescript tests + swift build
#   scripts/test.sh --fast   - skip the swift build
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== python: schedule core + planner CLI"
python3 scripts/test_schedule_core.py

echo "== applescript: parseDateTime rollover regression"
osascript scripts/test_date_rollover.applescript

echo "== applescript: syntax check"
tmpdir=$(mktemp -d -t shiftly_osacheck)
trap 'rm -rf "$tmpdir"' EXIT
osacompile -o "$tmpdir/sync.scpt" scripts/sync.applescript
osacompile -o "$tmpdir/main.scpt" scripts/main.applescript
echo "OK"

if [[ "${1:-}" != "--fast" ]]; then
  echo "== swift: build"
  (cd ShiftlyApp && swift build)
fi

echo "ALL TESTS PASSED"
