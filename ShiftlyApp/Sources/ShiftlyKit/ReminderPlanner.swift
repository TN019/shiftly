import Foundation

/// One pending pre-shift reminder.
public struct ReminderItem: Equatable {
    /// Stable per-day identifier ("shiftly.shift.YYYY-MM-DD") so that
    /// rescheduling replaces rather than duplicates.
    public let id: String
    public let fireDate: Date
    public let title: String
    public let body: String

    public init(id: String, fireDate: Date, title: String, body: String) {
        self.id = id
        self.fireDate = fireDate
        self.title = title
        self.body = body
    }
}

/// Pure planning of pre-shift reminders; the UNUserNotificationCenter
/// wiring stays thin and untested. Reminders always reflect the current
/// plan: callers cancel everything with the id prefix and re-add these.
public enum ReminderPlanner {
    public static let idPrefix = "shiftly.shift."

    public static func plan(
        shifts: [PlannedShift],
        leadMinutes: Int,
        now: Date,
        limit: Int = 20
    ) -> [ReminderItem] {
        guard leadMinutes > 0 else { return [] }
        return shifts
            .filter { $0.start > now }
            .sorted { $0.start < $1.start }
            .compactMap { shift -> ReminderItem? in
                let fire = shift.start.addingTimeInterval(TimeInterval(-leadMinutes * 60))
                guard fire > now else { return nil }
                return ReminderItem(
                    id: idPrefix + shift.date,
                    fireDate: fire,
                    title: "Upcoming shift",
                    body: "\(shift.start.formatted(date: .abbreviated, time: .shortened)) – \(shift.end.formatted(date: .omitted, time: .shortened))"
                )
            }
            .prefix(limit)
            .map { $0 }
    }
}
