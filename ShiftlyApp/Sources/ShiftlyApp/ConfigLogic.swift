import Foundation

/// Pure config-mutation logic, kept UI-free so it can be tested standalone.
///
/// Works on the raw JSON dictionary instead of `Config` so that keys this
/// app version does not know about survive a save round-trip.
enum ConfigLogic {
    /// Merge schedule fields into the raw config dictionary.
    ///
    /// - Unknown top-level keys are preserved untouched.
    /// - The rule is upserted by `effective_from`: an existing rule with the
    ///   same date is updated in place (its unknown keys preserved too),
    ///   otherwise the new rule is appended. Rules stay sorted by date.
    static func mergeSchedule(
        into raw: [String: Any],
        startTime: String,
        endTime: String,
        effectiveFrom: String,
        workdays: [String]
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
            rules[i] = rule
        } else {
            rules.append(["effective_from": effectiveFrom, "workdays": workdays])
        }
        rules.sort {
            (($0["effective_from"] as? String) ?? "") < (($1["effective_from"] as? String) ?? "")
        }
        cfg["rules"] = rules
        return cfg
    }

    static func readRawConfig(atPath path: String) throws -> [String: Any] {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.propertyListReadCorrupt)
        }
        return dict
    }

    static func writeRawConfig(_ raw: [String: Any], toPath path: String) throws {
        let data = try JSONSerialization.data(
            withJSONObject: raw,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: URL(fileURLWithPath: path))
    }
}
