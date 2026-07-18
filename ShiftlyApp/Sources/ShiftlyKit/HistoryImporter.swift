import EventKit
import Foundation

/// One-time import of past calendar events (any calendar the user picks)
/// into manual_shifts.json — each event's real start/end becomes a worked
/// shift, so pay is computed from actual hours, not the rule schedule.
public enum HistoryImporter {
    public struct Summary: Equatable {
        public var imported = 0
        /// Days that had several events, merged to earliest-start…latest-end.
        public var mergedDays = 0
        /// Days skipped because manual_shifts.json already has them.
        public var skippedExisting = 0

        public init() {}
    }

    /// Pure mapping: events strictly before `cutoff` (YYYY-MM-DD) →
    /// manual shifts. Multiple events on one day merge into one span.
    public static func shifts(
        from events: [CalendarEventInfo],
        before cutoff: String
    ) -> (shifts: [ManualShift], mergedDays: Int) {
        var byDate: [String: (start: Date, end: Date, count: Int)] = [:]
        for event in events {
            let day = event.startDay
            guard day < cutoff else { continue }
            if let existing = byDate[day] {
                byDate[day] = (
                    start: min(existing.start, event.start),
                    end: max(existing.end, event.end),
                    count: existing.count + 1
                )
            } else {
                byDate[day] = (event.start, event.end, 1)
            }
        }
        let shifts = byDate
            .sorted { $0.key < $1.key }
            .map { day, span in
                ManualShift(
                    date: day,
                    start: SyncFingerprint.hhmmString(for: span.start),
                    end: SyncFingerprint.hhmmString(for: span.end),
                    source: "import"
                )
            }
        let merged = byDate.values.filter { $0.count > 1 }.count
        return (shifts, merged)
    }

    /// Merge imported shifts into the store, never touching existing dates
    /// (readbacks and earlier imports win). Returns the summary.
    @discardableResult
    public static func apply(
        _ imported: [ManualShift],
        mergedDays: Int,
        to store: DataStore
    ) throws -> Summary {
        var summary = Summary()
        summary.mergedDays = mergedDays
        var manuals = store.loadManualShifts()
        let existingDates = Set(manuals.map(\.date))
        for shift in imported {
            if existingDates.contains(shift.date) {
                summary.skippedExisting += 1
            } else {
                manuals.append(shift)
                summary.imported += 1
            }
        }
        try store.saveManualShifts(manuals.sorted { $0.date < $1.date })
        return summary
    }

    /// All calendars visible to the event store (for the picker UI).
    public static func calendars(in eventStore: EKEventStore) -> [(id: String, title: String)] {
        eventStore.calendars(for: .event)
            .map { ($0.calendarIdentifier, $0.title) }
            .sorted { $0.1 < $1.1 }
    }

    /// Fetch every event of one calendar from `yearsBack` years ago until
    /// `until`, chunked yearly (EventKit predicates cap at ~4 years).
    public static func fetchEvents(
        calendarID: String,
        in eventStore: EKEventStore,
        until: Date,
        yearsBack: Int = 6
    ) -> [CalendarEventInfo] {
        guard let calendar = eventStore.calendar(withIdentifier: calendarID) else { return [] }
        let store = EKCalendarStore(eventStore: eventStore, calendar: calendar)
        var events: [CalendarEventInfo] = []
        var chunkEnd = until
        for _ in 0..<yearsBack {
            guard let chunkStart = Calendar.current.date(byAdding: .year, value: -1, to: chunkEnd) else { break }
            let window = DateInterval(start: chunkStart, end: chunkEnd)
            events.append(contentsOf: (try? store.events(in: window)) ?? [])
            chunkEnd = chunkStart
        }
        // Chunk edges can duplicate boundary events; dedupe by identifier.
        var seen = Set<String>()
        return events.filter { seen.insert($0.id).inserted }
    }
}
