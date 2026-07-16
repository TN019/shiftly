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
  echo "== swift: build + test"
  # Command Line Tools ship Testing.framework outside the default search
  # paths (and without Xcode there is no XCTest); pass them explicitly so
  # `swift test` works on CLT-only machines. Harmless with full Xcode.
  CLT_DEV=/Library/Developer/CommandLineTools/Library/Developer
  SWIFT_TEST_FLAGS=()
  if [[ -d "$CLT_DEV/Frameworks/Testing.framework" ]]; then
    SWIFT_TEST_FLAGS=(
      -Xswiftc -F -Xswiftc "$CLT_DEV/Frameworks"
      -Xlinker -F -Xlinker "$CLT_DEV/Frameworks"
      -Xlinker -rpath -Xlinker "$CLT_DEV/Frameworks"
      -Xlinker -rpath -Xlinker "$CLT_DEV/usr/lib"
    )
  fi
  (cd ShiftlyApp && swift build && swift test "${SWIFT_TEST_FLAGS[@]}")
fi

echo "ALL TESTS PASSED"
