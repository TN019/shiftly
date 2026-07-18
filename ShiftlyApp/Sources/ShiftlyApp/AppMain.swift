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

    var body: some Scene {
        // The menu bar item is an AppKit NSStatusItem owned by AppModel —
        // SwiftUI's MenuBarExtra(isInserted:) spins the scene-update loop
        // at 100% CPU (see MenuBarController).
        WindowGroup(id: "main") {
            ContentView(model: model)
        }
        .defaultSize(width: 840, height: 780)
    }
}
