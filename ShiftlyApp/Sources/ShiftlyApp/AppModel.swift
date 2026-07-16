import AppKit
import EventKit
import Foundation
import ServiceManagement
import ShiftlyKit

@MainActor
final class AppModel: ObservableObject {
    @Published var selectedDays: Set<String> = []
    @Published var startTime = "10:00"
    @Published var endTime = "18:30"
    @Published var effectiveFrom = Date()
    @Published var swapFrom = Date()
    @Published var swapTo = Date()
    @Published var leaveStart = Date()
    @Published var leaveEnd = Date()
    @Published var swaps: [SwapItem] = []
    @Published var leaves: [LeaveItem] = []
    @Published var syncState: SyncState = .unsynced
    @Published var lastSyncText = "-"
    @Published var statusMessage = ""
    @Published var isBusy = false
    @Published var busyMessage = ""
    @Published var workHistory: [WorkHistoryRow] = []
    @Published var workHistoryNote = ""
    @Published var rulesSummary = ""
    @Published var lastReport: SyncReportFile?
    @Published var readbackLog: [ReadbackRecord] = []

    @Published private(set) var paths = ShiftlyPaths.shared
    private var store: DataStore { DataStore(paths: paths) }

    /// True when no data root could be resolved: the first-run view is shown.
    var needsRootSetup: Bool { !paths.isValid }

    /// First-run flow: adopt a user-chosen folder as the data root,
    /// creating starter data files when missing.
    func adoptRoot(_ url: URL) {
        do {
            let root = url.path
            try ShiftlyPaths.bootstrapDataDirectory(atRoot: root)
            ShiftlyPaths.persistRoot(root)
            paths = ShiftlyPaths(root: root)
            statusMessage = "Data folder ready. Set your weekly schedule, then Sync Now."
            load()
        } catch {
            statusMessage = "Could not prepare data folder: \(error.localizedDescription)"
        }
    }

