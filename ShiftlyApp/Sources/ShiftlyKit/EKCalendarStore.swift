import EventKit
import Foundation

public enum CalendarAccess {
    case granted
    case denied
    case notDetermined

    public static var current: CalendarAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined:
            return .notDetermined
        case .fullAccess, .authorized:
            return .granted
        default:
            return .denied
        }
    }

    /// Requests calendar write access (Full Access on macOS 14+, the legacy
    /// prompt on macOS 13). Returns whether access is granted.
    public static func request(using store: EKEventStore) async -> Bool {
        if #available(macOS 14.0, *) {
            return (try? await store.requestFullAccessToEvents()) ?? false
        }
        return await withCheckedContinuation { cont in
            store.requestAccess(to: .event) { granted, _ in
                cont.resume(returning: granted)
            }
        }
    }

    /// Deep link to the Calendars privacy pane in System Settings.
    public static let settingsURLString =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
}

/// EventKit-backed CalendarStore. Construction requires granted access;
/// use `CalendarAccess.request` first.
public final class EKCalendarStore: CalendarStore {
    private let eventStore: EKEventStore
    private let calendar: EKCalendar

    public init(eventStore: EKEventStore, calendar: EKCalendar) {
        self.eventStore = eventStore
        self.calendar = calendar
    }

    /// Picks which calendar to sync into. The id remembered from the last
    /// sync wins while its calendar still carries the configured name, so
    /// duplicate names (or unstable calendar ordering) cannot silently
    /// switch calendars between runs — which would make every tracked event
    /// look user-deleted. Returns nil when a new calendar must be created.
    public static func selectCalendarID(
        preferredID: String?,
        name: String,
        candidates: [(id: String, title: String)]
    ) -> String? {
        if let id = preferredID, candidates.contains(where: { $0.id == id && $0.title == name }) {
            return id
        }
        return candidates.first(where: { $0.title == name })?.id
    }

    /// Finds the calendar by remembered id (see `selectCalendarID`), then by
    /// name, creating it in the default source when missing.
    public static func locateOrCreateCalendar(
        named name: String,
        in eventStore: EKEventStore,
        preferredID: String? = nil
    ) throws -> EKCalendar {
        let calendars = eventStore.calendars(for: .event)
        if let id = selectCalendarID(
            preferredID: preferredID,
            name: name,
            candidates: calendars.map { ($0.calendarIdentifier, $0.title) }
        ), let existing = calendars.first(where: { $0.calendarIdentifier == id }) {
            return existing
        }
        let calendar = EKCalendar(for: .event, eventStore: eventStore)
        calendar.title = name
        guard let source = eventStore.defaultCalendarForNewEvents?.source
            ?? eventStore.sources.first(where: { $0.sourceType == .local })
            ?? eventStore.sources.first else {
            throw SyncFailure("no calendar source available to create \"\(name)\"")
        }
        calendar.source = source
        try eventStore.saveCalendar(calendar, commit: true)
        return calendar
    }

    public func events(in window: DateInterval) throws -> [CalendarEventInfo] {
        // EventKit predicates silently cap at ~4 years; the window now spans
        // the whole schedule history, so fetch in yearly chunks and dedupe
        // boundary events by id.
        var raw: [EKEvent] = []
        var chunkStart = window.start
        while chunkStart < window.end {
            let chunkEnd = min(
                Calendar.current.date(byAdding: .year, value: 1, to: chunkStart) ?? window.end,
                window.end
            )
            let predicate = eventStore.predicateForEvents(
                withStart: chunkStart, end: chunkEnd, calendars: [calendar]
            )
            raw.append(contentsOf: eventStore.events(matching: predicate))
            chunkStart = chunkEnd
        }
        var seen = Set<String>()
        return raw.compactMap { event in
            guard let id = event.eventIdentifier,
                  let start = event.startDate,
                  let end = event.endDate,
                  // The engine ignores all-day and recurring events; Shiftly
                  // never creates them (design §7).
                  !event.isAllDay, !event.hasRecurrenceRules,
                  seen.insert(id).inserted else {
                return nil
            }
            return CalendarEventInfo(
                id: id,
                title: event.title ?? "",
                start: start,
                end: end,
                notes: event.notes
            )
        }
    }

    public func createEvent(title: String, start: Date, end: Date) throws -> String {
        let event = EKEvent(eventStore: eventStore)
        event.calendar = calendar
        event.title = title
        event.startDate = start
        event.endDate = end
        try eventStore.save(event, span: .thisEvent, commit: true)
        guard let id = event.eventIdentifier else {
            throw SyncFailure("event saved but has no identifier")
        }
        return id
    }

    public func updateEvent(id: String, title: String, start: Date, end: Date) throws {
        guard let event = eventStore.event(withIdentifier: id) else {
            throw SyncFailure("event \(id) not found for update")
        }
        event.title = title
        event.startDate = start
        event.endDate = end
        try eventStore.save(event, span: .thisEvent, commit: true)
    }

    public func deleteEvent(id: String) throws {
        guard let event = eventStore.event(withIdentifier: id) else {
            return // already gone
        }
        try eventStore.remove(event, span: .thisEvent, commit: true)
    }
}
