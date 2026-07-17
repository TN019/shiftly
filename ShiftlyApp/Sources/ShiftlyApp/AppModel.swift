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
    @Published var calendarName = ""
    @Published var eventTitle = ""
    @Published var nextShift: PlannedShift?
    @Published var rules: [Rule] = []
    @Published var shiftTypes: [ShiftType] = []
    @Published var selectedShiftType: String? = nil
    /// Engine-solved shifts for the month currently shown in the calendar
    /// page, keyed by YYYY-MM-DD. Same data source as sync (planner +
    /// overrides + manual), never a re-implementation.
    @Published var monthShifts: [String: PlannedShift] = [:]
    private var monthRange: (start: String, end: String)?

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
        refreshNextShift()
        if let range = monthRange {
            loadMonth(start: range.start, end: range.end)
        }
    }

    /// Solve the schedule for a displayed month (start/end YYYY-MM-DD).
    func loadMonth(start: String, end: String) {
        monthRange = (start, end)
        guard paths.isValid else {
            monthShifts = [:]
            return
        }
        let syncPaths = paths
        Task { @MainActor in
            let shifts = await Task.detached(priority: .utility) { () -> [String: PlannedShift] in
                let source = SyncDataSource(
                    store: DataStore(paths: syncPaths),
                    provider: PlannerScriptProvider(root: syncPaths.root)
                )
                let list = (try? source.plannedShifts(start: start, end: end)) ?? []
                return Dictionary(list.map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })
            }.value
            // Only publish if this is still the month being displayed.
            if monthRange?.start == start {
                monthShifts = shifts
            }
        }
    }

    /// Next planned shift from today onward (looks 45 days ahead); also
    /// reschedules pre-shift reminders from the same solve.
    func refreshNextShift() {
        guard paths.isValid else {
            nextShift = nil
            return
        }
        let syncPaths = paths
        Task { @MainActor in
            let shifts = await Task.detached(priority: .utility) { () -> [PlannedShift] in
                let df = DateFormatter()
                df.dateFormat = "yyyy-MM-dd"
                let today = df.string(from: Date())
                let end = df.string(from: Date().addingTimeInterval(45 * 86400))
                let source = SyncDataSource(
                    store: DataStore(paths: syncPaths),
                    provider: PlannerScriptProvider(root: syncPaths.root)
                )
                return (try? source.plannedShifts(start: today, end: end)) ?? []
            }.value
            let now = Date()
            nextShift = shifts.first { $0.end > now }
            await rescheduleReminders(shifts: shifts)
        }
    }

    // MARK: Pre-shift reminders

    static let reminderDefaultsKey = "shiftly.reminderMinutes"

    /// Lead time in minutes; 0 = off. Defaults to 60.
    @Published var reminderMinutes: Int = {
        UserDefaults.standard.object(forKey: AppModel.reminderDefaultsKey) == nil
            ? 60
            : UserDefaults.standard.integer(forKey: AppModel.reminderDefaultsKey)
    }() {
        didSet {
            UserDefaults.standard.set(reminderMinutes, forKey: Self.reminderDefaultsKey)
            refreshNextShift()
        }
    }

    var notificationsAvailable: Bool {
        NotificationScheduler.isAvailable
    }

    private func rescheduleReminders(shifts: [PlannedShift]) async {
        guard NotificationScheduler.isAvailable else { return }
        guard reminderMinutes > 0 else {
            await NotificationScheduler.reschedule([])
            return
        }
        guard await NotificationScheduler.ensureAuthorization() else { return }
        let items = ReminderPlanner.plan(
            shifts: shifts,
            leadMinutes: reminderMinutes,
            now: Date()
        )
        await NotificationScheduler.reschedule(items)
    }

    func saveCalendarSettings() {
        do {
            try store.saveCalendarSettings(
                calendarName: calendarName.trimmingCharacters(in: .whitespaces),
                eventTitle: eventTitle.trimmingCharacters(in: .whitespaces)
            )
            syncState = .unsynced
            statusMessage = "Settings saved."
        } catch {
            statusMessage = "Save settings failed: \(error.localizedDescription)"
        }
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
            let updated = try store.saveSchedule(
                startTime: startTime,
                endTime: endTime,
                effectiveFrom: df.string(from: effectiveFrom),
                workdays: dayOrder.filter { selectedDays.contains($0) },
                shiftType: selectedShiftType
            )
            rules = updated.sorted { $0.effective_from < $1.effective_from }
            rulesSummary = Self.rulesSummary(from: rules)
            syncState = .unsynced
            statusMessage = "Schedule saved."
            refreshNextShift()
        } catch {
            statusMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    /// Add or replace a rule from the timeline editor.
    func upsertRule(effectiveFrom: String, workdays: [String], shiftType: String?) {
        do {
            let updated = try store.saveSchedule(
                startTime: startTime,
                endTime: endTime,
                effectiveFrom: effectiveFrom,
                workdays: workdays,
                shiftType: shiftType
            )
            rules = updated.sorted { $0.effective_from < $1.effective_from }
            rulesSummary = Self.rulesSummary(from: rules)
            syncState = .unsynced
            statusMessage = "Rule saved."
            refreshNextShift()
        } catch {
            statusMessage = "Rule save failed: \(error.localizedDescription)"
        }
    }

    /// Delete a not-yet-effective rule. Rules already in effect are history
    /// and stay read-only.
    func deleteRule(effectiveFrom: String) {
        guard effectiveFrom > Self.todayYMD() else {
            statusMessage = "Rules already in effect are history and cannot be deleted."
            return
        }
        do {
            let updated = try store.deleteRule(effectiveFrom: effectiveFrom)
            rules = updated.sorted { $0.effective_from < $1.effective_from }
            rulesSummary = Self.rulesSummary(from: rules)
            syncState = .unsynced
            statusMessage = "Rule deleted."
            refreshNextShift()
        } catch {
            statusMessage = "Rule delete failed: \(error.localizedDescription)"
        }
    }

    /// How many rules reference a shift type (for the impact hint).
    func ruleCount(usingShiftType id: String) -> Int {
        rules.filter { $0.shift_type == id }.count
    }

    func saveShiftTypes(_ types: [ShiftType]) {
        do {
            try store.saveShiftTypes(types)
            shiftTypes = types
            if let selected = selectedShiftType, !types.contains(where: { $0.id == selected }) {
                selectedShiftType = nil
            }
            syncState = .unsynced
            statusMessage = "Shift types saved."
            refreshNextShift()
        } catch {
            statusMessage = "Shift types save failed: \(error.localizedDescription)"
        }
    }

    static func todayYMD() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: Date())
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
            calendarName = config.calendar_name
            eventTitle = config.event_title
            let sorted = config.rules.sorted { $0.effective_from < $1.effective_from }
            rules = sorted
            shiftTypes = config.shift_types ?? []
            // Edit the newest rule; older ones are history and must be kept.
            if let latest = sorted.last {
                selectedDays = Set(latest.workdays)
                selectedShiftType = latest.shift_type
                let df = DateFormatter()
                df.dateFormat = "yyyy-MM-dd"
                effectiveFrom = df.date(from: latest.effective_from) ?? Date()
            }
            rulesSummary = Self.rulesSummary(from: sorted)
            if let v = config.config_version, v > 2 {
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
