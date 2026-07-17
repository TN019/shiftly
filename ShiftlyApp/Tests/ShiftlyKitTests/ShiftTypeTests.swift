import Foundation
import Testing
@testable import ShiftlyKit

@Suite struct ShiftTypeConfigTests {
    @Test func timesResolutionPrefersTypeThenDefaults() throws {
        let json = """
        {"config_version":2,"calendar_name":"Shifts","event_title":"Work",
         "default_start_time":"10:00","default_end_time":"18:30","rules":[],
         "shift_types":[{"id":"night","label":"Night","start":"22:00","end":"06:00"}]}
        """
        let cfg = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        #expect(cfg.times(forShiftType: "night") == ("22:00", "06:00"))
        #expect(cfg.times(forShiftType: "missing") == ("10:00", "18:30"))
        #expect(cfg.times(forShiftType: nil) == ("10:00", "18:30"))
    }

    @Test func mergeShiftTypesBumpsVersionAndKeepsUnknownKeys() {
        let raw: [String: Any] = ["config_version": 1, "my_custom": 1, "rules": []]
        let merged = ConfigLogic.mergeShiftTypes(into: raw, shiftTypes: [
            ShiftType(id: "day", label: "Day", start: "09:00", end: "17:00")
        ])
        #expect(merged["config_version"] as? Int == 2)
        #expect(merged["my_custom"] as? Int == 1)
        let types = merged["shift_types"] as? [[String: Any]] ?? []
        #expect(types.count == 1)
        #expect(types[0]["id"] as? String == "day")

        // Never downgraded.
        let again = ConfigLogic.mergeShiftTypes(into: ["config_version": 3], shiftTypes: [])
        #expect(again["config_version"] as? Int == 3)
    }

    @Test func ruleUpsertKeepsAndSetsShiftType() {
        let raw: [String: Any] = ["rules": [
            ["effective_from": "2026-01-01", "workdays": ["MO"], "shift_type": "day"]
        ]]
        // Editing without a type keeps the existing one.
        let kept = ConfigLogic.mergeSchedule(
            into: raw, startTime: "10:00", endTime: "18:30",
            effectiveFrom: "2026-01-01", workdays: ["TU"]
        )
        let keptRules = kept["rules"] as? [[String: Any]] ?? []
        #expect(keptRules[0]["shift_type"] as? String == "day")

        // New rule with a type carries it.
        let added = ConfigLogic.mergeSchedule(
            into: raw, startTime: "10:00", endTime: "18:30",
            effectiveFrom: "2026-08-01", workdays: ["WE"], shiftType: "night"
        )
        let addedRules = added["rules"] as? [[String: Any]] ?? []
        #expect(addedRules.count == 2)
        #expect(addedRules[1]["shift_type"] as? String == "night")
    }

    @Test func deleteRuleRemovesOnlyThatRule() {
        let raw: [String: Any] = ["my_custom": 5, "rules": [
            ["effective_from": "2026-01-01", "workdays": ["MO"]],
            ["effective_from": "2026-08-01", "workdays": ["TU"]],
        ]]
        let result = ConfigLogic.deleteRule(from: raw, effectiveFrom: "2026-08-01")
        let rules = result["rules"] as? [[String: Any]] ?? []
        #expect(rules.count == 1)
        #expect(rules[0]["effective_from"] as? String == "2026-01-01")
        #expect(result["my_custom"] as? Int == 5)
        // Deleting a nonexistent rule is a no-op.
        let noop = ConfigLogic.deleteRule(from: result, effectiveFrom: "2099-01-01")
        #expect((noop["rules"] as? [[String: Any]])?.count == 1)
    }
}

@Suite struct ShiftTypeDataSourceTests {
    @Test func plannedShiftsUseTypeTimesThenOverride() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("shiftly_types_\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: root) }
        try FileManager.default.createDirectory(atPath: root + "/data", withIntermediateDirectories: true)
        try ConfigLogic.writeRawConfig([
            "config_version": 2,
            "calendar_name": "Shifts",
            "event_title": "Work Schedule",
            "default_start_time": "10:00",
            "default_end_time": "18:30",
            "rules": [],
            "shift_types": [["id": "night", "label": "Night", "start": "22:00", "end": "06:00"]],
        ], toPath: root + "/data/config.json")
        let paths = ShiftlyPaths(root: root)
        let store = DataStore(paths: paths)
        try store.saveOverrides([TimeOverride(date: "2026-07-22", start: "12:00", end: "20:00")])

        struct FixedProvider: ScheduleProvider {
            func plannedDays(start: String, end: String) throws -> [PlannedDay] {
                [
                    PlannedDay(date: "2026-07-20", source: "rule", shiftType: "night"),
                    PlannedDay(date: "2026-07-21", source: "rule", shiftType: "default"),
                    PlannedDay(date: "2026-07-22", source: "rule", shiftType: "night"),
                ]
            }
            func syncRange() throws -> (start: String, end: String) { ("2026-07-01", "2026-07-31") }
        }

        let shifts = try SyncDataSource(store: store, provider: FixedProvider())
            .plannedShifts(start: "2026-07-01", end: "2026-07-31")
        let byDate = Dictionary(shifts.map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })

        // Night type: 22:00 start, overnight end on the next day.
        let night = byDate["2026-07-20"]!
        #expect(SyncFingerprint.hhmmString(for: night.start) == "22:00")
        #expect(SyncFingerprint.dayString(for: night.end) == "2026-07-21")
        // Default falls back to config times.
        #expect(SyncFingerprint.hhmmString(for: byDate["2026-07-21"]!.start) == "10:00")
        // Per-day override beats the type.
        #expect(SyncFingerprint.hhmmString(for: byDate["2026-07-22"]!.start) == "12:00")
    }
}
