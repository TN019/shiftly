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
    @Published var payConfig: PayConfig?
    @Published var payCurrentMonth: PayBreakdown?
    @Published var logDir: String = (WorkLogStore.defaultDir as NSString).expandingTildeInPath
    @Published var logDirExists = false
    /// Content of today's log file; nil = not created yet.
    @Published var todayLogContent: String?
    /// Days with a log file in the calendar's displayed month.
    @Published var monthLogDates: Set<String> = []
    @Published var logSearchResults: [WorkLogStore.SearchHit] = []
    /// Last 12 months (oldest first), empty months included with zero totals.
    @Published var payMonths: [MonthPay] = []
    /// Sum of the current calendar year's earnings (base currency).
    @Published var payYearToDate: Double = 0

    struct MonthPay: Identifiable, Equatable {
        let month: String // YYYY-MM
        let breakdown: PayBreakdown
        var id: String { month }
    }

    @Published private(set) var paths = ShiftlyPaths.shared
    private var store: DataStore { DataStore(paths: paths) }

    // MARK: External file change watching

    private var watcher: FolderWatcher?
    /// Events until this instant are ours (self-write suppression).
    private var suppressWatcherUntil = Date.distantPast

    /// Call after any write this app performs, so the watcher does not
    /// re-trigger a reload for our own file activity.
    func noteOwnWrite() {
        suppressWatcherUntil = Date().addingTimeInterval(2)
    }

    /// Watch data/ and the log folder; external edits reload the UI and
    /// flag the state as unsynced (a corrupt half-written file just loads
    /// as defaults and the writer's final event triggers another reload).
    func startWatching() {
        watcher?.stop()
        guard paths.isValid else { return }
        watcher = FolderWatcher(paths: ["\(paths.root)/data", logDir]) { [weak self] changed in
            Task { @MainActor [weak self] in
                self?.handleExternalChange(changed)
            }
        }
        watcher?.start()
    }

    private func handleExternalChange(_ changedPaths: [String]) {
        guard Date() >= suppressWatcherUntil else { return }
        // A headless `shiftly sync now` also writes here; its meta/state
        // files identify it, and loadMeta then reports the true state.
        let syncArtifacts = ["meta.json", "sync_state.json", "last_sync_report", "readback_log"]
        let wasSync = changedPaths.contains { path in
            syncArtifacts.contains { path.contains($0) }
        }
        noteOwnWrite() // our own reload must not re-trigger the watcher
        load()
        if !wasSync {
            syncState = .unsynced
            statusMessage = L("Data changed on disk — reloaded.")
        }
    }

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
            statusMessage = L("Data folder ready. Set your weekly schedule, then Sync Now.")
            load()
            startWatching()
        } catch {
            statusMessage = LF("Could not prepare data folder: %@", error.localizedDescription)
        }
    }

    let dayOrder = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]
    let dayLabels: [String: String] = [
        "MO": L("Mon"), "TU": L("Tue"), "WE": L("Wed"), "TH": L("Thu"),
        "FR": L("Fri"), "SA": L("Sat"), "SU": L("Sun"),
    ]

    func load() {
        guard paths.isValid else {
            statusMessage = L("Set SHIFTLY_ROOT (or legacy SHIFTY_ROOT/SHIFTFLOW_ROOT), or run from the repo so data/config.json can be found.")
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
        payConfig = store.loadPayConfig()
        refreshPayMonth()
        refreshLogState()
        if watcher == nil {
            startWatching()
        }
    }

    // MARK: Work log

    var logStore: WorkLogStore {
        WorkLogStore(rootDir: logDir)
    }

    func refreshLogState() {
        let configured = (try? store.loadConfig())?.log_dir ?? WorkLogStore.defaultDir
        logDir = (configured as NSString).expandingTildeInPath
        logDirExists = logStore.rootExists
        todayLogContent = logStore.read(date: Self.todayYMD())
    }

    /// Append a timestamped entry to today's log (created on demand).
    func quickCapture(_ text: String) {
        noteOwnWrite()
        let entry = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !entry.isEmpty else { return }
        guard logDirExists else {
            statusMessage = L("Create the log folder first.")
            return
        }
        Task { @MainActor in
            guard await ensureTodayLog() != nil else {
                statusMessage = L("Could not create today's log.")
                return
            }
            let hhmm = SyncFingerprint.hhmmString(for: Date())
            do {
                try logStore.append(
                    entry: entry,
                    date: Self.todayYMD(),
                    timeHHMM: hhmm,
                    shift: nil,
                    shiftType: nil
                )
                todayLogContent = logStore.read(date: Self.todayYMD())
                statusMessage = L("Logged.")
            } catch {
                statusMessage = LF("Quick capture failed: %@", error.localizedDescription)
            }
        }
    }

    /// Create the log folder (first use) at the current location.
    func createLogDir() {
        noteOwnWrite()
        do {
            try FileManager.default.createDirectory(atPath: logDir, withIntermediateDirectories: true)
            refreshLogState()
            statusMessage = L("Log folder created.")
        } catch {
            statusMessage = LF("Could not create log folder: %@", error.localizedDescription)
        }
    }

    /// Point config at a different log folder. Existing files are neither
    /// moved nor deleted.
    func adoptLogDir(_ url: URL) {
        noteOwnWrite()
        do {
            try store.saveLogDir(url.path)
            refreshLogState()
            startWatching()
            statusMessage = L("Log folder updated. Existing logs stay in the old folder.")
        } catch {
            statusMessage = LF("Could not save log folder: %@", error.localizedDescription)
        }
    }

    /// Ensure today's log exists (frontmatter pre-filled from the plan) and
    /// return its path; nil on failure.
    func ensureTodayLog() async -> String? {
        let today = Self.todayYMD()
        let syncPaths = paths
        let dir = logDir
        return await Task.detached(priority: .utility) { () -> String? in
            let source = SyncDataSource(
                store: DataStore(paths: syncPaths),
                provider: PlannerScriptProvider(root: syncPaths.root)
            )
            let planned = (try? source.plannedShifts(start: today, end: today)) ?? []
            let days = (try? PlannerScriptProvider(root: syncPaths.root)
                .plannedDays(start: today, end: today)) ?? []
            let logStore = WorkLogStore(rootDir: dir)
            return try? logStore.ensureFile(
                date: today,
                shift: planned.first,
                shiftType: planned.first?.kind == .manual ? "manual" : days.first?.shiftType
            )
        }.value
    }

    func openTodayLog() {
        noteOwnWrite()
        guard paths.isValid else { return }
        guard logDirExists else {
            statusMessage = L("Create the log folder first.")
            return
        }
        Task { @MainActor in
            if let path = await ensureTodayLog() {
                todayLogContent = logStore.read(date: Self.todayYMD())
                NSWorkspace.shared.open(URL(fileURLWithPath: path))
            } else {
                statusMessage = L("Could not create today's log.")
            }
        }
    }

    // MARK: Pay

    /// Earnings for the last 12 months in one solve (same source as
    /// calendar/sync); derives current-month card, chart series, and YTD.
    func refreshPayMonth() {
        guard paths.isValid, let config = payConfig else {
            payCurrentMonth = nil
            payMonths = []
            payYearToDate = 0
            return
        }
        let syncPaths = paths
        Task { @MainActor in
            let byMonth = await Task.detached(priority: .utility) { () -> [String: PayBreakdown] in
                let cal = Calendar.current
                let now = Date()
                let thisMonthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
                let windowStart = cal.date(byAdding: .month, value: -11, to: thisMonthStart) ?? now
                let dayCount = cal.range(of: .day, in: .month, for: thisMonthStart)?.count ?? 28
                let windowEnd = cal.date(byAdding: .day, value: dayCount - 1, to: thisMonthStart) ?? now
                let df = DateFormatter()
                df.dateFormat = "yyyy-MM-dd"
                let source = SyncDataSource(
                    store: DataStore(paths: syncPaths),
                    provider: PlannerScriptProvider(root: syncPaths.root)
                )
                let shifts = (try? source.plannedShifts(
                    start: df.string(from: windowStart), end: df.string(from: windowEnd)
                )) ?? []
                return PayEngine.byMonth(shifts: shifts, config: config)
            }.value

            let cal = Calendar.current
            let now = Date()
            var months: [MonthPay] = []
            for offset in stride(from: -11, through: 0, by: 1) {
                guard let date = cal.date(byAdding: .month, value: offset, to: now) else { continue }
                let c = cal.dateComponents([.year, .month], from: date)
                let key = String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
                months.append(MonthPay(month: key, breakdown: byMonth[key] ?? PayBreakdown()))
            }
            payMonths = months
            payCurrentMonth = months.last?.breakdown
            let yearPrefix = String(format: "%04d-", cal.component(.year, from: now))
            payYearToDate = months
                .filter { $0.month.hasPrefix(yearPrefix) }
                .reduce(0) { $0 + $1.breakdown.totalAmount }
        }
    }

    func createPayConfig(baseCurrency: String, hourly: Double, effectiveFrom: String) {
        let config = PayConfig(
            base_currency: baseCurrency,
            rates: [PayRate(effective_from: effectiveFrom, hourly: hourly)]
        )
        savePay(config, successMessage: L("Pay setup saved."))
    }

    func addPayRate(hourly: Double, effectiveFrom: String) {
        guard var config = payConfig else { return }
        config.rates.removeAll { $0.effective_from == effectiveFrom }
        config.rates.append(PayRate(effective_from: effectiveFrom, hourly: hourly))
        config.rates.sort { $0.effective_from < $1.effective_from }
        savePay(config, successMessage: L("Rate saved."))
    }

    func updateDisplayRates(_ rates: [String: Double]) {
        guard var config = payConfig else { return }
        config.display_rates = rates
        savePay(config, successMessage: L("Exchange rates saved."))
    }

    private func savePay(_ config: PayConfig, successMessage: String) {
        noteOwnWrite()
        do {
            try store.savePayConfig(config)
            payConfig = config
            statusMessage = successMessage
            refreshPayMonth()
        } catch {
            statusMessage = LF("Pay save failed: %@", error.localizedDescription)
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
                monthLogDates = logStore.datesWithLogs(inMonth: String(start.prefix(7)))
            }
        }
    }

    /// Open (creating if needed) the log for any date; frontmatter is
    /// pre-filled from that day's plan.
    func openLog(date: String) {
        noteOwnWrite()
        guard logDirExists else {
            statusMessage = L("Create the log folder first.")
            return
        }
        let syncPaths = paths
        let dir = logDir
        Task { @MainActor in
            let path = await Task.detached(priority: .utility) { () -> String? in
                let source = SyncDataSource(
                    store: DataStore(paths: syncPaths),
                    provider: PlannerScriptProvider(root: syncPaths.root)
                )
                let planned = (try? source.plannedShifts(start: date, end: date)) ?? []
                let days = (try? PlannerScriptProvider(root: syncPaths.root)
                    .plannedDays(start: date, end: date)) ?? []
                return try? WorkLogStore(rootDir: dir).ensureFile(
                    date: date,
                    shift: planned.first,
                    shiftType: planned.first?.kind == .manual ? "manual" : days.first?.shiftType
                )
            }.value
            if let path {
                monthLogDates.insert(date)
                if date == Self.todayYMD() {
                    todayLogContent = logStore.read(date: date)
                }
                NSWorkspace.shared.open(URL(fileURLWithPath: path))
            } else {
                statusMessage = L("Could not create the log.")
            }
        }
    }

    func searchLogs(query: String, from: String?, to: String?) {
        let dir = logDir
        Task { @MainActor in
            logSearchResults = await Task.detached(priority: .utility) {
                WorkLogStore(rootDir: dir).search(query: query, from: from, to: to)
            }.value
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
        noteOwnWrite()
        do {
            try store.saveCalendarSettings(
                calendarName: calendarName.trimmingCharacters(in: .whitespaces),
                eventTitle: eventTitle.trimmingCharacters(in: .whitespaces)
            )
            syncState = .unsynced
            statusMessage = L("Settings saved.")
        } catch {
            statusMessage = LF("Save settings failed: %@", error.localizedDescription)
        }
    }

    func loadSyncReport() {
        lastReport = store.loadSyncReport()
        readbackLog = ReadbackJournal(paths: paths).load().reversed()
    }

    func undoReadback(_ record: ReadbackRecord) {
        guard !isBusy else { return }
        noteOwnWrite()
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
                statusMessage = L("Could not undo: matching record no longer exists.")
                loadSyncReport()
            }
        } catch {
            statusMessage = LF("Undo failed: %@", error.localizedDescription)
        }
    }

    func saveSchedule() {
        noteOwnWrite()
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
            statusMessage = L("Schedule saved.")
            refreshNextShift()
        } catch {
            statusMessage = LF("Save failed: %@", error.localizedDescription)
        }
    }

    /// Add or replace a rule from the timeline editor.
    func upsertRule(effectiveFrom: String, workdays: [String], shiftType: String?) {
        noteOwnWrite()
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
            statusMessage = L("Rule saved.")
            refreshNextShift()
        } catch {
            statusMessage = LF("Rule save failed: %@", error.localizedDescription)
        }
    }

    /// Delete a not-yet-effective rule. Rules already in effect are history
    /// and stay read-only.
    func deleteRule(effectiveFrom: String) {
        noteOwnWrite()
        guard effectiveFrom > Self.todayYMD() else {
            statusMessage = L("Rules already in effect are history and cannot be deleted.")
            return
        }
        do {
            let updated = try store.deleteRule(effectiveFrom: effectiveFrom)
            rules = updated.sorted { $0.effective_from < $1.effective_from }
            rulesSummary = Self.rulesSummary(from: rules)
            syncState = .unsynced
            statusMessage = L("Rule deleted.")
            refreshNextShift()
        } catch {
            statusMessage = LF("Rule delete failed: %@", error.localizedDescription)
        }
    }

    /// How many rules reference a shift type (for the impact hint).
    func ruleCount(usingShiftType id: String) -> Int {
        rules.filter { $0.shift_type == id }.count
    }

    func saveShiftTypes(_ types: [ShiftType]) {
        noteOwnWrite()
        do {
            try store.saveShiftTypes(types)
            shiftTypes = types
            if let selected = selectedShiftType, !types.contains(where: { $0.id == selected }) {
                selectedShiftType = nil
            }
            syncState = .unsynced
            statusMessage = L("Shift types saved.")
            refreshNextShift()
        } catch {
            statusMessage = LF("Shift types save failed: %@", error.localizedDescription)
        }
    }

    static func todayYMD() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: Date())
    }

    func addSwap() {
        noteOwnWrite()
        do {
            var list = try store.loadSwaps()
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            list.append(SwapItem(from_date: df.string(from: swapFrom), to_date: df.string(from: swapTo)))
            try store.saveSwaps(list)
            swaps = list
            syncState = .unsynced
            statusMessage = L("Swap added.")
        } catch {
            statusMessage = LF("Add swap failed: %@", error.localizedDescription)
        }
    }

    func addLeave() {
        noteOwnWrite()
        do {
            var list = try store.loadLeaves()
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            list.append(LeaveItem(start_date: df.string(from: leaveStart), end_date: df.string(from: leaveEnd)))
            try store.saveLeaves(list)
            leaves = list
            syncState = .unsynced
            statusMessage = L("Leave added.")
        } catch {
            statusMessage = LF("Add leave failed: %@", error.localizedDescription)
        }
    }

    func deleteSwap(id: UUID) {
        noteOwnWrite()
        guard swaps.contains(where: { $0.id == id }) else { return }
        swaps.removeAll { $0.id == id }
        do {
            try store.saveSwaps(swaps)
            syncState = .unsynced
        } catch {
            statusMessage = LF("Delete swap failed: %@", error.localizedDescription)
        }
    }

    func deleteLeave(id: UUID) {
        noteOwnWrite()
        guard leaves.contains(where: { $0.id == id }) else { return }
        leaves.removeAll { $0.id == id }
        do {
            try store.saveLeaves(leaves)
            syncState = .unsynced
        } catch {
            statusMessage = LF("Delete leave failed: %@", error.localizedDescription)
        }
    }

    @Published var showSettingsHint = false

    func syncNow() {
        guard !isBusy else { return }
        guard paths.isValid else {
            statusMessage = L("Cannot sync: repo path not resolved.")
            return
        }
        isBusy = true
        busyMessage = L("Syncing with Calendar…")
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
                statusMessage = L("Calendar access denied. Grant access in System Settings → Privacy & Security → Calendars, then sync again.")
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
                noteOwnWrite()
                load()
                syncState = .synced
                statusMessage = Self.syncSummary(outcome)
            } catch {
                syncState = .error(String(describing: error))
                statusMessage = LF("Sync failed: %@", String(describing: error))
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
        if outcome.created > 0 { parts.append(LF("%lld created", outcome.created)) }
        if outcome.updated > 0 { parts.append(LF("%lld updated", outcome.updated)) }
        if outcome.deleted > 0 { parts.append(LF("%lld removed", outcome.deleted)) }
        if !outcome.readbacks.isEmpty { parts.append(LF("%lld read back from Calendar", outcome.readbacks.count)) }
        if parts.isEmpty { return L("Synced. Already up to date.") }
        return LF("Synced: %@.", parts.joined(separator: ", "))
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
            workHistoryNote = L("work_history.py not found at the data root or in the app bundle.")
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
                statusMessage = L("Config invalid: calendar_name is empty.")
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
                statusMessage = LF("Warning: config_version %lld is newer than this app supports.", v)
            }
        } catch {
            statusMessage = L("Config load failed.")
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
            return LF("1 rule · effective from %@", latest.effective_from)
        }
        return LF("%lld rules · latest effective from %@", sorted.count, latest.effective_from)
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
            statusMessage = LF("Launch at login unavailable: %@ (requires the bundled Shiftly.app)", error.localizedDescription)
        }
    }
}
