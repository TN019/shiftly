use scripting additions

property projectRoot : ""

on getProjectRoot()
	try
		set e to do shell script "if [ -n \"$SHIFTLY_ROOT\" ]; then printf %s \"$SHIFTLY_ROOT\"; elif [ -n \"$SHIFTY_ROOT\" ]; then printf %s \"$SHIFTY_ROOT\"; elif [ -n \"$SHIFTFLOW_ROOT\" ]; then printf %s \"$SHIFTFLOW_ROOT\"; fi"
		if e is not "" then return e
	end try
	try
		set mePath to POSIX path of (path to me)
		set scriptsDir to do shell script "/usr/bin/dirname " & quoted form of mePath
		set rootDir to do shell script "/usr/bin/dirname " & quoted form of scriptsDir
		return rootDir
	on error errMsg
		error ("Shiftly: could not resolve project root. Set SHIFTLY_ROOT (legacy SHIFTY_ROOT/SHIFTFLOW_ROOT also accepted). " & errMsg) number -1700
	end try
end getProjectRoot

on run
	set projectRoot to my getProjectRoot()
	set flag to do shell script "/usr/bin/python3 " & quoted form of (projectRoot & "/scripts/needs_setup.py")
  if flag starts with "1" then
    my runSetupWizard()
  end if

  set options to {"Schedule", "Overrides", "Sync", "Reports", "Exit"}
  repeat
    set picked to choose from list options with prompt "Choose a section." with title "Shiftly" default items {"Sync"}
    if picked is false then exit repeat

    set choice to item 1 of picked
    if choice is "Schedule" then
      my scheduleMenu()
    else if choice is "Overrides" then
      my overridesMenu()
    else if choice is "Sync" then
      my syncMenu()
    else if choice is "Reports" then
      my reportsMenu()
    else if choice is "Exit" then
      exit repeat
    end if
  end repeat
end run

on scheduleMenu()
  set options to {"Set Work Schedule...", "View Current Rules", "Back"}
  set picked to choose from list options with prompt "Schedule actions" with title "Shiftly / Schedule" default items {"Set Work Schedule..."}
  if picked is false then return
  set choice to item 1 of picked
  if choice is "Set Work Schedule..." then
    my runSetupWizard()
  else if choice is "View Current Rules" then
    set configText to do shell script "cat " & quoted form of (projectRoot & "/data/config.json")
    display dialog configText buttons {"OK"} default button "OK" with title "Current Rules"
  end if
end scheduleMenu

on overridesMenu()
  set options to {"Add Swap", "Add Leave", "Back"}
  set picked to choose from list options with prompt "Override actions" with title "Shiftly / Overrides" default items {"Add Swap"}
  if picked is false then return
  set choice to item 1 of picked
  if choice is "Add Swap" then
    my addSwap()
  else if choice is "Add Leave" then
    my addLeave()
  end if
end overridesMenu

on syncMenu()
  set options to {"Sync Now", "View Sync Report", "Back"}
  set picked to choose from list options with prompt "Sync actions" with title "Shiftly / Sync" default items {"Sync Now"}
  if picked is false then return
  set choice to item 1 of picked
  if choice is "Sync Now" then
    try
      set appBinary to my findAppBinary()
      set outText to do shell script "export SHIFTLY_ROOT=" & quoted form of projectRoot & " && " & quoted form of appBinary & " --sync"
      display dialog "Sync completed." & linefeed & outText buttons {"OK"} default button "OK"
    on error errText
      display dialog "Sync failed: " & errText buttons {"OK"} default button "OK"
    end try
  else if choice is "View Sync Report" then
    my viewSyncReport()
  end if
end syncMenu

-- Sync runs through the app binary (same EventKit engine as the GUI).
-- Calendar access must have been granted to the app once via the GUI.
on findAppBinary()
  set candidates to {projectRoot & "/dist/Shiftly.app/Contents/MacOS/Shiftly", "/Applications/Shiftly.app/Contents/MacOS/Shiftly", projectRoot & "/ShiftlyApp/.build/release/ShiftlyApp", projectRoot & "/ShiftlyApp/.build/debug/ShiftlyApp"}
  repeat with p in candidates
    set candidatePath to contents of p
    try
      do shell script "test -x " & quoted form of candidatePath
      return candidatePath
    end try
  end repeat
  error "Shiftly binary not found. Build it first: scripts/build_app.sh"
end findAppBinary

on reportsMenu()
  set options to {"Weekly Hours", "Monthly Hours", "Back"}
  set picked to choose from list options with prompt "Report actions" with title "Shiftly / Reports" default items {"Weekly Hours"}
  if picked is false then return
  set choice to item 1 of picked
  if choice is "Weekly Hours" then
    my showHoursReport("week")
  else if choice is "Monthly Hours" then
    my showHoursReport("month")
  end if
end reportsMenu

