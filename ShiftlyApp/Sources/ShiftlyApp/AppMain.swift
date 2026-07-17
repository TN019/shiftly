import AppKit
import SwiftUI

let menuBarEnabledKey = "shiftly.menuBarEnabled"

final class ShiftlyAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // With the menu bar item enabled the app stays resident (auto-sync
        // keeps running); quitting is done from the menu bar or Cmd-Q.
        !UserDefaults.standard.bool(forKey: menuBarEnabledKey)
    }
}

@main
enum ShiftlyEntry {
    static func main() {
        if CommandLine.arguments.contains("--sync") {
            exit(HeadlessSync.run())
        }
        UserDefaults.standard.register(defaults: [menuBarEnabledKey: true])
        ShiftlyAppMain.main()
    }
}

struct ShiftlyAppMain: App {
    @NSApplicationDelegateAdaptor(ShiftlyAppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    @AppStorage(menuBarEnabledKey) private var menuBarEnabled = true

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView(model: model)
        }
        .defaultSize(width: 840, height: 780)

        MenuBarExtra(isInserted: $menuBarEnabled) {
            MenuBarContent(model: model)
        } label: {
            Image(systemName: menuBarSymbol)
        }
        .menuBarExtraStyle(.menu)
    }

    private var menuBarSymbol: String {
        switch model.syncState {
        case .synced: return "calendar.badge.checkmark"
        case .unsynced: return "calendar"
        case .error: return "calendar.badge.exclamationmark"
        }
    }
}
