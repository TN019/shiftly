import EventKit
import Foundation

/// One-time import of past calendar events (any calendar the user picks)
/// into manual_shifts.json — each event's real start/end becomes a worked
/// shift, so pay is computed from actual hours, not the rule schedule.
/// All-day events count as shifts at the configured default times, and
/// recurring events contribute every past occurrence (unlike the sync
/// engine, which manages only its own timed one-off events).
public enum HistoryImporter {
    public struct Summary: Equatable {
        public var imported = 0
        /// Days that had several events, merged to earliest-start…latest-end.
        public var mergedDays = 0
        /// Days skipped because manual_shifts.json already has them.
        public var skippedExisting = 0

        public init() {}
    }

    /// A past calendar event as the importer sees it. Occurrences of a
    /// recurring event arrive as separate values (same id, different start).
    public struct PastEvent: Equatable {
        public let id: String
        public let start: Date
        public let end: Date
        public let isAllDay: Bool
        public let title: String

        public init(id: String, start: Date, end: Date, isAllDay: Bool, title: String = "") {
            self.id = id
            self.start = start
            self.end = end
            self.isAllDay = isAllDay
            self.title = title
        }

        public var startDay: String { SyncFingerprint.dayString(for: start) }
    }

    /// Pure mapping: events strictly before `cutoff` (YYYY-MM-DD) →
    /// manual shifts. Multiple timed events on one day merge into one span;
    /// a day with only all-day events uses the configured default times.
    public static func shifts(
        from events: [PastEvent],
        before cutoff: String,
        defaultStart: String,
        defaultEnd: String
    ) -> (shifts: [ManualShift], mergedDays: Int) {
        var timed: [String: (start: Date, end: Date, count: Int)] = [:]
        var allDayDays = Set<String>()
        for event in events {
            let day = event.startDay
            guard day < cutoff else { continue }
            if event.isAllDay {
                allDayDays.insert(day)
                continue
            }
            if let existing = timed[day] {
                timed[day] = (
                    start: min(existing.start, event.start),
                    end: max(existing.end, event.end),
                    count: existing.count + 1
                )
            } else {
                timed[day] = (event.start, event.end, 1)
            }
        }
        var shifts = timed.map { day, span in
            ManualShift(
                date: day,
                start: SyncFingerprint.hhmmString(for: span.start),
                end: SyncFingerprint.hhmmString(for: span.end),
                source: "import"
            )
        }
        // Timed events win over an all-day marker on the same day.
        shifts += allDayDays
            .filter { timed[$0] == nil }
            .map { ManualShift(date: $0, start: defaultStart, end: defaultEnd, source: "import") }
        shifts.sort { $0.date < $1.date }
        let merged = timed.values.filter { $0.count > 1 }.count
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

    /// Map calendar events (e.g. a subscribed public-holidays calendar) to
    /// holiday entries: one per day, named after the event title. Days
    /// already present in `existing` are kept as they are.
    public static func holidays(
        from events: [PastEvent],
        existing: [HolidayItem]
    ) -> (merged: [HolidayItem], added: Int) {
        let known = Set(existing.map(\.date))
        var byDate: [String: String] = [:]
        for event in events {
            let day = event.startDay
            guard !known.contains(day), byDate[day] == nil else { continue }
            byDate[day] = event.title
        }
        let added = byDate
            .sorted { $0.key < $1.key }
            .map { HolidayItem(date: $0.key, name: $0.value) }
        return ((existing + added).sorted { $0.date < $1.date }, added.count)
    }

    /// All calendars visible to the event store (for the picker UI).
    public static func calendars(in eventStore: EKEventStore) -> [(id: String, title: String)] {
        eventStore.calendars(for: .event)
            .map { ($0.calendarIdentifier, $0.title) }
            .sorted { $0.1 < $1.1 }
    }

    /// Fetch every event of one calendar from `yearsBack` years ago until
    /// `until`, chunked yearly (EventKit predicates cap at ~4 years).
    /// Includes all-day events and expanded recurring occurrences.
    public static func fetchEvents(
        calendarID: String,
        in eventStore: EKEventStore,
        until: Date,
        yearsBack: Int = 6
    ) -> [PastEvent] {
        guard let calendar = eventStore.calendar(withIdentifier: calendarID) else { return [] }
        var events: [PastEvent] = []
        var chunkEnd = until
        for _ in 0..<yearsBack {
            guard let chunkStart = Calendar.current.date(byAdding: .year, value: -1, to: chunkEnd) else { break }
            let predicate = eventStore.predicateForEvents(
                withStart: chunkStart, end: chunkEnd, calendars: [calendar]
            )
            for event in eventStore.events(matching: predicate) {
                guard let id = event.eventIdentifier,
                      let start = event.startDate,
                      let end = event.endDate else { continue }
                events.append(PastEvent(
                    id: id, start: start, end: end,
                    isAllDay: event.isAllDay, title: event.title ?? ""
                ))
            }
            chunkEnd = chunkStart
        }
        // Occurrences of a recurring event share an eventIdentifier, so key
        // on id + start: chunk-edge duplicates drop, occurrences survive.
        var seen = Set<String>()
        return events.filter { seen.insert("\($0.id)#\($0.start.timeIntervalSince1970)").inserted }
    }
}
