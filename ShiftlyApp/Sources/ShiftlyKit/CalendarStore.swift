import Foundation

/// Abstraction over the calendar so the sync engine and its tests never
/// depend on EventKit. The production implementation (EKCalendarStore)
/// arrives with the EventKit integration.
public protocol CalendarStore {
    /// All events in the target calendar whose start falls inside the window.
    func events(in window: DateInterval) throws -> [CalendarEventInfo]
    /// Create an event; returns its stable identifier.
    func createEvent(title: String, start: Date, end: Date) throws -> String
    func updateEvent(id: String, title: String, start: Date, end: Date) throws
    func deleteEvent(id: String) throws
}

/// In-memory store for tests and dry runs.
public final class InMemoryCalendarStore: CalendarStore {
    public private(set) var storage: [String: CalendarEventInfo] = [:]
    public private(set) var writeCount = 0
    private var nextID = 1

    public init(events: [CalendarEventInfo] = []) {
        for e in events {
            storage[e.id] = e
        }
    }

    public func events(in window: DateInterval) throws -> [CalendarEventInfo] {
        storage.values
            .filter { window.contains($0.start) }
            .sorted { $0.start < $1.start }
    }

    public func createEvent(title: String, start: Date, end: Date) throws -> String {
        writeCount += 1
        let id = "mem-\(nextID)"
        nextID += 1
        storage[id] = CalendarEventInfo(id: id, title: title, start: start, end: end)
        return id
    }

    public func updateEvent(id: String, title: String, start: Date, end: Date) throws {
        writeCount += 1
        guard let old = storage[id] else { return }
        storage[id] = CalendarEventInfo(id: id, title: title, start: start, end: end, notes: old.notes)
    }

    public func deleteEvent(id: String) throws {
        writeCount += 1
        storage[id] = nil
    }

    public func resetWriteCount() {
        writeCount = 0
    }

    /// Test helper: mutate an event as if the user edited it in Calendar.
    public func userEdit(id: String, start: Date, end: Date) {
        guard let old = storage[id] else { return }
        storage[id] = CalendarEventInfo(id: id, title: old.title, start: start, end: end, notes: old.notes)
    }

    /// Test helper: delete without counting as a sync write.
    public func userDelete(id: String) {
        storage[id] = nil
    }
}
