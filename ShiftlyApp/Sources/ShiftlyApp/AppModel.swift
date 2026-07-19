import AppKit
import AVFoundation
import EventKit
import Foundation
import ServiceManagement
import ShiftlyKit
import WidgetKit

@MainActor
final class AppModel: ObservableObject {
    // Schedule editor state (Shift page). The folder watcher reloads config
    // on any external file event (iCloud roots touch files constantly), and
    // an unconditional refresh would wipe in-progress edits — so edits mark
    // the editor dirty and loadConfig refreshes it only while clean.
    @Published var selectedDays: Set<String> = [] { didSet { markScheduleEdited() } }
    @Published var startTime = "10:00" { didSet { markScheduleEdited() } }
    @Published var endTime = "18:30" { didSet { markScheduleEdited() } }
    @Published var effectiveFrom = Date() { didSet { markScheduleEdited() } }
    @Published var swapFrom = Date()
    @Published var swapTo = Date()
    @Published var leaveStart = Date()
    @Published var leaveEnd = Date()
    @Published var swaps: [SwapItem] = []
    @Published var leaves: [LeaveItem] = []
    @Published var holidays: [HolidayItem] = []
    @Published var holidayStart = Date()
    @Published var holidayEnd = Date()
    @Published var holidayName = ""
    @Published var holidayImportRunning = false
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
    @Published var selectedShiftType: String? = nil { didSet { markScheduleEdited() } }
    private var applyingConfig = false
    private var scheduleEditorDirty = false

    private func markScheduleEdited() {
        if !applyingConfig { scheduleEditorDirty = true }
    }
    /// Engine-solved shifts for the month currently shown in the calendar
    /// page, keyed by YYYY-MM-DD. Same data source as sync (planner +
    /// overrides + manual), never a re-implementation.
    @Published var monthShifts: [String: PlannedShift] = [:]
    private var monthRange: (start: String, end: String)?
    @Published var payConfig: PayConfig?
    @Published var payCurrentMonth: PayBreakdown?
    @Published var logDir: String = (WorkLogStore.defaultDir as NSString).expandingTildeInPath
    @Published var notesDir: String = (WorkLogStore.defaultDir as NSString).expandingTildeInPath + "/notes"
    @Published var logDirExists = false
    /// Content of the active daily log (today, or the last workday when
    /// today has no shift); nil = not created yet.
    @Published var todayLogContent: String?
    /// Standalone quick notes (`dd-mm-yy | title.md`), newest first.
    @Published var quickNotes: [WorkLogStore.NoteRef] = []
    @Published var noteSearchResults: [WorkLogStore.NoteRef] = []
    /// Every day with a daily log, newest first (the Logs browser).
    @Published var logDates: [String] = []
    /// Days with a log file in the calendar's displayed month.
    @Published var monthLogDates: Set<String> = []
    @Published var logSearchResults: [WorkLogStore.SearchHit] = []
    /// Last 12 months (oldest first), empty months included with zero totals.
    @Published var payMonths: [MonthPay] = []
    /// Sum of the current calendar year's earnings (base currency).
    @Published var payYearToDate: Double = 0
    /// Work routine steps (data/routine.json).
    @Published var routine: [RoutineStep] = []
    @Published var routineRunning = false
    /// Calendars available for history import (id, title).
    @Published var importCalendars: [ImportCalendar] = []
    @Published var importRunning = false
    /// Meeting recordings + Scripto integration.
    @Published var meetings: [MeetingStore.Meeting] = []
    @Published var meetingsDir: String = (MeetingStore.defaultDir as NSString).expandingTildeInPath
    @Published var scriptoDir: String = ""
    @Published var translateTarget: String = "zh"
    @Published var isRecording = false
    @Published var recordingSeconds = 0
    /// Meeting folders with a Scripto run in flight.
    @Published var scriptoBusy: Set<String> = []
    private var audioRecorder: AVAudioRecorder?
    private var recordTimer: Timer?

