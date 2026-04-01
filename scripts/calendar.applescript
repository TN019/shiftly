on ensureCalendar(calendarName)
  tell application "Calendar"
    if not (exists calendar calendarName) then
      make new calendar with properties {name:calendarName}
    end if
  end tell
end ensureCalendar

on clearSyncEvents(calendarName, startDate, endDate)
  tell application "Calendar"
    tell calendar calendarName
      set candidateEvents to (every event whose start date ≥ startDate and start date ≤ endDate)
      repeat with ev in candidateEvents
        set evNotes to ""
        try
          set evNotes to (description of ev as text)
        end try
        if evNotes contains "[SF_SYNC]" then
          delete ev
        end if
      end repeat
    end tell
  end tell
end clearSyncEvents

on createShiftEvent(calendarName, titleText, startDateTime, endDateTime, sourceTag)
  tell application "Calendar"
    tell calendar calendarName
      set notesText to "[SF_SYNC]\ntype=shift\nsource=" & sourceTag
      make new event with properties {summary:titleText, start date:startDateTime, end date:endDateTime, description:notesText}
    end tell
  end tell
end createShiftEvent
