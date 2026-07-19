import Foundation

/// Pure three-way diff between the desired schedule (planned), the calendar
/// (events) and the last-sync memory (state). See docs/SYNC_DESIGN.md §3–§5.
///
/// The engine never talks to EventKit or the filesystem: callers fetch
/// inputs, execute the returned `SyncPlan`, apply readbacks to the data
/// files, re-plan, and run a second pass that must converge to a no-op.
///
/// Policies encoded here:
/// - Only events recorded in the state (or claimed below) are ever touched.
/// - Calendar wins when the event changed since our last write (readback).
/// - Claiming (state lost / legacy [SF_SYNC] migration): an unmanaged event
///   whose title matches on a planned day is adopted; since nobody can tell
///   who changed what without state, the planned schedule wins and the event
///   is corrected — this keeps recovery deterministic and duplicate-free.
/// - Legacy-marked events on days with no planned shift are deleted, which
///   matches the old engine's clear-and-regenerate semantics.
/// - User-created events with the configured shift title become manual
///   shifts; anything else is reported and left untouched.
public enum SyncEngine {
    public static func plan(
        planned: [PlannedShift],
        events: [CalendarEventInfo],
        state: SyncStateFile,
        eventTitle: String
    ) -> SyncPlan {
        var plan = SyncPlan()

        let eventsByID = Dictionary(events.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        // State-loss guard: several events tracked and *none* of them exist
        // any more means the calendar was deleted, recreated or swapped —
        // not the user deleting individual shifts. Recover by dropping the
        // stale state (re-claim/create below) instead of reading back a
        // leave for every planned day. A single missing event is still an
        // honest per-day deletion.
        var stateEntries = state.entries
        if stateEntries.count >= 2,
           !stateEntries.contains(where: { eventsByID[$0.event_id] != nil }) {
            stateEntries = []
        }

        let plannedByDate = Dictionary(planned.map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })
        var entriesByDate = Dictionary(stateEntries.map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })
        let managedIDs = Set(stateEntries.map(\.event_id))

        // -- Claim pass: adopt unmanaged shift-title events on planned days
        //    that have no entry yet (state loss or legacy migration).
        var claimedIDs: Set<String> = []
        for event in events where !managedIDs.contains(event.id) {
            guard event.title == eventTitle else { continue }
            let day = event.startDay
            if plannedByDate[day] != nil, entriesByDate[day] == nil {
                let claimed = SyncEntry(
                    date: day,
                    kind: plannedByDate[day]!.kind,
                    event_id: event.id,
                    // Planned wins on recovery: record the event as if we
                    // wrote it, so a content mismatch below becomes a
                    // Shiftly-side correction rather than a readback.
                    fingerprint: event.fingerprint
                )
                entriesByDate[day] = claimed
                claimedIDs.insert(event.id)
            }
        }

        // -- Planned side: create / update / detect calendar-side edits.
        for shift in planned.sorted(by: { $0.date < $1.date }) {
            guard let entry = entriesByDate[shift.date] else {
                plan.creates.append(shift)
                continue
            }
            guard let event = eventsByID[entry.event_id] else {
                // We wrote it, it's gone: the user deleted the shift.
                plan.readbacks.append(.deleted(date: shift.date))
                entriesByDate[shift.date] = nil
                continue
            }
            if event.fingerprint == entry.fingerprint {
                // Calendar untouched since our last write.
                if shift.fingerprint != entry.fingerprint {
                    plan.updates.append(.init(eventID: event.id, shift: shift))
                } else {
                    plan.keptEntries.append(entry)
                }
            } else {
                // The user edited this event: calendar wins.
                let eventDay = event.startDay
                if eventDay == shift.date {
                    plan.readbacks.append(.retimed(
                        date: shift.date,
                        eventID: event.id,
                        startHHMM: SyncFingerprint.hhmmString(for: event.start),
                        endHHMM: SyncFingerprint.hhmmString(for: event.end)
                    ))
                } else {
                    plan.readbacks.append(.moved(fromDate: shift.date, toDate: eventDay, eventID: event.id))
                }
                // Keep the entry pointing at the event under its current
                // content; the post-readback pass reconciles the rest.
                plan.keptEntries.append(SyncEntry(
                    date: eventDay,
                    kind: entry.kind,
                    event_id: event.id,
                    fingerprint: event.fingerprint
                ))
            }
            entriesByDate[shift.date] = nil
        }