    struct ImportCalendar: Identifiable, Equatable {
        let id: String
        let title: String
    }

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
        watcher = FolderWatcher(paths: ["\(paths.root)/data", logDir, notesDir]) { [weak self] changed in
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

    /// First-run flow: provision the standard storage layout (app/data,
    /// app/meetings, logs, notes) under the chosen folder — an existing
    /// data root is adopted as-is.
    func adoptRoot(_ url: URL) {
        do {
            let root = try StorageLayout.provision(selectedPath: url.path)
            ShiftlyPaths.persistRoot(root)
            paths = ShiftlyPaths(root: root)
            statusMessage = L("Storage ready. Set your weekly schedule, then Sync Now.")
            load()
            startWatching()
        } catch {
            statusMessage = LF("Could not prepare data folder: %@", error.localizedDescription)
        }
    }

    // MARK: Storage relocation (move, never leave content behind)

    /// Move the data root (data/, and any sibling folders like meetings
    /// that live inside it) into the picked folder, which becomes the new
    /// root. Config paths inside the old root are rewritten.
    func changeDataFolder(to url: URL) {
        noteOwnWrite()
        let oldRoot = paths.root
        let newRoot = url.path
        guard newRoot != oldRoot else { return }
        do {
            try StorageLayout.moveContents(of: oldRoot, to: newRoot)
            var raw = try ConfigLogic.readRawConfig(atPath: "\(newRoot)/data/config.json")
            for key in ["log_dir", "notes_dir", "meetings_dir"] {
                if let value = raw[key] as? String, value.hasPrefix(oldRoot + "/") {
                    raw[key] = newRoot + value.dropFirst(oldRoot.count)
                }
            }
            try ConfigLogic.writeRawConfig(raw, toPath: "\(newRoot)/data/config.json")
            ShiftlyPaths.persistRoot(newRoot)
            paths = ShiftlyPaths(root: newRoot)
            load()
            startWatching()
            statusMessage = L("Data moved to the new folder.")
        } catch {
            statusMessage = LF("Move failed: %@", error.localizedDescription)
        }
    }

    func changeLogDir(to url: URL) {
        relocate(from: logDir, to: url.path, configKey: "log_dir",
                 done: L("Logs moved to the new folder."))
    }

    func changeNotesDir(to url: URL) {
        relocate(from: notesDir, to: url.path, configKey: "notes_dir",
                 done: L("Notes moved to the new folder."))
    }

    func changeMeetingsDir(to url: URL) {
        relocate(from: meetingsDir, to: url.path, configKey: "meetings_dir",
                 done: L("Meetings moved to the new folder."))
    }

    private func relocate(from oldDir: String, to newDir: String, configKey: String, done: String) {
        noteOwnWrite()
        guard newDir != oldDir else { return }
        do {
            try StorageLayout.moveContents(of: oldDir, to: newDir)
            var raw = try ConfigLogic.readRawConfig(atPath: paths.configPath)
            raw[configKey] = newDir
            try ConfigLogic.writeRawConfig(raw, toPath: paths.configPath)
            load()
            startWatching()
            statusMessage = done
        } catch {
            statusMessage = LF("Move failed: %@", error.localizedDescription)
        }
    }

    /// Factory reset: delete every Shiftly-owned data file, forget all
    /// shiftly.* preferences and return to the first-run welcome screen.
    /// Apple Calendar events and work-log files are left untouched.
    func resetAllData() {
        guard paths.isValid else { return }
        if isRecording { stopRecording() }
        watcher?.stop()
        watcher = nil
        DataReset.wipeLogs(logDir: logDir, notesDir: notesDir)
        DataReset.wipeMeetings(dir: meetingsDir)
        do {
            try DataReset.wipeData(atRoot: paths.root)
        } catch {
            statusMessage = LF("Reset failed: %@", error.localizedDescription)
            startWatching()
            return
        }
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("shiftly.") {
            defaults.removeObject(forKey: key)
        }
        paths = ShiftlyPaths(root: "")
        applyingConfig = true
        selectedDays = []
        startTime = "10:00"
        endTime = "18:30"
        effectiveFrom = Date()
        selectedShiftType = nil
        applyingConfig = false
        scheduleEditorDirty = false
        rules = []
        rulesSummary = ""
        shiftTypes = []
        swaps = []
        leaves = []
        monthShifts = [:]
        nextShift = nil
        workHistory = []
        workHistoryNote = ""
        payConfig = nil
        payCurrentMonth = nil
        payMonths = []
        payYearToDate = 0
        routine = []
        meetings = []
        quickNotes = []
        logDates = []
        todayLogContent = nil
        lastReport = nil
        readbackLog = []
        lastSyncText = "-"
        syncState = .unsynced
        statusMessage = L("All Shiftly data, logs, notes and meeting recordings erased. Calendar events were kept.")
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
        holidays = store.loadHolidays()
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
        routine = store.loadRoutine()
        refreshMeetings()
        if watcher == nil {
            startWatching()
        }
    }

    // MARK: Work routine

    var enabledRoutineSteps: [RoutineStep] {
        routine.filter(\.enabled)
    }

    func updateRoutine(_ steps: [RoutineStep]) {
        noteOwnWrite()
        do {
            try store.saveRoutine(steps)
            routine = steps
        } catch {
            statusMessage = LF("Routine save failed: %@", error.localizedDescription)
        }
    }

    /// Run all enabled steps in order. Failing steps are collected and
    /// reported; they never stop the rest.
    func runRoutine() {
        guard !routineRunning else { return }
        let steps = enabledRoutineSteps
        guard !steps.isEmpty else { return }
        routineRunning = true
        statusMessage = L("Starting your work routine…")
        Task { @MainActor in
            var failures: [String] = []
            for step in steps {
                switch step.kind {
                case "sync":
                    syncNow()
                case "log":
                    quickCapture(step.value.isEmpty ? L("Started work") : step.value)
                default:
                    let result = await Task.detached(priority: .userInitiated) {
                        RoutineRunner().runStep(step)
                    }.value
                    if !result.success {
                        failures.append("\(step.value): \(result.message ?? "?")")
                    }
                }
            }
            routineRunning = false
            statusMessage = failures.isEmpty
                ? L("Work routine finished.")
                : LF("Routine finished with issues: %@", failures.joined(separator: "; "))
        }
    }

    // MARK: Work log

    var logStore: WorkLogStore {
        WorkLogStore(rootDir: logDir, notesDir: notesDir)
    }

    /// The date daily-log entries go to: today when today is a workday,
    /// otherwise the most recent workday (a Sunday debrief belongs to
    /// Saturday's shift). Falls back to today before any history exists.
    var activeLogDate: String {
        let today = Self.todayYMD()
        return workHistory.last(where: { $0.ymd <= today })?.ymd ?? today
    }

    func refreshLogState() {
        let config = try? store.loadConfig()
        let configured = config?.log_dir ?? WorkLogStore.defaultDir
        logDir = (configured as NSString).expandingTildeInPath
        notesDir = ((config?.notes_dir ?? logDir + "/notes") as NSString).expandingTildeInPath
        logDirExists = logStore.rootExists
        todayLogContent = logStore.read(date: activeLogDate)
        quickNotes = logDirExists ? logStore.notes() : []
        logDates = logDirExists ? logStore.allDates().sorted(by: >) : []
    }

    /// Append a timestamped entry to the active daily log (created on
    /// demand).
    func quickCapture(_ text: String) {
        noteOwnWrite()
        let entry = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !entry.isEmpty else { return }
        guard logDirExists else {
            statusMessage = L("Create the log folder first.")
            return
        }
        let date = activeLogDate
        Task { @MainActor in
            guard await ensureLog(date: date) != nil else {
                statusMessage = L("Could not create today's log.")
                return
            }
            let hhmm = SyncFingerprint.hhmmString(for: Date())
            do {
                try logStore.append(
                    entry: entry,
                    date: date,
                    timeHHMM: hhmm,
                    shift: nil,
                    shiftType: nil
                )
                todayLogContent = logStore.read(date: date)
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


    /// Ensure a day's log exists (frontmatter pre-filled from the plan) and
    /// return its path; nil on failure.
    func ensureLog(date: String) async -> String? {
        let syncPaths = paths
        let dir = logDir
        return await Task.detached(priority: .utility) { () -> String? in
            let source = SyncDataSource(
                store: DataStore(paths: syncPaths),
                provider: PlannerScriptProvider(root: syncPaths.root)
            )
            let planned = (try? source.plannedShifts(start: date, end: date)) ?? []
            let days = (try? PlannerScriptProvider(root: syncPaths.root)
                .plannedDays(start: date, end: date)) ?? []
            let logStore = WorkLogStore(rootDir: dir)
            return try? logStore.ensureFile(
                date: date,
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
        let date = activeLogDate
        Task { @MainActor in
            if let path = await ensureLog(date: date) {
                todayLogContent = logStore.read(date: date)
                NSWorkspace.shared.open(URL(fileURLWithPath: path))
            } else {
                statusMessage = L("Could not create today's log.")
            }
        }
    }

    // MARK: Meetings

    var meetingStore: MeetingStore { MeetingStore(rootDir: meetingsDir) }

    func refreshMeetings() {
        let config = try? store.loadConfig()
        meetingsDir = config?.meetingsRoot ?? (MeetingStore.defaultDir as NSString).expandingTildeInPath
        scriptoDir = config?.scripto_dir ?? ""
        translateTarget = config?.translate_target ?? "zh"
        meetings = meetingStore.meetings()
    }


    func adoptScriptoDir(_ url: URL) {
        noteOwnWrite()
        do {
            try store.saveMeetingSetting(key: "scripto_dir", value: url.path)
            refreshMeetings()
            statusMessage = L("Scripto folder saved.")
        } catch {
            statusMessage = LF("Save failed: %@", error.localizedDescription)
        }
    }

    func setTranslateTarget(_ target: String) {
        noteOwnWrite()
        try? store.saveMeetingSetting(key: "translate_target", value: target)
        translateTarget = target
    }

    /// Start a meeting recording (AAC mono into the timestamped folder).
    func startRecording() {
        guard !isRecording else { return }
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            Task { @MainActor in
                guard granted else {
                    self.statusMessage = L("Microphone access denied. Grant it in System Settings → Privacy & Security → Microphone.")
                    return
                }
                self.beginRecording()
            }
        }
    }

    private func beginRecording() {
        let now = Date()
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        do {
            let path = try meetingStore.newRecordingPath(
                date: Self.todayYMD(), timeHHMM: df.string(from: now)
            )
            let recorder = try AVAudioRecorder(
                url: URL(fileURLWithPath: path),
                settings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 44_100,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
                ]
            )
            guard recorder.record() else {
                statusMessage = L("Could not start recording.")
                return
            }
            audioRecorder = recorder
            isRecording = true
            refreshNextShift() // widget snapshot picks up the recording state
            recordingSeconds = 0
            recordTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.isRecording else { return }
                    self.recordingSeconds += 1
                }
            }
            statusMessage = L("Recording…")
        } catch {
            statusMessage = LF("Could not start recording: %@", error.localizedDescription)
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        audioRecorder?.stop()
        audioRecorder = nil
        recordTimer?.invalidate()
        recordTimer = nil
        isRecording = false
        refreshMeetings()
        refreshNextShift() // widget snapshot drops the recording state
        statusMessage = L("Recording saved.")
    }

    /// Run Scripto headlessly on a meeting's audio; the SRT lands next to
    /// the recording and the list refreshes when the run finishes.
    func runScripto(meeting: MeetingStore.Meeting, translate: Bool) {
        guard let audio = meeting.audioPath else {
            statusMessage = L("No recording in this meeting folder.")
            return
        }
        let scripto = (scriptoDir as NSString).expandingTildeInPath
        guard !scripto.isEmpty,
              FileManager.default.fileExists(atPath: scripto + "/pyproject.toml") else {
            statusMessage = L("Set the Scripto folder in Settings first.")
            return
        }
        guard !scriptoBusy.contains(meeting.folder) else { return }
        scriptoBusy.insert(meeting.folder)
        statusMessage = translate ? L("Translating…") : L("Transcribing…")
        let target = translateTarget
        Task { @MainActor in
            let result = await Task.detached(priority: .userInitiated) { () -> (ok: Bool, message: String) in
                var command = "cd \(Self.shellQuote(scripto)) && uv run scripto-cli run \(Self.shellQuote(audio)) --format srt"
                if translate {
                    command += " --translate --target \(target)"
                }
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
                proc.arguments = ["-lc", command]
                let errPipe = Pipe()
                proc.standardError = errPipe
                proc.standardOutput = Pipe()
                do {
                    try proc.run()
                    proc.waitUntilExit()
                    if proc.terminationStatus == 0 {
                        return (true, "")
                    }
                    let err = String(
                        data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                        encoding: .utf8
                    )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    return (false, err.split(separator: "\n").last.map(String.init) ?? "exit \(proc.terminationStatus)")
                } catch {
                    return (false, error.localizedDescription)
                }
            }.value
            scriptoBusy.remove(meeting.folder)
            refreshMeetings()
            statusMessage = result.ok
                ? (translate ? L("Translation ready.") : L("Transcript ready."))
                : LF("Scripto failed: %@", result.message)
        }
    }

    /// Single-quote a string for /bin/zsh -lc.
    nonisolated static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    func deleteMeeting(_ meeting: MeetingStore.Meeting) {
        noteOwnWrite()
        do {
            try FileManager.default.trashItem(
                at: URL(fileURLWithPath: meeting.folder), resultingItemURL: nil
            )
            refreshMeetings()
            statusMessage = L("Meeting moved to Trash.")
        } catch {
            statusMessage = LF("Delete failed: %@", error.localizedDescription)
        }
    }

    /// Widget deep links. start-work and new-note never open the main
    /// window; meetings/open focus Shiftly (meetings also switches the
    /// sidebar to the Meetings section).
    func handleDeepLink(_ url: URL) {
        switch url.host ?? url.lastPathComponent {
        case "start-work":
            runRoutine()
        case "meetings", "record":
            UserDefaults.standard.set(AppSection.meetings.rawValue, forKey: "shiftly.section")
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
        case "new-note":
            newQuickNote()
        default:
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: In-app editor

    /// Open the in-app editor on the active daily log (created on demand).
    func editDailyLog() {
        guard logDirExists else {
            statusMessage = L("Create the log folder first.")
            return
        }
        let date = activeLogDate
        Task { @MainActor in
            guard let path = await ensureLog(date: date) else {
                statusMessage = L("Could not create today's log.")
                return
            }
            todayLogContent = logStore.read(date: date)
            LogEditorWindow.present(path: path, title: LF("Daily Log — %@", date), model: self)
        }
    }

    /// Open the in-app editor on an existing note or log file.
    func editFile(path: String, title: String) {
        LogEditorWindow.present(path: path, title: title, model: self)
    }

    /// Open the in-app editor in new-note mode (also the widget entry).
    func newQuickNote() {
        guard logDirExists else {
            statusMessage = L("Create the log folder first.")
            return
        }
        LogEditorWindow.presentNewNote(model: self)
    }

    /// Create the quick-note file for the editor's first save.
    /// Returns the path, or nil on failure.
    func createQuickNoteFile(title: String, body: String) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, logDirExists else { return nil }
        noteOwnWrite()
        do {
            let path = try logStore.createNote(title: trimmed, date: Self.todayYMD(), body: body)
            quickNotes = logStore.notes()
            return path
        } catch {
            statusMessage = LF("Note create failed: %@", error.localizedDescription)
            return nil
        }
    }

    /// Persist editor content and refresh whatever shows the file.
    func saveEditorContent(_ content: String, at path: String) -> Bool {
        noteOwnWrite()
        do {
            try Data(content.utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
            refreshLogState()
            return true
        } catch {
            statusMessage = LF("Save failed: %@", error.localizedDescription)
            return false
        }
    }

    /// Open a file in VS Code when installed, the default editor otherwise.
    func openInVSCode(path: String) {
        let candidates = ["Visual Studio Code", "VSCodium", "Code"]
        for name in candidates
        where FileManager.default.fileExists(atPath: "/Applications/\(name).app") {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            proc.arguments = ["-a", name, path]
            if (try? proc.run()) != nil { return }
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
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
                // Pay counts worked shifts only — stop at today so future
                // planned shifts (later this month) are not counted as earned.
                let windowEnd = now
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

    func setUnpaidBreak(minutes: Int) {
        guard var config = payConfig else { return }
        config.unpaid_break_minutes = max(0, minutes)
        savePay(config, successMessage: L("Unpaid break saved."))
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

    func searchLogs(query: String, from: String? = nil, to: String? = nil) {
        let dir = logDir
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            logSearchResults = []
            noteSearchResults = []
            return
        }
        Task { @MainActor in
            let (logs, notes) = await Task.detached(priority: .utility) { () -> ([WorkLogStore.SearchHit], [WorkLogStore.NoteRef]) in
                let store = WorkLogStore(rootDir: dir)
                return (store.search(query: trimmed, from: from, to: to),
                        store.searchNotes(query: trimmed))
            }.value
            logSearchResults = logs
            noteSearchResults = notes
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
            writeWidgetSnapshot(shifts: shifts.filter { $0.end > now })
            await rescheduleReminders(shifts: shifts)
        }
    }

    /// Feed the native WidgetKit widgets: snapshot JSON in the shared group
    /// container plus a timeline reload. The widget extension is sandboxed;
    /// the group container is the one place both sides can reach.
    private func writeWidgetSnapshot(shifts: [PlannedShift]) {
        let dir = NSHomeDirectory() + "/Library/Group Containers/group.com.shiftly.app"
        let dayFormat = Date.FormatStyle().weekday(.abbreviated).day().month(.abbreviated)
        var payload: [String: Any] = [
            "label": L("Next shift"),
            "time": "—",
            "sub": L("No upcoming shift in the next 45 days"),
            "recording": isRecording,
            "upcoming": shifts.prefix(4).map { shift in
                [
                    "day": shift.start.formatted(dayFormat),
                    "time": "\(SyncFingerprint.hhmmString(for: shift.start)) – \(SyncFingerprint.hhmmString(for: shift.end))",
                ]
            },
        ]
        if let next = shifts.first {
            payload["time"] = SyncFingerprint.hhmmString(for: next.start)
            payload["sub"] = next.start > Date()
                ? "\(next.start.formatted(dayFormat)) · \(next.start.formatted(.relative(presentation: .named)))"
                : L("in progress")
        }
        do {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            try data.write(to: URL(fileURLWithPath: dir + "/widget.json"), options: .atomic)
        } catch {
            return // widgets just keep their last snapshot
        }
        if #available(macOS 14.0, *) {
            WidgetCenter.shared.reloadAllTimelines()
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

    @discardableResult
    func saveSchedule() -> Bool {
        guard !selectedDays.isEmpty else {
            statusMessage = L("Select at least one workday, then save.")
            return false
        }
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
            // Disk now matches the editor; reloads may refresh it again.
            scheduleEditorDirty = false
            syncState = .unsynced
            statusMessage = L("Schedule saved.")
            refreshNextShift()
            if autoLaunchMode == .workdays { applyAutoLaunch() }
            return true
        } catch {
            statusMessage = LF("Save failed: %@", error.localizedDescription)
            return false
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
                    let stateStore = SyncStateStore(paths: syncPaths)
                    let calendar = try EKCalendarStore.locateOrCreateCalendar(
                        named: config.calendar_name, in: ekStore,
                        preferredID: stateStore.load().calendar_id
                    )
                    let coordinator = SyncCoordinator(
                        store: store,
                        stateStore: stateStore,
                        calendar: EKCalendarStore(eventStore: ekStore, calendar: calendar),
                        provider: PlannerScriptProvider(root: root),
                        calendarIdentifier: calendar.calendarIdentifier
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
        if saveSchedule() {
            syncNow()
        }
    }

    // MARK: Today quick adjustments

    /// One-click "not working today": a single-day leave, synced right away.
    func takeLeaveToday() {
        leaveStart = Date()
        leaveEnd = Date()
        addLeaveAndSync()
    }

    /// Move today's shift to another day: a swap, synced right away.
    func swapToday(to target: Date) {
        swapFrom = Date()
        swapTo = target
        addSwapAndSync()
    }

    func addSwapAndSync() {
        addSwap()
        syncNow()
    }

    // MARK: Holidays

    @discardableResult
    func addHoliday() -> Bool {
        noteOwnWrite()
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        var start = df.string(from: holidayStart)
        var end = df.string(from: holidayEnd)
        if end < start { swap(&start, &end) }
        guard !holidays.contains(where: { $0.start_date == start && $0.end_date == end }) else {
            statusMessage = L("This holiday range already exists.")
            return false
        }
        do {
            var list = store.loadHolidays()
            list.append(HolidayItem(
                start_date: start,
                end_date: end,
                name: holidayName.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
            try store.saveHolidays(list)
            holidays = store.loadHolidays()
            holidayName = ""
            syncState = .unsynced
            statusMessage = L("Holiday added.")
            return true
        } catch {
            statusMessage = LF("Holiday save failed: %@", error.localizedDescription)
            return false
        }
    }

    func addHolidayAndSync() {
        if addHoliday() {
            syncNow()
        }
    }

    func deleteHoliday(id: UUID) {
        guard let item = holidays.first(where: { $0.id == id }) else { return }
        noteOwnWrite()
        do {
            var list = store.loadHolidays()
            list.removeAll { $0 == item }
            try store.saveHolidays(list)
            holidays = store.loadHolidays()
            syncState = .unsynced
            statusMessage = L("Holiday removed.")
        } catch {
            statusMessage = LF("Holiday save failed: %@", error.localizedDescription)
        }
    }

    /// Import every day of a calendar (e.g. a subscribed public-holidays
    /// calendar) as holidays, a couple of years ahead and the past for
    /// correct work-history counting. Existing dates are kept.
    func importHolidays(calendarID: String) {
        guard !holidayImportRunning, paths.isValid else { return }
        holidayImportRunning = true
        noteOwnWrite()
        let syncPaths = paths
        let existing = store.loadHolidays()
        Task { @MainActor in
            defer { holidayImportRunning = false }
            let ekStore = EKEventStore()
            guard await CalendarAccess.request(using: ekStore) else {
                statusMessage = L("Calendar access denied. Grant access in System Settings → Privacy & Security → Calendars, then sync again.")
                return
            }
            let added: Int? = await Task.detached(priority: .userInitiated) {
                let until = Calendar.current.date(byAdding: .year, value: 2, to: Date()) ?? Date()
                let events = HistoryImporter.fetchEvents(
                    calendarID: calendarID, in: ekStore, until: until
                )
                let (merged, added) = HistoryImporter.holidays(from: events, existing: existing)
                do {
                    try DataStore(paths: syncPaths).saveHolidays(merged)
                    return added
                } catch {
                    return nil
                }
            }.value
            noteOwnWrite()
            if let added {
                load()
                syncState = .unsynced
                statusMessage = LF("Imported %lld holidays.", added)
            } else {
                statusMessage = L("Holiday import failed.")
            }
        }
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
            // The active daily-log date depends on the latest workday.
            refreshLogState()
        }
    }

    private func loadConfig() {
        do {
            let config = try store.loadConfig()
            if config.calendar_name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                statusMessage = L("Config invalid: calendar_name is empty.")
                return
            }
            calendarName = config.calendar_name
            eventTitle = config.event_title
            let sorted = config.rules.sorted { $0.effective_from < $1.effective_from }
            rules = sorted
            shiftTypes = config.shift_types ?? []
            // Refresh the editor from disk only while it has no in-progress
            // edits. Edit the newest rule; older ones are history.
            if !scheduleEditorDirty {
                applyingConfig = true
                startTime = config.default_start_time
                endTime = config.default_end_time
                if let latest = sorted.last {
                    selectedDays = Set(latest.workdays)
                    selectedShiftType = latest.shift_type
                    let df = DateFormatter()
                    df.dateFormat = "yyyy-MM-dd"
                    effectiveFrom = df.date(from: latest.effective_from) ?? Date()
                }
                applyingConfig = false
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

    // MARK: History import (Apple Calendar → manual_shifts)

    /// Load the calendar list for the import picker (asks for calendar
    /// access if needed).
    func loadImportCalendars() {
        Task { @MainActor in
            let ekStore = EKEventStore()
            guard await CalendarAccess.request(using: ekStore) else {
                statusMessage = L("Calendar access denied. Grant access in System Settings → Privacy & Security → Calendars, then sync again.")
                showSettingsHint = true
                return
            }
            importCalendars = HistoryImporter.calendars(in: ekStore)
                .map { ImportCalendar(id: $0.id, title: $0.title) }
        }
    }

    /// Import every past event of the chosen calendar as worked shifts
    /// (real start/end times). Existing dates are never overwritten.
    func importHistory(calendarID: String) {
        guard !importRunning, paths.isValid else { return }
        importRunning = true
        noteOwnWrite()
        let syncPaths = paths
        Task { @MainActor in
            defer { importRunning = false }
            let ekStore = EKEventStore()
            guard await CalendarAccess.request(using: ekStore) else {
                statusMessage = L("Calendar access denied. Grant access in System Settings → Privacy & Security → Calendars, then sync again.")
                return
            }
            let today = Self.todayYMD()
            let cfg = try? DataStore(paths: syncPaths).loadConfig()
            let (defaultStart, defaultEnd) = (
                cfg?.default_start_time ?? "09:00",
                cfg?.default_end_time ?? "17:00"
            )
            let summary: HistoryImporter.Summary? = await Task.detached(priority: .userInitiated) {
                let events = HistoryImporter.fetchEvents(
                    calendarID: calendarID, in: ekStore, until: Date()
                )
                let (shifts, merged) = HistoryImporter.shifts(
                    from: events, before: today,
                    defaultStart: defaultStart, defaultEnd: defaultEnd
                )
                return try? HistoryImporter.apply(
                    shifts, mergedDays: merged, to: DataStore(paths: syncPaths)
                )
            }.value
            noteOwnWrite()
            if let summary {
                load()
                var text = LF("Imported %lld days of history.", summary.imported)
                if summary.skippedExisting > 0 {
                    text += " " + LF("%lld already present, kept as they were.", summary.skippedExisting)
                }
                if summary.mergedDays > 0 {
                    text += " " + LF("%lld days had multiple events and were merged into one span.", summary.mergedDays)
                }
                statusMessage = text
            } else {
                statusMessage = L("History import failed.")
            }
        }
    }

    // MARK: Menu bar (AppKit NSStatusItem; see MenuBarController)

    private lazy var menuBar = MenuBarController(model: self)

    var menuBarEnabled: Bool {
        UserDefaults.standard.bool(forKey: menuBarEnabledKey)
    }

    /// Apply the stored preference at launch.
    func applyMenuBarPreference() {
        menuBar.setEnabled(menuBarEnabled)
    }

    func setMenuBarEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: menuBarEnabledKey)
        menuBar.setEnabled(enabled)
        objectWillChange.send()
    }

    // MARK: Auto-launch (SMAppService at login, or a launchd agent that
    // opens Shiftly on workdays at a set time; bundled Shiftly.app only)

    enum AutoLaunchMode: String { case off, login, workdays }

    static let autoLaunchModeKey = "shiftly.autoLaunchMode"
    static let workdayLaunchMinutesKey = "shiftly.workdayLaunchMinutes"

    @Published var autoLaunchMode: AutoLaunchMode = {
        if let raw = UserDefaults.standard.string(forKey: AppModel.autoLaunchModeKey),
           let mode = AutoLaunchMode(rawValue: raw) {
            return mode
        }
        // Back-compat: a pre-existing login item reads as .login.
        return SMAppService.mainApp.status == .enabled ? .login : .off
    }()

    /// Time of day the workday agent fires (defaults to 09:00).
    @Published var workdayLaunchTime: Date = {
        let minutes = UserDefaults.standard.object(forKey: AppModel.workdayLaunchMinutesKey) as? Int ?? 540
        return Calendar.current.date(
            bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()
        ) ?? Date()
    }()

    /// Workdays of the schedule going forward (the latest rule's days).
    var currentWorkdays: [String] {
        rules.max(by: { $0.effective_from < $1.effective_from })?.workdays ?? []
    }

    func setAutoLaunchMode(_ mode: AutoLaunchMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: Self.autoLaunchModeKey)
        autoLaunchMode = mode
        applyAutoLaunch()
    }

    func setWorkdayLaunchTime(_ date: Date) {
        workdayLaunchTime = date
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        UserDefaults.standard.set((c.hour ?? 9) * 60 + (c.minute ?? 0), forKey: Self.workdayLaunchMinutesKey)
        if autoLaunchMode == .workdays { applyAutoLaunch() }
    }

    /// Re-run whenever the mode, time, or workdays change so the launchd
    /// agent always mirrors the current schedule.
    func applyAutoLaunch() {
        switch autoLaunchMode {
        case .off:
            try? SMAppService.mainApp.unregister()
            WorkdayLauncher.uninstall()
        case .login:
            WorkdayLauncher.uninstall()
            do {
                try SMAppService.mainApp.register()
            } catch {
                statusMessage = LF("Launch at login unavailable: %@ (requires the bundled Shiftly.app)", error.localizedDescription)
            }
        case .workdays:
            try? SMAppService.mainApp.unregister()
            let c = Calendar.current.dateComponents([.hour, .minute], from: workdayLaunchTime)
            WorkdayLauncher.install(
                appBundlePath: Bundle.main.bundlePath,
                workdays: currentWorkdays,
                hour: c.hour ?? 9, minute: c.minute ?? 0
            )
        }
    }
}
