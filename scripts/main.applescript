use scripting additions

property projectRoot : "/Users/tn/Dev/Local/ShiftFlow"

on run
  set flag to do shell script "/usr/bin/python3 " & quoted form of (projectRoot & "/scripts/needs_setup.py")
  if flag starts with "1" then
    my runSetupWizard()
  end if

  set options to {"Schedule", "Overrides", "Sync", "Reports", "Exit"}
  repeat
    set picked to choose from list options with prompt "Choose a section." with title "ShiftFlow" default items {"Sync"}
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
  set picked to choose from list options with prompt "Schedule actions" with title "ShiftFlow / Schedule" default items {"Set Work Schedule..."}
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
  set picked to choose from list options with prompt "Override actions" with title "ShiftFlow / Overrides" default items {"Add Swap"}
  if picked is false then return
  set choice to item 1 of picked
  if choice is "Add Swap" then
    my addSwap()
  else if choice is "Add Leave" then
    my addLeave()
  end if
end overridesMenu

on syncMenu()
  set options to {"Sync Now", "View Sync Log", "Back"}
  set picked to choose from list options with prompt "Sync actions" with title "ShiftFlow / Sync" default items {"Sync Now"}
  if picked is false then return
  set choice to item 1 of picked
  if choice is "Sync Now" then
    try
      do shell script "osascript " & quoted form of (projectRoot & "/scripts/sync.applescript")
      display dialog "Sync completed." buttons {"OK"} default button "OK"
    on error errText
      display dialog "Sync failed: " & errText buttons {"OK"} default button "OK"
    end try
  else if choice is "View Sync Log" then
    my viewSyncLog()
  end if
end syncMenu

on reportsMenu()
  set options to {"Weekly Hours", "Monthly Hours", "Back"}
  set picked to choose from list options with prompt "Report actions" with title "ShiftFlow / Reports" default items {"Weekly Hours"}
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
  set picked to choose from list dayChoices with prompt "Select workdays (Cmd-click multiple):" with title "ShiftFlow — Setup" with multiple selections allowed
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

  set startDialog to display dialog "Daily start time (HH:MM, e.g. 10:00):" default answer "10:00" with title "ShiftFlow — Setup"
  set startT to text returned of startDialog
  set endDialog to display dialog "Daily end time (HH:MM, e.g. 18:30):" default answer "18:30" with title "ShiftFlow — Setup"
  set endT to text returned of endDialog

  set jsonPayload to my buildSetupJson(wdCodes, startT, endT)
  try
    do shell script "printf %s " & quoted form of jsonPayload & " | /usr/bin/python3 " & quoted form of (projectRoot & "/scripts/apply_setup.py")
    display dialog "Settings saved. Use Sync Now to write your calendar." buttons {"OK"} default button "OK" with title "ShiftFlow"
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

on viewSyncLog()
  set logPath to projectRoot & "/data/logs/sync.log"
  try
    set contentText to do shell script "test -f " & quoted form of logPath & " && tail -n 40 " & quoted form of logPath & " || echo '(no log yet)'"
    display dialog contentText buttons {"OK"} default button "OK" with title "Sync Log (last 40 lines)"
  on error errText
    display dialog "Could not read log: " & errText buttons {"OK"} default button "OK"
  end try
end viewSyncLog

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

on appendSwap(fromDate, toDate)
  set py to "import json,pathlib,datetime;f=pathlib.Path('/Users/tn/Dev/Local/ShiftFlow/data/swaps.json');a=json.loads(f.read_text());datetime.date.fromisoformat('" & fromDate & "');datetime.date.fromisoformat('" & toDate & "');a.append({'from_date':'" & fromDate & "','to_date':'" & toDate & "'});f.write_text(json.dumps(a,indent=2))"
  do shell script "/usr/bin/python3 -c " & quoted form of py
end appendSwap

on appendLeave(startDate, endDate)
  set py to "import json,pathlib,datetime;f=pathlib.Path('/Users/tn/Dev/Local/ShiftFlow/data/leave.json');a=json.loads(f.read_text());datetime.date.fromisoformat('" & startDate & "');datetime.date.fromisoformat('" & endDate & "');a.append({'start_date':'" & startDate & "','end_date':'" & endDate & "'});f.write_text(json.dumps(a,indent=2))"
  do shell script "/usr/bin/python3 -c " & quoted form of py
end appendLeave