        // -- State side: entries whose day is no longer planned.
        for entry in entriesByDate.values.sorted(by: { $0.date < $1.date }) {
            guard let event = eventsByID[entry.event_id] else {
                continue // gone on both sides; drop silently
            }
            if event.fingerprint == entry.fingerprint {
                // Shiftly cancelled the shift (leave etc.); calendar untouched.
                plan.deletes.append(.init(eventID: event.id, date: entry.date))
            } else {
                // Shiftly cancelled it, but the user also edited the event:
                // calendar wins — whatever the user shaped it into is a
                // shift they want. Treat it as a manual shift where it now is.
                plan.readbacks.append(.newManual(
                    date: event.startDay,
                    eventID: event.id,
                    startHHMM: SyncFingerprint.hhmmString(for: event.start),
                    endHHMM: SyncFingerprint.hhmmString(for: event.end)
                ))
                plan.keptEntries.append(SyncEntry(
                    date: event.startDay,
                    kind: .manual,
                    event_id: event.id,
                    fingerprint: event.fingerprint
                ))
            }
        }

        // -- Calendar side: events we do not manage.
        let keptIDs = Set(plan.keptEntries.map(\.event_id))
        for event in events.sorted(by: { $0.start < $1.start }) {
            if managedIDs.contains(event.id) || claimedIDs.contains(event.id) || keptIDs.contains(event.id) {
                continue
            }
            if event.hasLegacyMarker {
                // Old engine's events with no matching plan: it would have
                // cleared and regenerated them, so removing is the faithful
                // migration of stale ones.
                plan.deletes.append(.init(eventID: event.id, date: event.startDay))
            } else if event.title == eventTitle {
                plan.readbacks.append(.newManual(
                    date: event.startDay,
                    eventID: event.id,
                    startHHMM: SyncFingerprint.hhmmString(for: event.start),
                    endHHMM: SyncFingerprint.hhmmString(for: event.end)
                ))
                plan.keptEntries.append(SyncEntry(
                    date: event.startDay,
                    kind: .manual,
                    event_id: event.id,
                    fingerprint: event.fingerprint
                ))
            } else {
                plan.ignoredForeign.append(event)
            }
        }

        return plan
    }

    /// Execute the calendar writes of a plan against a store and return the
    /// entries for the resulting state file (kept + created + updated).
    public static func execute(
        _ plan: SyncPlan,
        on store: CalendarStore
    ) throws -> [SyncEntry] {
        var entries = plan.keptEntries
        for creation in plan.creates {
            let id = try store.createEvent(title: creation.title, start: creation.start, end: creation.end)
            entries.append(SyncEntry(
                date: creation.date, kind: creation.kind,
                event_id: id, fingerprint: creation.fingerprint
            ))
        }
        for update in plan.updates {
            try store.updateEvent(
                id: update.eventID,
                title: update.shift.title,
                start: update.shift.start,
                end: update.shift.end
            )
            entries.append(SyncEntry(
                date: update.shift.date, kind: update.shift.kind,
                event_id: update.eventID, fingerprint: update.shift.fingerprint
            ))
        }
        for deletion in plan.deletes {
            try store.deleteEvent(id: deletion.eventID)
        }
        return entries.sorted { $0.date < $1.date }
    }
}

/// Builds concrete shift times from a day + HH:MM strings, handling
/// overnight shifts (end <= start rolls into the next day).
public enum ShiftTimeBuilder {
    public static func makeShift(
        date: String,
        kind: ShiftKind,
        title: String,
        startHHMM: String,
        endHHMM: String,
        calendar: Calendar = .current
    ) -> PlannedShift? {
        guard let dayStart = day(from: date, calendar: calendar),
              let s = apply(hhmm: startHHMM, to: dayStart, calendar: calendar),
              var e = apply(hhmm: endHHMM, to: dayStart, calendar: calendar) else {
            return nil
        }
        if e <= s {
            guard let next = calendar.date(byAdding: .day, value: 1, to: e) else { return nil }
            e = next
        }
        return PlannedShift(date: date, kind: kind, title: title, start: s, end: e)
    }

    private static func day(from ymd: String, calendar: Calendar) -> Date? {
        let parts = ymd.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var comps = DateComponents()
        comps.year = parts[0]
        comps.month = parts[1]
        comps.day = parts[2]
        return calendar.date(from: comps)
    }

    private static func apply(hhmm: String, to dayStart: Date, calendar: Calendar) -> Date? {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: dayStart)
    }
}
