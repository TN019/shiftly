import Foundation
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

    let paths = ShiftlyPaths.shared
    private let store = DataStore()

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
        refreshWorkHistory()
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
            let outcome = await Task.detached(priority: .userInitiated) {
                SyncScriptRunner.run(root: root, scriptPath: path)
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
}
