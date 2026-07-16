import Foundation

/// Supplies the planned schedule dates and the sync window. The production
/// implementation shells out to scripts/planner.py so the rule/swap/leave
/// algorithm keeps its single source of truth in schedule_core.py; the Swift
/// side only overlays the data the Python planner does not know about
/// (manual shifts and per-day time overrides).
public protocol ScheduleProvider {
    /// Planned auto-shift dates (YYYY-MM-DD) in [start, end].
    func plannedDates(start: String, end: String) throws -> [String]
    /// Sync window as (first, last) dates.
    func syncRange() throws -> (start: String, end: String)
}

public struct PlannerScriptError: Error, CustomStringConvertible {
    public let description: String
}

/// Runs scripts/planner.py. Blocking — call off the main thread.
public struct PlannerScriptProvider: ScheduleProvider {
    public let root: String

    public init(root: String) {
        self.root = root
    }

    public func plannedDates(start: String, end: String) throws -> [String] {
        let out = try run(["shifts", "--start", start, "--end", end])
        return out.split(separator: "\n").compactMap { line in
            line.split(separator: "|").first.map(String.init)
        }
    }

    public func syncRange() throws -> (start: String, end: String) {
        let out = try run(["sync-range"])
        let lines = out.split(separator: "\n").map(String.init)
        guard lines.count >= 2 else {
            throw PlannerScriptError(description: "planner.py sync-range returned \(lines.count) lines")
        }
        return (lines[0], lines[1])
    }

    private func run(_ args: [String]) throws -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        proc.arguments = ["\(root)/scripts/planner.py"] + args
        var env = ProcessInfo.processInfo.environment
        ShiftlyPaths.applyRepoRootEnvironment(&env, root: root)
        proc.environment = env
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        try proc.run()
        proc.waitUntilExit()
        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if proc.terminationStatus != 0 {
            let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw PlannerScriptError(description: err.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return out
    }
}

/// Builds the full planned-shift set for the engine: planner dates with
/// default (or overridden) times, plus manual shifts read back earlier.
public struct SyncDataSource {
    private let store: DataStore
    private let provider: ScheduleProvider

    public init(store: DataStore, provider: ScheduleProvider) {
        self.store = store
        self.provider = provider
    }

    public func plannedShifts(start: String, end: String) throws -> [PlannedShift] {
        let config = try store.loadConfig()
        let overrides = Dictionary(
            store.loadOverrides().map { ($0.date, $0) },
            uniquingKeysWith: { a, _ in a }
        )
        var byDate: [String: PlannedShift] = [:]

        for date in try provider.plannedDates(start: start, end: end) {
            let times = overrides[date]
            let shift = ShiftTimeBuilder.makeShift(
                date: date,
                kind: .auto,
                title: config.event_title,
                startHHMM: times?.start ?? config.default_start_time,
                endHHMM: times?.end ?? config.default_end_time
            )
            byDate[date] = shift
        }

        for manual in store.loadManualShifts() where manual.date >= start && manual.date <= end {
            if let shift = ShiftTimeBuilder.makeShift(
                date: manual.date,
                kind: .manual,
                title: config.event_title,
                startHHMM: manual.start,
                endHHMM: manual.end
            ) {
                byDate[manual.date] = shift
            }
        }

        return byDate.values.sorted { $0.date < $1.date }
    }
}
