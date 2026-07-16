import Foundation

public struct Rule: Codable, Equatable {
    public var effective_from: String
    public var workdays: [String]

    public init(effective_from: String, workdays: [String]) {
        self.effective_from = effective_from
        self.workdays = workdays
    }
}

public struct Config: Codable {
    public var config_version: Int?
    public var calendar_name: String
    public var event_title: String
    public var default_start_time: String
    public var default_end_time: String
    public var history_csv: String?
    public var setup_completed: Bool?
    public var rules: [Rule]
}

public struct SwapItem: Codable, Identifiable, Equatable {
    // Stable in-memory identity; not part of the JSON file format.
    public var id = UUID()
    public var from_date: String
    public var to_date: String

    private enum CodingKeys: String, CodingKey {
        case from_date, to_date
    }

    public init(from_date: String, to_date: String) {
        self.from_date = from_date
        self.to_date = to_date
    }

    // id is in-memory identity only; equality is about content.
    public static func == (lhs: SwapItem, rhs: SwapItem) -> Bool {
        lhs.from_date == rhs.from_date && lhs.to_date == rhs.to_date
    }
}

public struct LeaveItem: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var start_date: String
    public var end_date: String

    private enum CodingKeys: String, CodingKey {
        case start_date, end_date
    }

    public init(start_date: String, end_date: String) {
        self.start_date = start_date
        self.end_date = end_date
    }

    public static func == (lhs: LeaveItem, rhs: LeaveItem) -> Bool {
        lhs.start_date == rhs.start_date && lhs.end_date == rhs.end_date
    }
}

public struct Meta: Codable {
    public var last_sync_at: String
    public var last_sync_status: String
    public var last_sync_error: String?

    public init(last_sync_at: String, last_sync_status: String, last_sync_error: String? = nil) {
        self.last_sync_at = last_sync_at
        self.last_sync_status = last_sync_status
        self.last_sync_error = last_sync_error
    }
}

public struct WorkHistoryRow: Codable, Identifiable {
    public var id: String { ymd }
    public let ymd: String
    public let ordinal: Int

    public init(ymd: String, ordinal: Int) {
        self.ymd = ymd
        self.ordinal = ordinal
    }
}

public enum SyncState {
    case synced
    case unsynced
    case error(String)
}
