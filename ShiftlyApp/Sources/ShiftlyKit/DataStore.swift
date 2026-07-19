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

    /// Missing file = no holidays; the file appears on first save.
    public func loadHolidays() -> [HolidayItem] {
        guard let data = FileManager.default.contents(atPath: paths.holidaysPath) else { return [] }
        return (try? JSONDecoder().decode([HolidayItem].self, from: data)) ?? []
    }

    public func saveHolidays(_ holidays: [HolidayItem]) throws {
        try writeJSON(holidays.sorted { $0.start_date < $1.start_date }, to: paths.holidaysPath)
    }

    public func loadMeta() -> Meta? {
        guard let data = FileManager.default.contents(atPath: paths.metaPath) else { return nil }
        return try? JSONDecoder().decode(Meta.self, from: data)
    }

    public func saveMeta(_ meta: Meta) throws {
        try writeJSON(meta, to: paths.metaPath)
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
        workdays: [String],
        shiftType: String? = nil
    ) throws -> [Rule] {
        let raw = try ConfigLogic.readRawConfig(atPath: paths.configPath)
        let merged = ConfigLogic.mergeSchedule(
            into: raw,
            startTime: startTime,
            endTime: endTime,
            effectiveFrom: effectiveFrom,
            workdays: workdays,
            shiftType: shiftType
        )
        try ConfigLogic.writeRawConfig(merged, toPath: paths.configPath)
        return Self.rules(fromRaw: merged)
    }

    /// Delete a rule by its effective_from date; returns the new rule list.
    @discardableResult
    public func deleteRule(effectiveFrom: String) throws -> [Rule] {
        let raw = try ConfigLogic.readRawConfig(atPath: paths.configPath)
        let merged = ConfigLogic.deleteRule(from: raw, effectiveFrom: effectiveFrom)
        try ConfigLogic.writeRawConfig(merged, toPath: paths.configPath)
        return Self.rules(fromRaw: merged)
    }

    public func saveShiftTypes(_ types: [ShiftType]) throws {
        let raw = try ConfigLogic.readRawConfig(atPath: paths.configPath)
        let merged = ConfigLogic.mergeShiftTypes(into: raw, shiftTypes: types)
        try ConfigLogic.writeRawConfig(merged, toPath: paths.configPath)
    }

    private static func rules(fromRaw raw: [String: Any]) -> [Rule] {
        ((raw["rules"] as? [[String: Any]]) ?? []).compactMap { dict in
            guard let ef = dict["effective_from"] as? String else { return nil }
            return Rule(
                effective_from: ef,
                workdays: (dict["workdays"] as? [String]) ?? [],
                shift_type: dict["shift_type"] as? String
            )
        }
    }

    /// Set the work-log folder in config.json (unknown keys preserved).
    public func saveLogDir(_ dir: String) throws {
        var raw = try ConfigLogic.readRawConfig(atPath: paths.configPath)
        raw["log_dir"] = dir
        try ConfigLogic.writeRawConfig(raw, toPath: paths.configPath)
    }

    /// Set the quick-notes folder in config.json (unknown keys preserved).
    public func saveNotesDir(_ dir: String) throws {
        var raw = try ConfigLogic.readRawConfig(atPath: paths.configPath)
        raw["notes_dir"] = dir
        try ConfigLogic.writeRawConfig(raw, toPath: paths.configPath)
    }

    /// Merge calendar name/title into config.json (unknown keys preserved).
    public func saveCalendarSettings(calendarName: String, eventTitle: String) throws {
        let raw = try ConfigLogic.readRawConfig(atPath: paths.configPath)
        let merged = ConfigLogic.mergeCalendarSettings(
            into: raw, calendarName: calendarName, eventTitle: eventTitle
        )
        try ConfigLogic.writeRawConfig(merged, toPath: paths.configPath)
    }

    private func writeJSON<T: Encodable>(_ value: T, to path: String) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(value)
        try data.write(to: URL(fileURLWithPath: path))
    }
}
