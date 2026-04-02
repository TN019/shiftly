use scripting additions

property projectRoot : ""
property historyImportedMarker : "/data/meta.history_imported"

on getProjectRoot()
	try
		set e to do shell script "if [ -n \"$SHIFTY_ROOT\" ]; then printf %s \"$SHIFTY_ROOT\"; elif [ -n \"$SHIFTFLOW_ROOT\" ]; then printf %s \"$SHIFTFLOW_ROOT\"; fi"
		if e is not "" then return e
	end try
	try
		set mePath to POSIX path of (path to me)
		set scriptsDir to do shell script "/usr/bin/dirname " & quoted form of mePath
		set rootDir to do shell script "/usr/bin/dirname " & quoted form of scriptsDir
		return rootDir
	on error errMsg
		error ("Shifty: could not resolve project root. Set SHIFTY_ROOT or SHIFTFLOW_ROOT. " & errMsg) number -1700
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
  return my runPlannerPython(startYmd, endYmd)
end getPlannedShiftLines

on getRangeYmdForPeriod(periodKind)
  set py to "import datetime" & linefeed & ¬
    "today=datetime.date.today()" & linefeed & ¬
    "if '" & periodKind & "'=='week':" & linefeed & ¬
    "  start=today-datetime.timedelta(days=today.weekday())" & linefeed & ¬
    "  end=start+datetime.timedelta(days=6)" & linefeed & ¬
    "elif '" & periodKind & "'=='month':" & linefeed & ¬
    "  start=datetime.date(today.year,today.month,1)" & linefeed & ¬
    "  if today.month==12:" & linefeed & ¬
    "    end=datetime.date(today.year+1,1,1)-datetime.timedelta(days=1)" & linefeed & ¬
    "  else:" & linefeed & ¬
    "    end=datetime.date(today.year,today.month+1,1)-datetime.timedelta(days=1)" & linefeed & ¬
    "else:" & linefeed & ¬
    "  start=today; end=today" & linefeed & ¬
    "print(start.isoformat())" & linefeed & ¬
    "print(end.isoformat())" & linefeed
  set outText to do shell script "/usr/bin/python3 -c " & quoted form of py
  set linesList to paragraphs of outText
  if (count of linesList) < 2 then error "report range"
  return {item 1 of linesList, item 2 of linesList}
end getRangeYmdForPeriod

on getSyncRangeYmd()
  set py to "import os,datetime" & linefeed & ¬
    "import json,pathlib" & linefeed & ¬
    "root=pathlib.Path(os.environ['SHIFTFLOW_ROOT'])" & linefeed & ¬
    "swaps=json.loads((root/'data/swaps.json').read_text()) if (root/'data/swaps.json').exists() else []" & linefeed & ¬
    "leave=json.loads((root/'data/leave.json').read_text()) if (root/'data/leave.json').exists() else []" & linefeed & ¬
    "today=datetime.date.today()" & linefeed & ¬
    "mode=(os.environ.get('SHIFTY_SYNC_MODE') or os.environ.get('SHIFTFLOW_SYNC_MODE') or '')" & linefeed & ¬
    "if mode=='next_month':" & linefeed & ¬
    "  if today.month==12:" & linefeed & ¬
    "    first=datetime.date(today.year+1,1,1)" & linefeed & ¬
    "  else:" & linefeed & ¬
    "    first=datetime.date(today.year,today.month+1,1)" & linefeed & ¬
    "  if first.month==12:" & linefeed & ¬
    "    last=datetime.date(first.year+1,1,1)-datetime.timedelta(days=1)" & linefeed & ¬
    "  else:" & linefeed & ¬
    "    last=datetime.date(first.year,first.month+1,1)-datetime.timedelta(days=1)" & linefeed & ¬
    "else:" & linefeed & ¬
    "  first=today" & linefeed & ¬
    "  if today.month==12:" & linefeed & ¬
    "    last=datetime.date(today.year+1,1,1)-datetime.timedelta(days=1)" & linefeed & ¬
    "  else:" & linefeed & ¬
    "    last=datetime.date(today.year,today.month+1,1)-datetime.timedelta(days=1)" & linefeed & ¬
    "def date_or_none(s):" & linefeed & ¬
    "  try: return datetime.date.fromisoformat(s)" & linefeed & ¬
    "  except Exception: return None" & linefeed & ¬
    "max_override=last" & linefeed & ¬
    "for s in swaps:" & linefeed & ¬
    "  t=date_or_none(s.get('to_date',''))" & linefeed & ¬
    "  if t and t>max_override: max_override=t" & linefeed & ¬
    "for lv in leave:" & linefeed & ¬
    "  e=date_or_none(lv.get('end_date',''))" & linefeed & ¬
    "  if e and e>max_override: max_override=e" & linefeed & ¬
    "last=max_override" & linefeed & ¬
    "print(first.isoformat())" & linefeed & ¬
    "print(last.isoformat())" & linefeed
  set outText to do shell script "export SHIFTY_ROOT=" & quoted form of projectRoot & " && export SHIFTFLOW_ROOT=" & quoted form of projectRoot & " && /usr/bin/python3 -c " & quoted form of py
  set linesList to paragraphs of outText
  if (count of linesList) is less than 2 then error "sync range"
  return {item 1 of linesList, item 2 of linesList}
