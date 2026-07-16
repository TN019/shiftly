import SwiftUI
import Foundation
import AppKit

struct ShiftlyPaths {
    static let shared = ShiftlyPaths()

    let root: String

    private init() {
        root = Self.resolveRoot()
    }

    var isValid: Bool { !root.isEmpty }

    var configPath: String { "\(root)/data/config.json" }
    var swapsPath: String { "\(root)/data/swaps.json" }
    var leavePath: String { "\(root)/data/leave.json" }
    var syncScriptPath: String { "\(root)/scripts/sync.applescript" }
    var metaPath: String { "\(root)/data/meta.json" }
    var workHistoryScript: String { "\(root)/scripts/work_history.py" }

    private static func resolveRoot() -> String {
        if let e = Self.rootFromEnvironment() {
            return e
        }
        if let r = findRepoRoot(from: executableDirectory()) {
            return r
        }
        if let r = findRepoRoot(from: URL(fileURLWithPath: #filePath).deletingLastPathComponent()) {
            return r
        }
        return ""
    }

    private static func rootFromEnvironment() -> String? {
        for key in ["SHIFTLY_ROOT", "SHIFTY_ROOT", "SHIFTFLOW_ROOT"] {
            if let e = ProcessInfo.processInfo.environment[key], !e.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return (e as NSString).standardizingPath
            }
        }
        return nil
    }

    private static func executableDirectory() -> URL {
        let path = Bundle.main.executablePath
            ?? ProcessInfo.processInfo.arguments.first
            ?? "/"
        return URL(fileURLWithPath: path).deletingLastPathComponent().standardizedFileURL
    }

    private static func findRepoRoot(from start: URL) -> String? {
        var url = start.standardizedFileURL
        for _ in 0..<16 {
            let example = url.appendingPathComponent("data/config.example.json")
            let cfg = url.appendingPathComponent("data/config.json")
            if FileManager.default.fileExists(atPath: example.path) || FileManager.default.fileExists(atPath: cfg.path) {
                return url.path
            }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { break }
            url = parent
        }
        return nil
    }

    static func applyRepoRootEnvironment(_ env: inout [String: String], root: String) {
        env["SHIFTLY_ROOT"] = root
        // Legacy names kept for scripts that still read them.
        env["SHIFTY_ROOT"] = root
        env["SHIFTFLOW_ROOT"] = root
    }
}

struct Rule: Codable {
    var effective_from: String
    var workdays: [String]
}

struct Config: Codable {
    var config_version: Int?
    var calendar_name: String
    var event_title: String
    var default_start_time: String
    var default_end_time: String
    var history_csv: String?
    var setup_completed: Bool?
    var rules: [Rule]
}

struct SwapItem: Codable, Identifiable {
    // Stable in-memory identity; not part of the JSON file format.
    var id = UUID()
    var from_date: String
    var to_date: String

    private enum CodingKeys: String, CodingKey {
        case from_date, to_date
    }
}

struct LeaveItem: Codable, Identifiable {
    var id = UUID()
    var start_date: String
    var end_date: String

    private enum CodingKeys: String, CodingKey {
        case start_date, end_date
    }
}

struct Meta: Codable {
    var last_sync_at: String
    var last_sync_status: String
}

enum SyncState {
    case synced
    case unsynced
    case error(String)
}

struct WorkHistoryRow: Codable, Identifiable {
    var id: String { ymd }
    let ymd: String
    let ordinal: Int
}

enum WorkHistoryScriptRunner {
    static func run(root: String, scriptPath: String) -> (rows: [WorkHistoryRow], note: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        proc.arguments = [scriptPath]
        var env = ProcessInfo.processInfo.environment
        ShiftlyPaths.applyRepoRootEnvironment(&env, root: root)
        proc.environment = env
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        do {
            try proc.run()
            proc.waitUntilExit()
            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            let errText = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            if proc.terminationStatus != 0 {
                return ([], errText.isEmpty ? "work_history.py failed." : errText.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            let rows = try JSONDecoder().decode([WorkHistoryRow].self, from: outData)
            return (rows, "")
        } catch {
            return ([], error.localizedDescription)
        }
    }

}

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

    private let paths = ShiftlyPaths.shared

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
        loadSwaps()
        loadLeaves()
        loadMeta()
        refreshWorkHistory()
    }

