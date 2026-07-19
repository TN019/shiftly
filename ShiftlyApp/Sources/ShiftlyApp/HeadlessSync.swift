import EventKit
import Foundation
import ShiftlyKit

/// `Shiftly --sync`: run one bidirectional sync without the UI and exit.
/// Used by the launchd template and the AppleScript menu. Calendar access
/// must already be granted (launch the app once and sync from the UI);
/// otherwise this exits non-zero and records the error in meta.json.
enum HeadlessSync {
    static func run() -> Int32 {
        let paths = ShiftlyPaths.shared
        guard paths.isValid else {
            fail("no data root: set SHIFTLY_ROOT or run the app once to choose a folder")
            return 2
        }
        let semaphore = DispatchSemaphore(value: 0)
        var exitCode: Int32 = 1
        Task {
            exitCode = await sync(paths: paths)
            semaphore.signal()
        }
        semaphore.wait()
        return exitCode
    }

    private static func sync(paths: ShiftlyPaths) async -> Int32 {
        let ekStore = EKEventStore()
        guard await CalendarAccess.request(using: ekStore) else {
            // Record the failure the same way the coordinator would.
            try? DataStore(paths: paths).saveMeta(Meta(
                last_sync_at: ISO8601DateFormatter().string(from: Date()),
                last_sync_status: "error",
                last_sync_error: "calendar access denied (grant access in the app first)"
            ))
            fail("calendar access denied: grant access in the app first")
            return 3
        }
        do {
            let store = DataStore(paths: paths)
            let config = try store.loadConfig()
            let stateStore = SyncStateStore(paths: paths)
            let calendar = try EKCalendarStore.locateOrCreateCalendar(
                named: config.calendar_name, in: ekStore,
                preferredID: stateStore.load().calendar_id
            )
            let coordinator = SyncCoordinator(
                store: store,
                stateStore: stateStore,
                calendar: EKCalendarStore(eventStore: ekStore, calendar: calendar),
                provider: PlannerScriptProvider(root: paths.root),
                calendarIdentifier: calendar.calendarIdentifier
            )
            let outcome = try coordinator.sync()
            print("synced: +\(outcome.created) ~\(outcome.updated) -\(outcome.deleted), readback \(outcome.readbacks.count)")
            return 0
        } catch {
            fail(String(describing: error))
            return 1
        }
    }

    private static func fail(_ message: String) {
        FileHandle.standardError.write(Data("shiftly --sync: \(message)\n".utf8))
    }
}
