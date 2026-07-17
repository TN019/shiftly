import Foundation
import ShiftlyKit
import UserNotifications

/// Thin wrapper over UNUserNotificationCenter for pre-shift reminders.
/// UserNotifications needs a real bundle identity: available only when
/// running from Shiftly.app (not `swift run`), otherwise every call is a
/// silent no-op and the Settings UI shows a hint.
enum NotificationScheduler {
    static var isAvailable: Bool {
        Bundle.main.bundlePath.hasSuffix(".app")
    }

    /// Ask for permission if not determined. Returns whether notifications
    /// may be delivered.
    static func ensureAuthorization() async -> Bool {
        guard isAvailable else { return false }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        case .denied:
            return false
        default:
            return true
        }
    }

    /// Replace all Shiftly reminders with the given plan.
    static func reschedule(_ items: [ReminderItem]) async {
        guard isAvailable else { return }
        let center = UNUserNotificationCenter.current()

        let pending = await center.pendingNotificationRequests()
        let stale = pending.map(\.identifier).filter { $0.hasPrefix(ReminderPlanner.idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: stale)

        for item in items {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            let comps = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: item.fireDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(identifier: item.id, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }
}