    func saveSchedule() {
        do {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            // Merge into the raw dictionary: unknown keys survive, and the
            // rule history is upserted instead of overwritten.
            let raw = try ConfigLogic.readRawConfig(atPath: paths.configPath)
            let merged = ConfigLogic.mergeSchedule(
                into: raw,
                startTime: startTime,
                endTime: endTime,
                effectiveFrom: df.string(from: effectiveFrom),
                workdays: dayOrder.filter { selectedDays.contains($0) }
            )
            try ConfigLogic.writeRawConfig(merged, toPath: paths.configPath)
            rulesSummary = Self.rulesSummary(from: (merged["rules"] as? [[String: Any]])?.compactMap {
                guard let ef = $0["effective_from"] as? String else { return nil }
                return Rule(effective_from: ef, workdays: ($0["workdays"] as? [String]) ?? [])
            } ?? [])
            syncState = .unsynced
            statusMessage = "Schedule saved."
        } catch {
            statusMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    func addSwap() {
        do {
            var list = try readSwaps()
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            list.append(SwapItem(from_date: df.string(from: swapFrom), to_date: df.string(from: swapTo)))
            try writeJSON(list, to: paths.swapsPath)
            swaps = list
            syncState = .unsynced
            statusMessage = "Swap added."
        } catch {
            statusMessage = "Add swap failed: \(error.localizedDescription)"
        }
    }

    func addLeave() {
        do {
            var list = try readLeaves()
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            list.append(LeaveItem(start_date: df.string(from: leaveStart), end_date: df.string(from: leaveEnd)))
            try writeJSON(list, to: paths.leavePath)
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
            try writeJSON(swaps, to: paths.swapsPath)
            syncState = .unsynced
        } catch {
            statusMessage = "Delete swap failed: \(error.localizedDescription)"
        }
    }

    func deleteLeave(id: UUID) {
        guard leaves.contains(where: { $0.id == id }) else { return }
        leaves.removeAll { $0.id == id }
        do {
            try writeJSON(leaves, to: paths.leavePath)
            syncState = .unsynced
        } catch {
            statusMessage = "Delete leave failed: \(error.localizedDescription)"
        }
    }

    func syncNow() {
        guard !isBusy else { return }
        guard paths.isValid else {
            statusMessage = "Cannot sync: repo path not resolved."
            return
        }
        isBusy = true
        busyMessage = "Syncing with Calendar…"
        let path = paths.syncScriptPath
        let root = paths.root
        Task { @MainActor in
            let outcome: (ok: Bool, err: String) = await Task.detached(priority: .userInitiated) {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                proc.arguments = [path]
                var env = ProcessInfo.processInfo.environment
                ShiftlyPaths.applyRepoRootEnvironment(&env, root: root)
                proc.environment = env
                let pipe = Pipe()
                proc.standardError = pipe
                do {
                    try proc.run()
                    proc.waitUntilExit()
                    if proc.terminationStatus == 0 {
                        return (true, "")
                    }
                    let msg = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "sync error"
                    return (false, msg)
                } catch {
                    return (false, error.localizedDescription)
                }
            }.value
            isBusy = false
            busyMessage = ""
            if outcome.ok {
                syncState = .synced
                statusMessage = "Synced."
                loadMeta()
                refreshWorkHistory()
            } else {
                syncState = .error(outcome.err)
                statusMessage = "Sync failed."
            }
        }
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

    private func loadConfig() {
        do {
            let config = try readConfig()
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

    private func loadSwaps() {
        swaps = (try? readSwaps()) ?? []
    }

    private func loadLeaves() {
        leaves = (try? readLeaves()) ?? []
    }

    func refreshWorkHistory() {
        guard paths.isValid else {
            workHistory = []
            workHistoryNote = ""
            return
        }
        let root = paths.root
        let script = paths.workHistoryScript
        Task { @MainActor in
            let result = await Task.detached(priority: .utility) {
                WorkHistoryScriptRunner.run(root: root, scriptPath: script)
            }.value
            workHistory = result.rows
            workHistoryNote = result.note
        }
    }

    private func loadMeta() {
        guard let data = FileManager.default.contents(atPath: paths.metaPath),
              let meta = try? JSONDecoder().decode(Meta.self, from: data) else { return }
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

    private func readConfig() throws -> Config {
        let data = try Data(contentsOf: URL(fileURLWithPath: paths.configPath))
        return try JSONDecoder().decode(Config.self, from: data)
    }

    private func readSwaps() throws -> [SwapItem] {
        let data = try Data(contentsOf: URL(fileURLWithPath: paths.swapsPath))
        return try JSONDecoder().decode([SwapItem].self, from: data)
    }

    private func readLeaves() throws -> [LeaveItem] {
        let data = try Data(contentsOf: URL(fileURLWithPath: paths.leavePath))
        return try JSONDecoder().decode([LeaveItem].self, from: data)
    }

    private func writeJSON<T: Encodable>(_ value: T, to path: String) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(value)
        try data.write(to: URL(fileURLWithPath: path))
    }
}

struct ContentView: View {
    @StateObject private var model = AppModel()
    @FocusState private var timeFocus: TimeField?
    @FocusState private var historySearchFocused: Bool
    @State private var overridesListExpanded = false
    @State private var historyExpanded = false
    @State private var historyDateSearch = ""
    @State private var historyPeriod: HistoryPeriodFilter = .all
    @State private var historyRangeFrom = Date()
    @State private var historyRangeTo = Date()
    @State private var historyWeekdayFilter: Set<Int> = []
    @State private var historyNewestFirst = false
    @State private var historyActiveTool: HistoryTool? = nil

    private enum TimeField: Hashable {
        case start
        case end
    }

    private enum HistoryTool: Int, CaseIterable, Identifiable {
        case period
        case sort
        case quick
        case search
        case weekday

        var id: Int { rawValue }

        var systemImage: String {
            switch self {
            case .period: return "line.3.horizontal.decrease.circle"
            case .sort: return "arrow.up.arrow.down"
            case .quick: return "bolt.fill"
            case .search: return "magnifyingglass"
            case .weekday: return "slider.horizontal.3"
            }
        }

        var helpText: String {
            switch self {
            case .period: return "Time period"
            case .sort: return "Sort order"
            case .quick: return "Quick range"
            case .search: return "Search by date"
            case .weekday: return "Weekday"
            }
        }
    }

    private enum HistoryPeriodFilter: String, CaseIterable, Identifiable {
        case all = "All time"
        case thisWeek = "This week"
        case thisMonth = "This month"
        case custom = "Custom range"
        var id: String { rawValue }
    }

    private var startOfToday: Date {
        Calendar.current.startOfDay(for: Date())
    }

    private func localDateFromISO(_ iso: String) -> Date? {
        let trimmed = iso.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        var comps = DateComponents()
        comps.year = y
        comps.month = m
        comps.day = d
        return Calendar.current.date(from: comps)
    }

    private func isSwapPast(_ item: SwapItem) -> Bool {
        guard let f = localDateFromISO(item.from_date), let t = localDateFromISO(item.to_date) else { return false }
        return max(f, t) < startOfToday
    }

    private func isLeavePast(_ item: LeaveItem) -> Bool {
        guard let end = localDateFromISO(item.end_date) else { return false }
        return end < startOfToday
    }

    private var visibleSwaps: [SwapItem] {
        model.swaps.filter { !isSwapPast($0) }
    }

    private var visibleLeaves: [LeaveItem] {
        model.leaves.filter { !isLeavePast($0) }
    }

    private var overridesVisibleCount: Int {
        visibleSwaps.count + visibleLeaves.count
    }

    private var historyPeriodBounds: (start: Date, end: Date)? {
        let cal = Calendar.current
        let today = Date()
        switch historyPeriod {
        case .all:
            return nil
        case .thisWeek:
            guard let iv = cal.dateInterval(of: .weekOfYear, for: today) else { return nil }
            let s = cal.startOfDay(for: iv.start)
            guard let last = cal.date(byAdding: .day, value: 6, to: s) else { return nil }
            return (s, cal.startOfDay(for: last))
        case .thisMonth:
            let c = cal.dateComponents([.year, .month], from: today)
            guard let monthStart = cal.date(from: c),
                  let monthRange = cal.range(of: .day, in: .month, for: monthStart),
                  let endDay = cal.date(byAdding: .day, value: monthRange.count - 1, to: monthStart) else { return nil }
            return (cal.startOfDay(for: monthStart), cal.startOfDay(for: endDay))
        case .custom:
            let a = cal.startOfDay(for: historyRangeFrom)
            let b = cal.startOfDay(for: historyRangeTo)
            return a <= b ? (a, b) : (b, a)
        }
    }

    private func historyRowDate(_ row: WorkHistoryRow) -> Date? {
        localDateFromISO(row.ymd)
    }

    private func historyDateInPeriod(_ row: WorkHistoryRow) -> Bool {
        guard let bounds = historyPeriodBounds else { return true }
        guard let d = historyRowDate(row) else { return false }
        let cal = Calendar.current
        let ds = cal.startOfDay(for: d)
        return ds >= bounds.start && ds <= bounds.end
    }

    private var filteredWorkHistory: [WorkHistoryRow] {
        var rows = model.workHistory
        let q = historyDateSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            rows = rows.filter { $0.ymd.localizedCaseInsensitiveContains(q) }
        }
        rows = rows.filter { historyDateInPeriod($0) }
        if !historyWeekdayFilter.isEmpty {
            rows = rows.filter { row in
                guard let d = historyRowDate(row) else { return false }
                let wd = Calendar.current.component(.weekday, from: d)
                return historyWeekdayFilter.contains(wd)
            }
        }
        return rows.sorted { a, b in
            guard let da = historyRowDate(a), let db = historyRowDate(b) else {
                return a.ymd < b.ymd
            }
            if historyNewestFirst { return da > db }
            return da < db
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(nsColor: .windowBackgroundColor), Color(nsColor: .underPageBackgroundColor)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    weeklySection
                    overridesSection
                    historySection
                    actions
                    if !model.statusMessage.isEmpty {
                        Text(model.statusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                    Color.clear
                        .frame(minHeight: 120)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            resignAllFocus()
                        }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 780)
            .onExitCommand {
                resignAllFocus()
            }
            .onAppear {
                model.load()
                DispatchQueue.main.async {
                    resignAllFocus()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    resignAllFocus()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    resignAllFocus()
                }
            }

            if model.isBusy {
                Color.black.opacity(0.38)
                    .ignoresSafeArea()
                    .allowsHitTesting(true)
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                        .controlSize(.large)
                    Text(model.busyMessage.isEmpty ? "Working…" : model.busyMessage)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)
                }
                .padding(32)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.ultraThickMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
            }
        }
    }

    private func resignAllFocus() {
        timeFocus = nil
        historySearchFocused = false
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Shiftly").font(.title2).bold()
                Text("Shifts calendar scheduler")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
                .contentShape(Rectangle())
                .frame(minHeight: 48)
                .onTapGesture {
                    resignAllFocus()
                }
            HStack(spacing: 8) {
                Circle().fill(statusColor).frame(width: 9, height: 9)
                Text(statusLabel).fontWeight(.semibold)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.thinMaterial, in: Capsule())

            Text("Last Sync: \(model.lastSyncText)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
        .padding(.bottom, 4)
    }

    private var weeklySection: some View {
        card("Weekly Schedule") {
            if !model.rulesSummary.isEmpty {
                Text(model.rulesSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                ForEach(model.dayOrder, id: \.self) { code in
                    let isSelected = model.selectedDays.contains(code)
                    Button(model.dayLabels[code] ?? code) {
                        if model.selectedDays.contains(code) { model.selectedDays.remove(code) } else { model.selectedDays.insert(code) }
                    }
                    .buttonStyle(.plain)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.16), in: Capsule())
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                }
                Spacer(minLength: 0)
                    .contentShape(Rectangle())
                    .frame(minHeight: 40)
                    .onTapGesture {
                        resignAllFocus()
                    }
            }
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Start").font(.caption).foregroundStyle(.secondary)
                    TextField("10:00", text: $model.startTime)
                        .frame(width: 86)
                        .focused($timeFocus, equals: .start)
                        .onSubmit { resignAllFocus() }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("End").font(.caption).foregroundStyle(.secondary)
                    TextField("18:30", text: $model.endTime)
                        .frame(width: 86)
                        .focused($timeFocus, equals: .end)
                        .onSubmit { resignAllFocus() }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Effective From").font(.caption).foregroundStyle(.secondary)
                    styledDatePicker($model.effectiveFrom)
                }
                Spacer(minLength: 0)
                    .contentShape(Rectangle())
                    .frame(minHeight: 44)
                    .onTapGesture {
                        resignAllFocus()
                    }
            }
            HStack {
                Button("Save") { model.saveSchedule() }
                    .buttonStyle(.bordered)
                    .disabled(model.isBusy)
                Button("Save + Sync") {
                    model.saveScheduleAndSync()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isBusy)
            }
        }
        .environment(\.isEnabled, !model.isBusy)
    }

