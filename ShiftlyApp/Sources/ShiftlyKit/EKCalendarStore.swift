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

    /// Finds the calendar by name, creating it in the default source when
    /// missing.
    public static func locateOrCreateCalendar(
        named name: String,
        in eventStore: EKEventStore
    ) throws -> EKCalendar {
        if let existing = eventStore.calendars(for: .event).first(where: { $0.title == name }) {
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
        let predicate = eventStore.predicateForEvents(
            withStart: window.start,
            end: window.end,
            calendars: [calendar]
        )
        return eventStore.events(matching: predicate).compactMap { event in
            guard let id = event.eventIdentifier,
                  let start = event.startDate,
                  let end = event.endDate,
                  // The engine ignores all-day and recurring events; Shiftly
                  // never creates them (design §7).
                  !event.isAllDay, !event.hasRecurrenceRules else {
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
