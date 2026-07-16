use scripting additions

property projectRoot : ""
property historyImportedMarker : "/data/meta.history_imported"

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
	set cfg to my readConfig()
  set calendarName to calendar_name of cfg
  set eventTitle to event_title of cfg
  set shiftStart to default_start_time of cfg
  set shiftEnd to default_end_time of cfg

  set rangePair to my getSyncRangeYmd()
  set startYmd to item 1 of rangePair
  set endYmd to item 2 of rangePair
  set startDate to my parseDateTime(startYmd & " 00:00")
  set endDate to my parseDateTime(endYmd & " 23:59")

  my logInfo("sync start " & startYmd & " .. " & endYmd)
  my ensureCalendar(calendarName)

  my clearSyncEvents(calendarName, startDate, endDate)
  my importHistoryOnce(calendarName, eventTitle, shiftStart, shiftEnd)
  my generatePlannedFutureShifts(calendarName, eventTitle, shiftStart, shiftEnd, startDate, endDate)

  my writeMetaStatus("success")
  my logInfo("sync done")
end run

on ensureCalendar(targetCalendar)
  tell application "Calendar"
    if (count of (every calendar whose name is targetCalendar)) is 0 then
      make new calendar with properties {name:targetCalendar}
      my logInfo("created calendar: " & targetCalendar)
    end if
  end tell
end ensureCalendar

on clearSyncEvents(targetCalendar, startDate, endDate)
  tell application "Calendar"
    tell calendar targetCalendar
      set candidateEvents to every event
      repeat with ev in candidateEvents
        set evStart to start date of ev
        if (evStart is greater than or equal to startDate) and (evStart is less than or equal to endDate) then
          set evNotes to ""
          try
            set evNotes to (description of ev as text)
          end try
          if evNotes contains "[SF_SYNC]" then delete ev
        end if
      end repeat
    end tell
  end tell
end clearSyncEvents

on createShiftEvent(targetCalendar, titleText, startDateTime, endDateTime, sourceTag)
  if my hasExistingEvent(targetCalendar, titleText, startDateTime) then
    my logWarn("skip duplicate event: " & (startDateTime as text))
    return
  end if

  tell application "Calendar"
    tell calendar targetCalendar
      set notesText to "[SF_SYNC]\ntype=shift\nsource=" & sourceTag
      make new event with properties {summary:titleText, start date:startDateTime, end date:endDateTime, description:notesText}
    end tell
  end tell
end createShiftEvent

on hasExistingEvent(targetCalendar, titleText, startDateTime)
  tell application "Calendar"
    tell calendar targetCalendar
      set matches to (every event whose summary is titleText and start date is startDateTime)
      if (count of matches) is greater than 0 then return true
    end tell
  end tell
  return false
end hasExistingEvent

on importHistoryOnce(calendarName, eventTitle, shiftStart, shiftEnd)
  set markerPath to projectRoot & historyImportedMarker
  try
    do shell script "test -f " & quoted form of markerPath
    my logInfo("history already imported; skip")
    return
  on error
    -- first run, continue
  end try

  set csvPath to projectRoot & "/History.csv"
  try
    set csvContent to do shell script "cat " & quoted form of csvPath
  on error
    my logWarn("History.csv not found, skip import")
    return
  end try

  set rowList to paragraphs of csvContent
  repeat with i from 2 to count of rowList
    set oneRow to item i of rowList
    if oneRow is not "" then
      set dateKey to my csvCol(oneRow, 1)
      if dateKey is not "" then
        set sDate to my parseDateTime(dateKey & " " & shiftStart)
        set eDate to my parseDateTime(dateKey & " " & shiftEnd)
        my createShiftEvent(calendarName, eventTitle, sDate, eDate, "history")
      end if
    end if
  end repeat

  do shell script "touch " & quoted form of markerPath
  my logInfo("history imported")
end importHistoryOnce

on generatePlannedFutureShifts(calendarName, eventTitle, shiftStart, shiftEnd, startDate, endDate)
  set startYmd to my dateToYmd(startDate)
  set endYmd to my dateToYmd(endDate)
  set plannedText to my getPlannedShiftLines(startYmd, endYmd)
  if plannedText is "" then
    my logWarn("planner returned no shifts")
    return
  end if

  set linesList to paragraphs of plannedText
  repeat with oneLine in linesList
    set lineText to contents of oneLine
    if lineText is not "" then
      set parts to my splitByPipe(lineText)
      if (count of parts) is 2 then
        set ymd to item 1 of parts
        set sourceTag to item 2 of parts
        set sDate to my parseDateTime(ymd & " " & shiftStart)
        set eDate to my parseDateTime(ymd & " " & shiftEnd)
        my createShiftEvent(calendarName, eventTitle, sDate, eDate, sourceTag)
      end if
    end if
  end repeat
end generatePlannedFutureShifts