    private var overridesSection: some View {
        card("Overrides") {
            HStack(alignment: .center, spacing: 10) {
                Text("Swap")
                    .font(.subheadline.weight(.medium))
                    .frame(width: 48, alignment: .leading)
                    .foregroundStyle(.secondary)
                styledDatePicker($model.swapFrom)
                flowArrowSwap()
                styledDatePicker($model.swapTo)
                Button {
                    model.addSwapAndSync()
                } label: {
                    Label("Add", systemImage: "plus.circle.fill")
                }
                .labelStyle(.titleAndIcon)
                .buttonStyle(.bordered)
                .disabled(model.isBusy)
                Spacer(minLength: 0)
                    .contentShape(Rectangle())
                    .frame(minHeight: 36)
                    .onTapGesture {
                        resignAllFocus()
                    }
            }
            HStack(alignment: .center, spacing: 10) {
                Text("Leave")
                    .font(.subheadline.weight(.medium))
                    .frame(width: 48, alignment: .leading)
                    .foregroundStyle(.secondary)
                styledDatePicker($model.leaveStart)
                flowArrowRange()
                styledDatePicker($model.leaveEnd)
                Button {
                    model.addLeaveAndSync()
                } label: {
                    Label("Add", systemImage: "plus.circle.fill")
                }
                .labelStyle(.titleAndIcon)
                .buttonStyle(.bordered)
                .disabled(model.isBusy)
                Spacer(minLength: 0)
                    .contentShape(Rectangle())
                    .frame(minHeight: 36)
                    .onTapGesture {
                        resignAllFocus()
                    }
            }

            DisclosureGroup(isExpanded: $overridesListExpanded) {
                if overridesVisibleCount == 0 {
                    Text("None")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .italic()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(visibleSwaps) { item in
                                overrideSwapRow(item: item)
                            }
                            ForEach(visibleLeaves) { item in
                                overrideLeaveRow(item: item)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .frame(maxHeight: 240)
                }
            } label: {
                HStack(spacing: 8) {
                    Text("Current Overrides")
                        .font(.subheadline.weight(.medium))
                    Text("(\(overridesVisibleCount))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }
            .padding(.top, 4)
        }
        .environment(\.isEnabled, !model.isBusy)
    }

    private var historySection: some View {
        card("") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            historyExpanded.toggle()
                            if !historyExpanded {
                                historyActiveTool = nil
                                historySearchFocused = false
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: historyExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                                .frame(width: 14, alignment: .center)
                            Text("Work History")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                    Button("Refresh") {
                        model.refreshWorkHistory()
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isBusy || !ShiftlyPaths.shared.isValid)
                }

                if historyExpanded {
                    HStack {
                        Spacer(minLength: 0)
                        HStack(spacing: 4) {
                            ForEach(HistoryTool.allCases) { tool in
                                historyToolIconButton(tool)
                            }
                        }
                    }

                    if let tool = historyActiveTool {
                        historyToolPanel(tool)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.white.opacity(0.06))
                            )
                    }

                    if !model.workHistoryNote.isEmpty {
                        Text(model.workHistoryNote)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    if model.workHistory.isEmpty && model.workHistoryNote.isEmpty && ShiftlyPaths.shared.isValid {
                        Text("No entries.")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    } else if !model.workHistory.isEmpty && filteredWorkHistory.isEmpty {
                        Text("No matches for current filters.")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    } else if !filteredWorkHistory.isEmpty {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                ForEach(filteredWorkHistory) { row in
                                    HStack(spacing: 12) {
                                        Text("Day \(row.ordinal)")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.tertiary)
                                            .frame(width: 72, alignment: .leading)
                                        Text(row.ymd)
                                            .font(.system(.body, design: .rounded).monospacedDigit())
                                        Spacer(minLength: 0)
                                        Text(weekdayLabel(forYMD: row.ymd))
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(Color.white.opacity(0.05))
                                    )
                                }
                            }
                        }
                        .frame(maxHeight: 240)
                    }
                }
            }
        }
        .environment(\.isEnabled, !model.isBusy)
    }

    private func historyToolIconButton(_ tool: HistoryTool) -> some View {
        let on = historyActiveTool == tool
        return Button {
            if historyActiveTool == tool {
                historyActiveTool = nil
                historySearchFocused = false
            } else {
                historyActiveTool = tool
                if tool == .search {
                    DispatchQueue.main.async {
                        NSApp.activate(ignoringOtherApps: true)
                        historySearchFocused = true
                    }
                } else {
                    historySearchFocused = false
                }
            }
        } label: {
            Image(systemName: tool.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(on ? Color.accentColor : Color.secondary)
                .frame(width: 30, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(on ? Color.accentColor.opacity(0.18) : Color.white.opacity(0.05))
                )
        }
        .buttonStyle(.plain)
        .help(tool.helpText)
    }

    @ViewBuilder
    private func historyToolPanel(_ tool: HistoryTool) -> some View {
        switch tool {
        case .period:
            HStack(alignment: .center, spacing: 10) {
                Text("Range").font(.caption).foregroundStyle(.secondary)
                Picker("Range", selection: $historyPeriod) {
                    ForEach(HistoryPeriodFilter.allCases) { p in
                        Text(p.rawValue).tag(p)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(minWidth: 140, alignment: .leading)
                if historyPeriod == .custom {
                    Text("From").font(.caption).foregroundStyle(.secondary)
                    styledDatePicker($historyRangeFrom)
                    Text("To").font(.caption).foregroundStyle(.secondary)
                    styledDatePicker($historyRangeTo)
                }
                Spacer(minLength: 0)
            }
        case .sort:
            HStack(spacing: 10) {
                Text("Order").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $historyNewestFirst) {
                    Text("Oldest first").tag(false)
                    Text("Newest first").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
                Spacer(minLength: 0)
            }
        case .quick:
            HStack(spacing: 8) {
                Button("This week") { historyPeriod = .thisWeek }
                    .buttonStyle(.bordered)
                Button("This month") { historyPeriod = .thisMonth }
                    .buttonStyle(.bordered)
                Button("All time") { historyPeriod = .all }
                    .buttonStyle(.bordered)
                Spacer(minLength: 0)
            }
        case .search:
            TextField("Search by date (e.g. 2026-04)", text: $historyDateSearch)
                .textFieldStyle(.roundedBorder)
                .focused($historySearchFocused)
                .frame(maxWidth: .infinity)
        case .weekday:
            HStack(spacing: 6) {
                ForEach(0 ..< 7, id: \.self) { idx in
                    let wd = idx + 1
                    let sym = Calendar.current.shortStandaloneWeekdaySymbols[wd - 1]
                    let on = historyWeekdayFilter.contains(wd)
                    Button(sym) {
                        if on { historyWeekdayFilter.remove(wd) } else { historyWeekdayFilter.insert(wd) }
                    }
                    .buttonStyle(.plain)
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(on ? Color.accentColor : Color.secondary.opacity(0.16), in: Capsule())
                    .foregroundStyle(on ? Color.white : Color.primary)
                }
            }
        }
    }

    private func weekdayLabel(forYMD ymd: String) -> String {
        let parts = ymd.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return "—" }
        var comps = DateComponents()
        comps.year = parts[0]
        comps.month = parts[1]
        comps.day = parts[2]
        guard let date = Calendar.current.date(from: comps) else { return "—" }
        let f = DateFormatter()
        f.locale = .current
        f.dateFormat = "EEEE"
        return f.string(from: date)
    }

    @ViewBuilder
    private func overrideSwapRow(item: SwapItem) -> some View {
        HStack(spacing: 8) {
            Text("Swap")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.white.opacity(0.08)))
            Text(displayDate(fromISO: item.from_date))
                .font(.system(.body, design: .rounded).weight(.medium).monospacedDigit())
            Image(systemName: "arrow.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
            Text(displayDate(fromISO: item.to_date))
                .font(.system(.body, design: .rounded).weight(.medium).monospacedDigit())
            Spacer()
            Button(role: .destructive) {
                model.deleteSwap(id: item.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove swap")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    @ViewBuilder
    private func overrideLeaveRow(item: LeaveItem) -> some View {
        HStack(spacing: 8) {
            Text("Leave")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.white.opacity(0.08)))
            Text(displayDate(fromISO: item.start_date))
                .font(.system(.body, design: .rounded).weight(.medium).monospacedDigit())
            Image(systemName: "arrow.left.and.line.vertical.and.arrow.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            Text(displayDate(fromISO: item.end_date))
                .font(.system(.body, design: .rounded).weight(.medium).monospacedDigit())
            Spacer()
            Button(role: .destructive) {
                model.deleteLeave(id: item.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove leave")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    private var actions: some View {
        card("") {
            HStack {
                Button("Sync Now") { model.syncNow() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isBusy)
                Button("Open Calendar") { model.openCalendar() }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Refresh") { model.load() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(model.isBusy)
            }
        }
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !title.isEmpty {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            content()
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var statusColor: Color {
        switch model.syncState {
        case .synced: return .green
        case .unsynced: return .orange
        case .error: return .red
        }
    }

    private var statusLabel: String {
        switch model.syncState {
        case .synced: return "Synced"
        case .unsynced: return "Unsynced"
        case .error(let msg):
            return msg.isEmpty ? "Error" : "Error"
        }
    }

    @ViewBuilder
    private func styledDatePicker(_ selection: Binding<Date>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            DatePicker("", selection: selection, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
    }

    private func flowArrowSwap() -> some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(.secondary)
            .frame(width: 28, height: 28)
            .background(Circle().fill(Color.white.opacity(0.08)))
    }

    private func flowArrowRange() -> some View {
        Image(systemName: "arrow.left.and.line.vertical.and.arrow.right")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .frame(width: 28, height: 28)
            .background(Circle().fill(Color.white.opacity(0.08)))
    }

    private static let isoParser: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    private func displayDate(fromISO iso: String) -> String {
        guard let d = Self.isoParser.date(from: iso) else { return iso }
        return d.formatted(date: .abbreviated, time: .omitted)
    }
}

final class ShiftlyAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct ShiftlyAppMain: App {
    @NSApplicationDelegateAdaptor(ShiftlyAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 840, height: 780)
    }
}