end getSyncRangeYmd

on runPlannerPython(startYmd, endYmd)
  set py to "import json,datetime,pathlib,os" & linefeed & ¬
    "root=pathlib.Path(os.environ['SHIFTFLOW_ROOT'])" & linefeed & ¬
    "cfg=json.loads((root/'data/config.json').read_text())" & linefeed & ¬
    "swaps=json.loads((root/'data/swaps.json').read_text())" & linefeed & ¬
    "leave=json.loads((root/'data/leave.json').read_text())" & linefeed & ¬
    "start=datetime.date.fromisoformat('" & startYmd & "')" & linefeed & ¬
    "end=datetime.date.fromisoformat('" & endYmd & "')" & linefeed & ¬
    "wk={'MO':0,'TU':1,'WE':2,'TH':3,'FR':4,'SA':5,'SU':6}" & linefeed & ¬
    "rules=sorted(cfg.get('rules',[]),key=lambda r:r.get('effective_from',''))" & linefeed & ¬
    "def rule_for(d):" & linefeed & ¬
    "  c=None" & linefeed & ¬
    "  for r in rules:" & linefeed & ¬
    "    ef=r.get('effective_from')" & linefeed & ¬
    "    if not ef: continue" & linefeed & ¬
    "    if datetime.date.fromisoformat(ef)<=d: c=r" & linefeed & ¬
    "  return c" & linefeed & ¬
    "shifts=set()" & linefeed & ¬
    "d=start" & linefeed & ¬
    "while d<=end:" & linefeed & ¬
    "  r=rule_for(d)" & linefeed & ¬
    "  if r:" & linefeed & ¬
    "    wd={wk[x] for x in r.get('workdays',[]) if x in wk}" & linefeed & ¬
    "    if d.weekday() in wd: shifts.add(d)" & linefeed & ¬
    "  d+=datetime.timedelta(days=1)" & linefeed & ¬
    "for s in swaps:" & linefeed & ¬
    "  fd=s.get('from_date'); td=s.get('to_date')" & linefeed & ¬
    "  if not fd or not td: continue" & linefeed & ¬
    "  f=datetime.date.fromisoformat(fd); t=datetime.date.fromisoformat(td)" & linefeed & ¬
    "  if f in shifts: shifts.remove(f)" & linefeed & ¬
    "  if start<=t<=end: shifts.add(t)" & linefeed & ¬
    "for lv in leave:" & linefeed & ¬
    "  sd=lv.get('start_date'); ed=lv.get('end_date')" & linefeed & ¬
    "  if not sd or not ed: continue" & linefeed & ¬
    "  a=datetime.date.fromisoformat(sd); b=datetime.date.fromisoformat(ed)" & linefeed & ¬
    "  if b<a: a,b=b,a" & linefeed & ¬
    "  x=a" & linefeed & ¬
    "  while x<=b:" & linefeed & ¬
    "    if x in shifts: shifts.remove(x)" & linefeed & ¬
    "    x+=datetime.timedelta(days=1)" & linefeed & ¬
    "for d in sorted(shifts): print(d.isoformat()+'|auto')" & linefeed

  return do shell script "export SHIFTY_ROOT=" & quoted form of projectRoot & " && export SHIFTFLOW_ROOT=" & quoted form of projectRoot & " && /usr/bin/python3 -c " & quoted form of py
end runPlannerPython

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
  set py to "import json,pathlib,os;root=pathlib.Path(os.environ['SHIFTFLOW_ROOT']);cfg=json.loads((root/'data/config.json').read_text());print(cfg.get('calendar_name','Shifts'));print(cfg.get('event_title','Work Schedule'));print(cfg.get('default_start_time','10:00'));print(cfg.get('default_end_time','18:30'))"
  set outText to do shell script "export SHIFTY_ROOT=" & quoted form of projectRoot & " && export SHIFTFLOW_ROOT=" & quoted form of projectRoot & " && /usr/bin/python3 -c " & quoted form of py
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
  set y to (text 1 thru 4 of ymdHm) as integer
  set m to (text 6 thru 7 of ymdHm) as integer
  set d to (text 9 thru 10 of ymdHm) as integer
  set hh to (text 12 thru 13 of ymdHm) as integer
  set mm to (text 15 thru 16 of ymdHm) as integer

  set dt to current date
  set year of dt to y
  set month of dt to my monthFromNum(m)
  set day of dt to d
  set time of dt to (hh * hours) + (mm * minutes)
  return dt
end parseDateTime

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
