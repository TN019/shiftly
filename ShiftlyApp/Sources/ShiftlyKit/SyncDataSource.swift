import Foundation

/// One planner-emitted day: date, provenance (rule/swap) and the shift-type
/// id of the rule in effect that day.
public struct PlannedDay: Equatable {
    public let date: String
    public let source: String
    public let shiftType: String

    public init(date: String, source: String, shiftType: String) {
        self.date = date
        self.source = source
        self.shiftType = shiftType
    }
}

/// Supplies the planned schedule days and the sync window. The production
/// implementation shells out to scripts/planner.py so the rule/swap/leave
/// algorithm keeps its single source of truth in schedule_core.py; the Swift
/// side only overlays the data the Python planner does not know about
/// (manual shifts and per-day time overrides).
public protocol ScheduleProvider {
    /// Planned auto-shift days in [start, end].
    func plannedDays(start: String, end: String) throws -> [PlannedDay]
    /// Sync window as (first, last) dates.
    func syncRange() throws -> (start: String, end: String)
}

public struct PlannerScriptError: Error, CustomStringConvertible {
    public let description: String
}

/// Finds helper scripts: a scripts/ directory at the data root wins (repo
/// checkouts), otherwise the copy bundled into the .app Resources is used.
public enum ScriptLocator {
    public static func locate(_ name: String, root: String) -> String? {
        let atRoot = "\(root)/scripts/\(name)"
        if FileManager.default.fileExists(atPath: atRoot) {
            return atRoot
        }
        if let bundled = Bundle.main.resourceURL?
            .appendingPathComponent("scripts/\(name)").path,
            FileManager.default.fileExists(atPath: bundled) {
            return bundled
        }
        return nil
    }
}

/// Runs scripts/planner.py. Blocking — call off the main thread.
public struct PlannerScriptProvider: ScheduleProvider {
    public let root: String

    public init(root: String) {
        self.root = root
    }

    public func plannedDays(start: String, end: String) throws -> [PlannedDay] {
        let out = try run(["shifts", "--start", start, "--end", end])
        return out.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "|").map(String.init)
            guard let date = parts.first, !date.isEmpty else { return nil }
            return PlannedDay(
                date: date,
                source: parts.count > 1 ? parts[1] : "rule",
                shiftType: parts.count > 2 ? parts[2] : "default"
            )
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
        guard let script = ScriptLocator.locate("planner.py", root: root) else {
            throw PlannerScriptError(description: "planner.py not found at the data root or in the app bundle")
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        proc.arguments = [script] + args
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

        // Time precedence: per-day override > rule's shift type > defaults.
        for day in try provider.plannedDays(start: start, end: end) {
            let typeTimes = config.times(forShiftType: day.shiftType)
            let override = overrides[day.date]
            let shift = ShiftTimeBuilder.makeShift(
                date: day.date,
                kind: .auto,
                title: config.event_title,
                startHHMM: override?.start ?? typeTimes.start,
                endHHMM: override?.end ?? typeTimes.end
            )
            byDate[day.date] = shift
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
