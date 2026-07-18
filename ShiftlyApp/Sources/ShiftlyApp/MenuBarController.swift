import AppKit
import Combine
import ShiftlyKit

/// AppKit-backed menu bar item. Replaces SwiftUI's MenuBarExtra, whose
/// `isInserted:` binding spins the scene-update loop at 100% CPU on
/// current macOS — an NSStatusItem has no such feedback path. The menu is
/// rebuilt each time it opens, so the countdown is always fresh; the icon
/// updates only when the sync state actually changes.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private unowned let model: AppModel
    private var statusItem: NSStatusItem?
    private var stateSink: AnyCancellable?

    init(model: AppModel) {
        self.model = model
        super.init()
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            install()
        } else {
            remove()
        }
    }

    private func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = icon(for: model.syncState)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item

        stateSink = model.$syncState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.statusItem?.button?.image = self?.icon(for: state)
            }
    }

    private func remove() {
        stateSink = nil
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    private func icon(for state: SyncState) -> NSImage? {
        let name: String
        switch state {
        case .synced: name = "calendar.badge.checkmark"
        case .unsynced: name = "calendar"
        case .error: name = "calendar.badge.exclamationmark"
        }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Shiftly")
        image?.isTemplate = true
        return image
    }

    // MARK: NSMenuDelegate — rebuild on every open for a fresh countdown

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if let shift = model.nextShift {
            let line = LF(
                "Next shift: %@ – %@",
                shift.start.formatted(date: .abbreviated, time: .shortened),
                shift.end.formatted(date: .omitted, time: .shortened)
            )
            menu.addItem(disabled(line))
            let relative = shift.start > Date()
                ? shift.start.formatted(.relative(presentation: .named))
                : L("In progress")
            menu.addItem(disabled(relative))
        } else if model.paths.isValid {
            menu.addItem(disabled(L("No upcoming shift in the next 45 days")))
        } else {
            menu.addItem(disabled(L("Data folder not set — open Shiftly")))
        }
        menu.addItem(disabled(statusLine()))

        menu.addItem(.separator())

        let sync = NSMenuItem(title: L("Sync Now"), action: #selector(syncNow), keyEquivalent: "")
        sync.target = self
        sync.isEnabled = !model.isBusy && model.paths.isValid
        menu.addItem(sync)

        if !model.enabledRoutineSteps.isEmpty {
            let start = NSMenuItem(title: L("Start Work"), action: #selector(startWork), keyEquivalent: "")
            start.target = self
            start.isEnabled = !model.routineRunning
            menu.addItem(start)
        }

        menu.addItem(disabled(L("Write Log Entry")))

        menu.addItem(.separator())

        let open = NSMenuItem(title: L("Open Shiftly"), action: #selector(openApp), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        let quit = NSMenuItem(title: L("Quit Shiftly"), action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func statusLine() -> String {
        switch model.syncState {
        case .synced: return LF("Synced · %@", model.lastSyncText)
        case .unsynced: return L("Not synced yet")
        case .error: return L("Sync error — see Shiftly for details")
        }
    }

    // MARK: Actions

    @objc private func syncNow() {
        model.syncNow()
    }

    @objc private func startWork() {
        model.runRoutine()
    }

    @objc private func openApp() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeKey && !($0 is NSPanel) }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            // Closed windows are gone in SwiftUI; a reopen event through
            // Launch Services recreates the WindowGroup window.
            NSWorkspace.shared.openApplication(
                at: Bundle.main.bundleURL,
                configuration: NSWorkspace.OpenConfiguration(),
                completionHandler: nil
            )
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
