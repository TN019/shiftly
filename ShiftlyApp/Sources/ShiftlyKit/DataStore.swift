import Foundation

/// Typed access to the JSON data files under `<root>/data/`.
public struct DataStore {
    public let paths: ShiftlyPaths

    public init(paths: ShiftlyPaths = .shared) {
        self.paths = paths
    }

    // MARK: Reads

    public func loadConfig() throws -> Config {
        let data = try Data(contentsOf: URL(fileURLWithPath: paths.configPath))
        return try JSONDecoder().decode(Config.self, from: data)
    }

    public func loadSwaps() throws -> [SwapItem] {
        let data = try Data(contentsOf: URL(fileURLWithPath: paths.swapsPath))
        return try JSONDecoder().decode([SwapItem].self, from: data)
    }

    public func loadLeaves() throws -> [LeaveItem] {
        let data = try Data(contentsOf: URL(fileURLWithPath: paths.leavePath))
        return try JSONDecoder().decode([LeaveItem].self, from: data)
    }

    public func loadMeta() -> Meta? {
        guard let data = FileManager.default.contents(atPath: paths.metaPath) else { return nil }
        return try? JSONDecoder().decode(Meta.self, from: data)
    }

    // MARK: Writes

    public func saveSwaps(_ swaps: [SwapItem]) throws {
        try writeJSON(swaps, to: paths.swapsPath)
    }

    public func saveLeaves(_ leaves: [LeaveItem]) throws {
        try writeJSON(leaves, to: paths.leavePath)
    }

    /// Merge the schedule into config.json (unknown keys preserved, rule
    /// history upserted). Returns the resulting rule list, sorted by date.
    @discardableResult
    public func saveSchedule(
        startTime: String,
        endTime: String,
        effectiveFrom: String,
        workdays: [String]
    ) throws -> [Rule] {
        let raw = try ConfigLogic.readRawConfig(atPath: paths.configPath)
        let merged = ConfigLogic.mergeSchedule(
            into: raw,
            startTime: startTime,
            endTime: endTime,
            effectiveFrom: effectiveFrom,
            workdays: workdays
        )
        try ConfigLogic.writeRawConfig(merged, toPath: paths.configPath)
        let rules = (merged["rules"] as? [[String: Any]]) ?? []
        return rules.compactMap { dict in
            guard let ef = dict["effective_from"] as? String else { return nil }
            return Rule(effective_from: ef, workdays: (dict["workdays"] as? [String]) ?? [])
        }
    }

    private func writeJSON<T: Encodable>(_ value: T, to path: String) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(value)
        try data.write(to: URL(fileURLWithPath: path))
    }
}