    let dayOrder = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]
    let dayLabels: [String: String] = [
        "MO": "Mon", "TU": "Tue", "WE": "Wed", "TH": "Thu", "FR": "Fri", "SA": "Sat", "SU": "Sun"
    ]

    func load() {
        guard paths.isValid else {
            statusMessage = "Set SHIFTLY_ROOT (or legacy SHIFTY_ROOT/SHIFTFLOW_ROOT), or run from the repo so data/config.json can be found."
            return
        }
        loadConfig()
        swaps = (try? store.loadSwaps()) ?? []
        leaves = (try? store.loadLeaves()) ?? []
        loadMeta()
        loadSyncReport()
        refreshWorkHistory()
    }

    func loadSyncReport() {
        lastReport = store.loadSyncReport()
        readbackLog = ReadbackJournal(paths: paths).load().reversed()
    }

    func undoReadback(_ record: ReadbackRecord) {
        guard !isBusy else { return }
        do {
            let undoService = ReadbackUndoService(
                store: store,
                journal: ReadbackJournal(paths: paths)
            )
            if try undoService.undo(record) {
                loadSyncReport()
                // Re-sync writes the restored plan back to the calendar.
                syncNow()
            } else {
                statusMessage = "Could not undo: matching record no longer exists."
                loadSyncReport()
            }
        } catch {
            statusMessage = "Undo failed: \(error.localizedDescription)"
        }
    }

    func saveSchedule() {
        do {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            let rules = try store.saveSchedule(
                startTime: startTime,
                endTime: endTime,
                effectiveFrom: df.string(from: effectiveFrom),
                workdays: dayOrder.filter { selectedDays.contains($0) }
            )
            rulesSummary = Self.rulesSummary(from: rules)
            syncState = .unsynced
            statusMessage = "Schedule saved."
        } catch {
            statusMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    func addSwap() {
        do {
            var list = try store.loadSwaps()
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            list.append(SwapItem(from_date: df.string(from: swapFrom), to_date: df.string(from: swapTo)))
            try store.saveSwaps(list)
            swaps = list
            syncState = .unsynced
            statusMessage = "Swap added."
        } catch {
            statusMessage = "Add swap failed: \(error.localizedDescription)"
        }
    }

    func addLeave() {
        do {
            var list = try store.loadLeaves()
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            list.append(LeaveItem(start_date: df.string(from: leaveStart), end_date: df.string(from: leaveEnd)))
            try store.saveLeaves(list)
            leaves = list
            syncState = .unsynced
            statusMessage = "Leave added."
        } catch {
            statusMessage = "Add leave failed: \(error.localizedDescription)"
        }
    }

    func deleteSwap(id: UUID) {
        guard swaps.contains(where: { $0.id == id }) else { return }
        swaps.removeAll { $0.id == id }
        do {
            try store.saveSwaps(swaps)
            syncState = .unsynced
        } catch {
            statusMessage = "Delete swap failed: \(error.localizedDescription)"
        }
    }

    func deleteLeave(id: UUID) {
        guard leaves.contains(where: { $0.id == id }) else { return }
        leaves.removeAll { $0.id == id }
        do {
            try store.saveLeaves(leaves)
            syncState = .unsynced
        } catch {
            statusMessage = "Delete leave failed: \(error.localizedDescription)"
        }
    }

    @Published var showSettingsHint = false

    func syncNow() {
        guard !isBusy else { return }
        guard paths.isValid else {
            statusMessage = "Cannot sync: repo path not resolved."
            return
        }
        isBusy = true
        busyMessage = "Syncing with Calendar…"
        showSettingsHint = false
        let root = paths.root
        Task { @MainActor in
            defer {
                isBusy = false
                busyMessage = ""
            }
            let ekStore = EKEventStore()
            guard await CalendarAccess.request(using: ekStore) else {
                syncState = .error("calendar access denied")
                statusMessage = "Calendar access denied. Grant access in System Settings → Privacy & Security → Calendars, then sync again."
                showSettingsHint = true
                return
            }
            do {
                let syncPaths = paths
                let outcome = try await Task.detached(priority: .userInitiated) {
                    let store = DataStore(paths: syncPaths)
                    let config = try store.loadConfig()
                    let calendar = try EKCalendarStore.locateOrCreateCalendar(
                        named: config.calendar_name, in: ekStore
                    )
                    let coordinator = SyncCoordinator(
                        store: store,
                        stateStore: SyncStateStore(paths: syncPaths),
                        calendar: EKCalendarStore(eventStore: ekStore, calendar: calendar),
                        provider: PlannerScriptProvider(root: root)
                    )
                    return try coordinator.sync()
                }.value
                load()
                syncState = .synced
                statusMessage = Self.syncSummary(outcome)
            } catch {
                syncState = .error(String(describing: error))
                statusMessage = "Sync failed: \(error)"
                loadMeta()
            }
        }
    }

    func openCalendarPrivacySettings() {
        if let url = URL(string: CalendarAccess.settingsURLString) {
            NSWorkspace.shared.open(url)
        }
    }

    private static func syncSummary(_ outcome: SyncOutcome) -> String {
        var parts: [String] = []
        if outcome.created > 0 { parts.append("\(outcome.created) created") }
        if outcome.updated > 0 { parts.append("\(outcome.updated) updated") }
        if outcome.deleted > 0 { parts.append("\(outcome.deleted) removed") }
        if !outcome.readbacks.isEmpty { parts.append("\(outcome.readbacks.count) read back from Calendar") }
        if parts.isEmpty { return "Synced. Already up to date." }
        return "Synced: " + parts.joined(separator: ", ") + "."
    }

    func saveScheduleAndSync() {
        saveSchedule()
        syncNow()
    }

    func addSwapAndSync() {
        addSwap()
        syncNow()
    }

    func addLeaveAndSync() {
        addLeave()
        syncNow()
    }

    func openCalendar() {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        proc.arguments = ["-a", "Calendar"]
        try? proc.run()
    }

    func refreshWorkHistory() {
        guard paths.isValid else {
            workHistory = []
            workHistoryNote = ""
            return
        }
        let root = paths.root
        guard let script = ScriptLocator.locate("work_history.py", root: root) else {
            workHistory = []
            workHistoryNote = "work_history.py not found at the data root or in the app bundle."
            return
        }
        Task { @MainActor in
            let result = await Task.detached(priority: .utility) {
                WorkHistoryScriptRunner.run(root: root, scriptPath: script)
            }.value
            workHistory = result.rows
            workHistoryNote = result.note
        }
    }

    private func loadConfig() {
        do {
            let config = try store.loadConfig()
            if config.calendar_name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                statusMessage = "Config invalid: calendar_name is empty."
                return
            }
            startTime = config.default_start_time
            endTime = config.default_end_time
            let sorted = config.rules.sorted { $0.effective_from < $1.effective_from }
            // Edit the newest rule; older ones are history and must be kept.
            if let latest = sorted.last {
                selectedDays = Set(latest.workdays)
                let df = DateFormatter()
                df.dateFormat = "yyyy-MM-dd"
                effectiveFrom = df.date(from: latest.effective_from) ?? Date()
            }
            rulesSummary = Self.rulesSummary(from: sorted)
            if let v = config.config_version, v > 1 {
                statusMessage = "Warning: config_version \(v) is newer than this app supports."
            }
        } catch {
            statusMessage = "Config load failed."
        }
    }

    private func loadMeta() {
        guard let meta = store.loadMeta() else { return }
        lastSyncText = meta.last_sync_at.isEmpty ? "-" : meta.last_sync_at
        if meta.last_sync_status == "success" { syncState = .synced }
    }

    private static func rulesSummary(from rules: [Rule]) -> String {
        let sorted = rules.sorted { $0.effective_from < $1.effective_from }
        guard let latest = sorted.last else { return "" }
        if sorted.count == 1 {
            return "1 rule · effective from \(latest.effective_from)"
        }
        return "\(sorted.count) rules · latest effective from \(latest.effective_from)"
    }

    // MARK: Auto-sync (runs while the app is open; pair with launch-at-login
    // so a reboot needs no terminal. Headless syncing without the app stays
    // on the launchd template.)

    static let autoSyncDefaultsKey = "shiftly.autoSyncHours"
    static let autoSyncChoices = [0, 1, 6, 12, 24]

    @Published var autoSyncHours: Int = UserDefaults.standard.integer(forKey: AppModel.autoSyncDefaultsKey) {
        didSet {
            UserDefaults.standard.set(autoSyncHours, forKey: Self.autoSyncDefaultsKey)
            scheduleAutoSync()
        }
    }
    private var autoSyncTimer: Timer?

    /// Called once at startup: schedules the timer and, when enabled,
    /// runs a catch-up sync right away.
    func startAutoSyncIfEnabled() {
        scheduleAutoSync()
        if autoSyncHours > 0 && paths.isValid {
            syncNow()
        }
    }

    private func scheduleAutoSync() {
        autoSyncTimer?.invalidate()
        autoSyncTimer = nil
        guard autoSyncHours > 0 else { return }
        let interval = TimeInterval(autoSyncHours) * 3600
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isBusy, self.paths.isValid else { return }
                self.syncNow()
            }
        }
        timer.tolerance = 300
        RunLoop.main.add(timer, forMode: .common)
        autoSyncTimer = timer
    }

    // MARK: Launch at login (SMAppService; only effective for the bundled
    // Shiftly.app, not `swift run`)

    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = SMAppService.mainApp.status == .enabled
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            statusMessage = "Launch at login unavailable: \(error.localizedDescription) (requires the bundled Shiftly.app)"
        }
    }
}
