-- Regression test for the parseDateTime month-rollover bug.
-- Run: osascript scripts/test_date_rollover.applescript
-- Compiles sync.applescript, loads the real parseDateTimeFrom handler, and
-- checks it against simulated "today" values that used to trigger the bug
-- (day 29/30/31 + a shorter target month). No Calendar access involved.

on run
	set scriptsDir to do shell script "/usr/bin/dirname " & quoted form of (POSIX path of (path to me))
	set srcPath to scriptsDir & "/sync.applescript"
	set tmpDir to do shell script "mktemp -d -t shiftly_sync_test"
	set tmpPath to tmpDir & "/sync.scpt"
	do shell script "osacompile -o " & quoted form of tmpPath & " " & quoted form of srcPath
	set syncLib to load script (POSIX file tmpPath)

	set failures to {}

	-- {base y, base m, base d, input, expected y, expected m, expected d, expected time}
	set cases to {¬
		{2026, 1, 31, "2026-02-15 10:00", 2026, 2, 15, 10 * hours}, ¬
		{2026, 3, 31, "2026-04-30 18:30", 2026, 4, 30, 18 * hours + 30 * minutes}, ¬
		{2026, 12, 31, "2027-02-01 00:00", 2027, 2, 1, 0}, ¬
		{2024, 2, 29, "2025-02-28 09:15", 2025, 2, 28, 9 * hours + 15 * minutes}, ¬
		{2026, 5, 31, "2026-06-15 10:00", 2026, 6, 15, 10 * hours}, ¬
		{2026, 7, 16, "2026-07-31 23:59", 2026, 7, 31, 23 * hours + 59 * minutes}}

	repeat with c in cases
		set base to my makeDate(item 1 of c, item 2 of c, item 3 of c)
		set got to syncLib's parseDateTimeFrom(base, item 4 of c)
		if (year of got is not item 5 of c) or ((month of got as integer) is not item 6 of c) or (day of got is not item 7 of c) or (time of got is not item 8 of c) then
			set end of failures to ("input " & item 4 of c & " with base " & (item 1 of c) & "-" & (item 2 of c) & "-" & (item 3 of c) & " -> got " & (got as text))
		end if
	end repeat

	do shell script "rm -rf " & quoted form of tmpDir

	if (count of failures) is 0 then
		return "OK: " & (count of cases) & " parseDateTimeFrom cases passed"
	else
		error "FAILED:" & linefeed & my joinLines(failures)
	end if
end run

on makeDate(y, m, d)
	set dt to current date
	set day of dt to 1
	set year of dt to y
	set month of dt to m
	set day of dt to d
	set time of dt to 0
	return dt
end makeDate

on joinLines(xs)
	set out to ""
	repeat with x in xs
		set out to out & (contents of x) & linefeed
	end repeat
	return out
end joinLines
