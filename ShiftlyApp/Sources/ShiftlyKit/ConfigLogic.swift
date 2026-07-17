import Foundation

/// Pure config-mutation logic, kept UI-free so it can be tested standalone.
///
/// Works on the raw JSON dictionary instead of `Config` so that keys this
/// app version does not know about survive a save round-trip.
public enum ConfigLogic {
    /// Merge schedule fields into the raw config dictionary.
    ///
    /// - Unknown top-level keys are preserved untouched.
    /// - The rule is upserted by `effective_from`: an existing rule with the
    ///   same date is updated in place (its unknown keys preserved too),
    ///   otherwise the new rule is appended. Rules stay sorted by date.
    public static func mergeSchedule(
        into raw: [String: Any],
        startTime: String,
        endTime: String,
        effectiveFrom: String,
        workdays: [String],
        shiftType: String? = nil
    ) -> [String: Any] {
        var cfg = raw
        cfg["default_start_time"] = startTime
        cfg["default_end_time"] = endTime
        cfg["setup_completed"] = true
        if cfg["config_version"] == nil {
            cfg["config_version"] = 1
        }

        var rules = (cfg["rules"] as? [[String: Any]]) ?? []
        if let i = rules.firstIndex(where: { ($0["effective_from"] as? String) == effectiveFrom }) {
            var rule = rules[i]
            rule["workdays"] = workdays
            if let shiftType {
                rule["shift_type"] = shiftType
            }
            rules[i] = rule
        } else {
            var rule: [String: Any] = ["effective_from": effectiveFrom, "workdays": workdays]
            if let shiftType {
                rule["shift_type"] = shiftType
            }
            rules.append(rule)
        }
        rules.sort {
            (($0["effective_from"] as? String) ?? "") < (($1["effective_from"] as? String) ?? "")
        }
        cfg["rules"] = rules
        return cfg
    }

    /// Remove the rule with the given effective_from. Unknown keys elsewhere
    /// are untouched; removing a nonexistent rule is a no-op.
    public static func deleteRule(
        from raw: [String: Any],
        effectiveFrom: String
    ) -> [String: Any] {
        var cfg = raw
        var rules = (cfg["rules"] as? [[String: Any]]) ?? []
        rules.removeAll { ($0["effective_from"] as? String) == effectiveFrom }
        cfg["rules"] = rules
        return cfg
    }

    /// Replace the shift-type list. Writing shift types is the v2 feature,
    /// so config_version is raised to 2 (never lowered).
    public static func mergeShiftTypes(
        into raw: [String: Any],
        shiftTypes: [ShiftType]
    ) -> [String: Any] {
        var cfg = raw
        cfg["shift_types"] = shiftTypes.map { type in
            ["id": type.id, "label": type.label, "start": type.start, "end": type.end]
        }
        let version = cfg["config_version"] as? Int ?? 1
        cfg["config_version"] = max(version, 2)
        return cfg
    }

    /// Merge calendar identity fields into the raw config dictionary,
    /// preserving unknown keys (same contract as `mergeSchedule`).
    public static func mergeCalendarSettings(
        into raw: [String: Any],
        calendarName: String,
        eventTitle: String
    ) -> [String: Any] {
        var cfg = raw
        cfg["calendar_name"] = calendarName
        cfg["event_title"] = eventTitle
        if cfg["config_version"] == nil {
            cfg["config_version"] = 1
        }
        return cfg
    }

    public static func readRawConfig(atPath path: String) throws -> [String: Any] {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.propertyListReadCorrupt)
        }
        return dict
    }

    public static func writeRawConfig(_ raw: [String: Any], toPath path: String) throws {
        let data = try JSONSerialization.data(
            withJSONObject: raw,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: URL(fileURLWithPath: path))
    }
}
