import AppKit
import ShiftlyKit
import SwiftUI

/// Dropdown for the menu bar item: next shift at a glance + quick actions.
/// Content is rebuilt each time the menu opens, so the countdown is fresh.
struct MenuBarContent: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if let shift = model.nextShift {
                Text("Next shift: \(shift.start.formatted(date: .abbreviated, time: .shortened)) – \(shift.end.formatted(date: .omitted, time: .shortened))")
                if shift.start > Date() {
                    Text(shift.start.formatted(.relative(presentation: .named)))
                } else {
                    Text("In progress")
                }
            } else if model.paths.isValid {
                Text("No upcoming shift in the next 45 days")
            } else {
                Text("Data folder not set — open Shiftly")
            }
            Text(syncStatusLine)

            Divider()

            Button("Sync Now") {
                model.syncNow()
            }
            .disabled(model.isBusy || !model.paths.isValid)

            Button("Write Log Entry") {}
                .disabled(true)

            Divider()

            Button("Open Shiftly") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }

            Button("Quit Shiftly") {
                NSApp.terminate(nil)
            }
        }
    }

    private var syncStatusLine: String {
        switch model.syncState {
        case .synced: return LF("Synced · %@", model.lastSyncText)
        case .unsynced: return L("Not synced yet")
        case .error: return L("Sync error — see Shiftly for details")
        }
    }
}
