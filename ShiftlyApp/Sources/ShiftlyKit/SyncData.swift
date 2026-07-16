import Foundation

/// A shift the user created directly in the calendar (read back by sync).
/// Stored in data/manual_shifts.json.
public struct ManualShift: Codable, Equatable {
    public var date: String
    public var start: String
    public var end: String
    public var source: String

    public init(date: String, start: String, end: String, source: String = "calendar") {
        self.date = date
        self.start = start
        self.end = end
        self.source = source
    }
}

/// A single-day time override (user retimed one shift in the calendar).
/// Stored in data/overrides.json.
public struct TimeOverride: Codable, Equatable {
    public var date: String
    public var start: String
    public var end: String

    public init(date: String, start: String, end: String) {
        self.date = date
        self.start = start
        self.end = end
    }
}

extension ShiftlyPaths {
    public var manualShiftsPath: String { "\(root)/data/manual_shifts.json" }
    public var overridesPath: String { "\(root)/data/overrides.json" }
    public var plannerScript: String { "\(root)/scripts/planner.py" }
}

extension DataStore {
    public func loadManualShifts() -> [ManualShift] {
        loadArray(at: paths.manualShiftsPath)
    }

    public func saveManualShifts(_ items: [ManualShift]) throws {
        try writeArray(items, to: paths.manualShiftsPath)
    }

    public func loadOverrides() -> [TimeOverride] {
        loadArray(at: paths.overridesPath)
    }

    public func saveOverrides(_ items: [TimeOverride]) throws {
        try writeArray(items, to: paths.overridesPath)
    }

    private func loadArray<T: Decodable>(at path: String) -> [T] {
        guard let data = FileManager.default.contents(atPath: path) else { return [] }
        return (try? JSONDecoder().decode([T].self, from: data)) ?? []
    }

    private func writeArray<T: Encodable>(_ items: [T], to path: String) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(items)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}

/// Writes calendar-side changes into the data files (design §4).
public struct ReadbackApplier {
    private let store: DataStore

    public init(store: DataStore) {
        self.store = store
    }

    /// Applies changes; returns how many records were written.
    @discardableResult
    public func apply(_ changes: [ReadbackChange]) throws -> Int {
        guard !changes.isEmpty else { return 0 }
        var swaps = (try? store.loadSwaps()) ?? []
        var leaves = (try? store.loadLeaves()) ?? []
        var manuals = store.loadManualShifts()
        var overrides = store.loadOverrides()
        var written = 0

        for change in changes {
            switch change {
            case .moved(let from, let to, _):
                swaps.append(SwapItem(from_date: from, to_date: to))
                written += 1
            case .retimed(let date, _, let start, let end):
                if let i = overrides.firstIndex(where: { $0.date == date }) {
                    overrides[i] = TimeOverride(date: date, start: start, end: end)
                } else {
                    overrides.append(TimeOverride(date: date, start: start, end: end))
                }
                written += 1
            case .deleted(let date):
                leaves.append(LeaveItem(start_date: date, end_date: date))
                written += 1
            case .newManual(let date, _, let start, let end):
                if !manuals.contains(where: { $0.date == date }) {
                    manuals.append(ManualShift(date: date, start: start, end: end))
                    written += 1
                }
            }
        }

        try store.saveSwaps(swaps)
        try store.saveLeaves(leaves)
        try store.saveManualShifts(manuals.sorted { $0.date < $1.date })
        try store.saveOverrides(overrides.sorted { $0.date < $1.date })
        return written
    }
}