on getPlannedShiftLines(startYmd, endYmd)
  return my runPlanner("shifts --start " & quoted form of startYmd & " --end " & quoted form of endYmd)
end getPlannedShiftLines

-- All schedule semantics live in scripts/schedule_core.py, called through
-- scripts/planner.py. Arguments are passed as shell-quoted argv values —
-- never interpolated into code.
on runPlanner(argsText)
  return do shell script "export SHIFTLY_ROOT=" & quoted form of projectRoot & " && /usr/bin/python3 " & quoted form of (projectRoot & "/scripts/planner.py") & " " & argsText
end runPlanner

on getSyncRangeYmd()
  set outText to my runPlanner("sync-range")
  set linesList to paragraphs of outText
  if (count of linesList) is less than 2 then error "sync range"
  return {item 1 of linesList, item 2 of linesList}
end getSyncRangeYmd

on splitByPipe(t)
  set AppleScript's text item delimiters to "|"
  set xs to text items of t
  set AppleScript's text item delimiters to ""
  return xs
end splitByPipe

on dateToYmd(d)
  set y to year of d as integer
  set m to my monthNumFromEnum(month of d)
  set dd to day of d as integer
  return (y as text) & "-" & my pad2(m) & "-" & my pad2(dd)
end dateToYmd

on monthNumFromEnum(m)
  if m is January then return 1
  if m is February then return 2
  if m is March then return 3
  if m is April then return 4
  if m is May then return 5
  if m is June then return 6
  if m is July then return 7
  if m is August then return 8
  if m is September then return 9
  if m is October then return 10
  if m is November then return 11
  return 12
end monthNumFromEnum

on pad2(n)
  if n < 10 then return "0" & (n as text)
  return n as text
end pad2

on readConfig()
  set outText to my runPlanner("config-summary")
  set linesList to paragraphs of outText
  if (count of linesList) < 4 then error "invalid config"
  return {calendar_name:item 1 of linesList, event_title:item 2 of linesList, default_start_time:item 3 of linesList, default_end_time:item 4 of linesList}
end readConfig

on writeMetaStatus(statusText)
  set stamp to do shell script "date '+%Y-%m-%dT%H:%M:%S%z'"
  set jsonText to "{\n  \"last_sync_at\": \"" & stamp & "\",\n  \"last_sync_status\": \"" & statusText & "\"\n}"
  do shell script "printf %s " & quoted form of jsonText & " > " & quoted form of (projectRoot & "/data/meta.json")
end writeMetaStatus

on startOfDay(d)
  set x to d
  set time of x to 0
  return x
end startOfDay

on csvCol(rowText, colIndex)
  set AppleScript's text item delimiters to ","
  set cols to text items of rowText
  set AppleScript's text item delimiters to ""
  if (count of cols) is greater than or equal to colIndex then return item colIndex of cols
  return ""
end csvCol

on parseDateTime(ymdHm)
  return my parseDateTimeFrom(current date, ymdHm)
end parseDateTime

-- baseDate is injectable so tests can simulate any "today"
-- (see scripts/test_date_rollover.applescript).
on parseDateTimeFrom(baseDate, ymdHm)
  set y to (text 1 thru 4 of ymdHm) as integer
  set m to (text 6 thru 7 of ymdHm) as integer
  set d to (text 9 thru 10 of ymdHm) as integer
  set hh to (text 12 thru 13 of ymdHm) as integer
  set mm to (text 15 thru 16 of ymdHm) as integer

  copy baseDate to dt
  -- Reset day to 1 first: if the base date is the 29th/30th/31st and the
  -- target month is shorter, setting month would overflow into the next month.
  set day of dt to 1
  set year of dt to y
  set month of dt to my monthFromNum(m)
  set day of dt to d
  set time of dt to (hh * hours) + (mm * minutes)
  return dt
end parseDateTimeFrom

on monthFromNum(mm)
  if mm is 1 then return January
  if mm is 2 then return February
  if mm is 3 then return March
  if mm is 4 then return April
  if mm is 5 then return May
  if mm is 6 then return June
  if mm is 7 then return July
  if mm is 8 then return August
  if mm is 9 then return September
  if mm is 10 then return October
  if mm is 11 then return November
  return December
end monthFromNum

on logInfo(messageText)
  my writeLog("INFO", messageText)
end logInfo

on logWarn(messageText)
  my writeLog("WARN", messageText)
end logWarn

on writeLog(levelText, messageText)
  set logPath to projectRoot & "/data/logs/sync.log"
  set timestamp to do shell script "date '+%Y-%m-%d %H:%M:%S'"
  set lineText to timestamp & " [" & levelText & "] " & messageText
  do shell script "mkdir -p " & quoted form of (projectRoot & "/data/logs")
  do shell script "printf %s\\n " & quoted form of lineText & " >> " & quoted form of logPath
end writeLog