on runSetupWizard()
  set dayChoices to {"Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"}
  set picked to choose from list dayChoices with prompt "Select workdays (Cmd-click multiple):" with title "Shiftly — Setup" with multiple selections allowed
  if picked is false then return
  if (count of picked) is 0 then
    display dialog "Select at least one workday." buttons {"OK"} default button "OK"
    my runSetupWizard()
    return
  end if

  set wdCodes to {}
  repeat with d in picked
    set end of wdCodes to my weekdayCode(contents of d)
  end repeat

  set startDialog to display dialog "Daily start time (HH:MM, e.g. 10:00):" default answer "10:00" with title "Shiftly — Setup"
  set startT to text returned of startDialog
  set endDialog to display dialog "Daily end time (HH:MM, e.g. 18:30):" default answer "18:30" with title "Shiftly — Setup"
  set endT to text returned of endDialog

  set jsonPayload to my buildSetupJson(wdCodes, startT, endT)
  try
    do shell script "printf %s " & quoted form of jsonPayload & " | /usr/bin/python3 " & quoted form of (projectRoot & "/scripts/apply_setup.py")
    display dialog "Settings saved. Use Sync Now to write your calendar." buttons {"OK"} default button "OK" with title "Shiftly"
  on error errText
    display dialog "Could not save settings: " & errText buttons {"OK"} default button "OK"
  end try
end runSetupWizard

on weekdayCode(dayLabel)
  if dayLabel is "Monday" then return "MO"
  if dayLabel is "Tuesday" then return "TU"
  if dayLabel is "Wednesday" then return "WE"
  if dayLabel is "Thursday" then return "TH"
  if dayLabel is "Friday" then return "FR"
  if dayLabel is "Saturday" then return "SA"
  return "SU"
end weekdayCode

on buildSetupJson(wdCodes, startT, endT)
  set parts to {}
  repeat with c in wdCodes
    set end of parts to "\"" & (contents of c) & "\""
  end repeat
  set wdStr to my joinDelim(parts, ",")
  return "{\"start\":\"" & startT & "\",\"end\":\"" & endT & "\",\"workdays\":[" & wdStr & "]}"
end buildSetupJson

on joinDelim(itemList, delim)
  set out to ""
  set i to 1
  repeat with oneItem in itemList
    if i is greater than 1 then set out to out & delim
    set out to out & (contents of oneItem)
    set i to i + 1
  end repeat
  return out
end joinDelim

on viewSyncReport()
  set metaPath to projectRoot & "/data/meta.json"
  set reportPath to projectRoot & "/data/last_sync_report.json"
  try
    set contentText to do shell script "for f in " & quoted form of metaPath & " " & quoted form of reportPath & "; do test -f \"$f\" && cat \"$f\" && printf '\\n'; done || echo '(no sync yet)'"
    display dialog contentText buttons {"OK"} default button "OK" with title "Last Sync"
  on error errText
    display dialog "Could not read sync report: " & errText buttons {"OK"} default button "OK"
  end try
end viewSyncReport

on showHoursReport(periodKind)
  set cmd to "/usr/bin/python3 " & quoted form of (projectRoot & "/scripts/report.py") & " --period " & quoted form of periodKind
  try
    set reportText to do shell script cmd
    display dialog reportText buttons {"OK"} default button "OK" with title "Hours Report"
  on error errText
    display dialog "Could not generate report: " & errText buttons {"OK"} default button "OK"
  end try
end showHoursReport

on addSwap()
  set fromDialog to display dialog "Swap from date (YYYY-MM-DD):" default answer ""
  set fromDate to text returned of fromDialog
  set toDialog to display dialog "Swap to date (YYYY-MM-DD):" default answer ""
  set toDate to text returned of toDialog

  try
    my appendSwap(fromDate, toDate)
    display dialog "Swap saved." buttons {"OK"} default button "OK"
  on error errText
    display dialog "Invalid swap input: " & errText buttons {"OK"} default button "OK"
  end try
end addSwap

on addLeave()
  set startDialog to display dialog "Leave start date (YYYY-MM-DD):" default answer ""
  set startDate to text returned of startDialog
  set endDialog to display dialog "Leave end date (YYYY-MM-DD):" default answer ""
  set endDate to text returned of endDialog

  try
    my appendLeave(startDate, endDate)
    display dialog "Leave saved." buttons {"OK"} default button "OK"
  on error errText
    display dialog "Invalid leave input: " & errText buttons {"OK"} default button "OK"
  end try
end addLeave

-- User input goes to planner.py as shell-quoted argv values — never
-- interpolated into code. planner.py validates the dates and exits non-zero
-- on bad input, which surfaces as the "Invalid ... input" dialog above.
on runPlanner(argsText)
	do shell script "export SHIFTLY_ROOT=" & quoted form of projectRoot & " && /usr/bin/python3 " & quoted form of (projectRoot & "/scripts/planner.py") & " " & argsText
end runPlanner

on appendSwap(fromDate, toDate)
	my runPlanner("add-swap --from-date " & quoted form of fromDate & " --to-date " & quoted form of toDate)
end appendSwap

on appendLeave(startDate, endDate)
	my runPlanner("add-leave --start " & quoted form of startDate & " --end " & quoted form of endDate)
end appendLeave
