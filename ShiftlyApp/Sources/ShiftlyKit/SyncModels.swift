import CryptoKit
import Foundation

/// Origin of a managed shift.
public enum ShiftKind: String, Codable, Equatable {
    /// Generated from rules + swaps + leave by the planner.
    case auto
    /// Created by the user directly in Apple Calendar and read back.
    case manual
}

/// One shift Shiftly wants on the calendar.
public struct PlannedShift: Equatable {
    /// Owning day, YYYY-MM-DD (start day for overnight shifts).
    public let date: String
    public let kind: ShiftKind
    public let title: String
    public let start: Date
    public let end: Date

    public init(date: String, kind: ShiftKind, title: String, start: Date, end: Date) {
        self.date = date
        self.kind = kind
        self.title = title
        self.start = start
        self.end = end
    }

    public var fingerprint: String {
        SyncFingerprint.make(title: title, start: start, end: end)
    }
}

/// Snapshot of a calendar event, decoupled from EventKit for testability.
public struct CalendarEventInfo: Equatable {
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let notes: String?

    public init(id: String, title: String, start: Date, end: Date, notes: String? = nil) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.notes = notes
    }

    public var fingerprint: String {
        SyncFingerprint.make(title: title, start: start, end: end)
    }

    /// Written by the legacy AppleScript engine; used once for migration.
    public var hasLegacyMarker: Bool {
        notes?.contains("[SF_SYNC]") == true
    }

    /// Local-calendar day of the event start, YYYY-MM-DD.
    public var startDay: String {
        SyncFingerprint.dayString(for: start)
    }
}

public enum SyncFingerprint {
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    public static func make(title: String, start: Date, end: Date) -> String {
        let payload = "\(iso.string(from: start))|\(iso.string(from: end))|\(title)"
        return SHA256.hash(data: Data(payload.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    public static func dayString(for date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// HH:MM in the local calendar, for readback records.
    public static func hhmmString(for date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}

/// One managed event in sync_state.json.
public struct SyncEntry: Codable, Equatable {
    public var date: String
    public var kind: ShiftKind
    public var event_id: String
    public var fingerprint: String

    public init(date: String, kind: ShiftKind, event_id: String, fingerprint: String) {
        self.date = date
        self.kind = kind
        self.event_id = event_id
        self.fingerprint = fingerprint
    }
}

/// Contents of data/sync_state.json. Engine-private state; not user-editable.
public struct SyncStateFile: Codable, Equatable {
    public var version: Int
    public var calendar_id: String?
    public var last_sync_at: String?
    public var entries: [SyncEntry]

    public init(version: Int = 1, calendar_id: String? = nil, last_sync_at: String? = nil, entries: [SyncEntry] = []) {
        self.version = version
        self.calendar_id = calendar_id
        self.last_sync_at = last_sync_at
        self.entries = entries
    }

    public static let empty = SyncStateFile()
}

/// A calendar-side change translated back into Shiftly data (design §4).
public enum ReadbackChange: Equatable {
    /// Event dragged to another day → swap record.
    case moved(fromDate: String, toDate: String, eventID: String)
    /// Same-day time change → per-day time override.
    case retimed(date: String, eventID: String, startHHMM: String, endHHMM: String)
    /// Event deleted by the user → day off record.
    case deleted(date: String)
    /// Shift-style event created by the user → manual shift.
    case newManual(date: String, eventID: String, startHHMM: String, endHHMM: String)
}

/// What one engine pass wants to happen. Writes go to the calendar,
/// readbacks go to the data files; after applying readbacks the caller
/// must re-plan and run a second pass (which must converge to no-ops).
public struct SyncPlan: Equatable {
    public var creates: [PlannedShift] = []
    public var updates: [EventUpdate] = []
    public var deletes: [EventDeletion] = []
    public var readbacks: [ReadbackChange] = []
    /// Events in the window that Shiftly does not manage and will not touch.
    public var ignoredForeign: [CalendarEventInfo] = []
    /// Entries still valid after this pass (existing + claimed). The applier
    /// appends entries for `creates`/`updates` once event IDs are known.
    public var keptEntries: [SyncEntry] = []

    public struct EventUpdate: Equatable {
        public let eventID: String
        public let shift: PlannedShift
        public init(eventID: String, shift: PlannedShift) {
            self.eventID = eventID
            self.shift = shift
        }
    }

    public struct EventDeletion: Equatable {
        public let eventID: String
        public let date: String
        public init(eventID: String, date: String) {
            self.eventID = eventID
            self.date = date
        }
    }

    public var isNoop: Bool {
        creates.isEmpty && updates.isEmpty && deletes.isEmpty && readbacks.isEmpty
    }

    public init() {}
}
