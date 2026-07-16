import Foundation
import Testing
@testable import ShiftlyKit

@Suite struct ConfigLogicTests {
    private let baseRaw: [String: Any] = [
        "config_version": 1,
        "calendar_name": "Shifts",
        "event_title": "Work Schedule",
        "default_start_time": "10:00",
        "default_end_time": "18:30",
        "my_custom": 1,
        "nested_custom": ["a": [1, 2, 3]],
        "rules": [
            ["effective_from": "2026-01-01", "workdays": ["MO", "TU"], "rule_note": "keep me"]
        ],
    ]

    private func merge(_ raw: [String: Any], effectiveFrom: String, workdays: [String]) -> [String: Any] {
        ConfigLogic.mergeSchedule(
            into: raw, startTime: "09:00", endTime: "17:00",
            effectiveFrom: effectiveFrom, workdays: workdays
        )
    }

    @Test func unknownKeysPreserved() {
        let merged = merge(baseRaw, effectiveFrom: "2026-07-16", workdays: ["WE"])
        #expect(merged["my_custom"] as? Int == 1)
        #expect(merged["nested_custom"] as? [String: Any] != nil)
        #expect(merged["default_start_time"] as? String == "09:00")
        #expect(merged["setup_completed"] as? Bool == true)
    }

    @Test func ruleAppendedNotOverwritten() {
        let merged = merge(baseRaw, effectiveFrom: "2026-07-16", workdays: ["WE", "TH"])
        let rules = merged["rules"] as? [[String: Any]] ?? []
        #expect(rules.count == 2)
        #expect(rules[0]["effective_from"] as? String == "2026-01-01")
        #expect(rules[0]["workdays"] as? [String] == ["MO", "TU"])
        #expect(rules[1]["effective_from"] as? String == "2026-07-16")
    }

    @Test func sameDateUpsertReplacesAndKeepsRuleKeys() {
        let once = merge(baseRaw, effectiveFrom: "2026-07-16", workdays: ["WE"])
        let twice = merge(once, effectiveFrom: "2026-01-01", workdays: ["SA"])
        let rules = twice["rules"] as? [[String: Any]] ?? []
        #expect(rules.count == 2)
        #expect(rules[0]["workdays"] as? [String] == ["SA"])
        #expect(rules[0]["rule_note"] as? String == "keep me")
    }

    @Test func configVersionDefaulting() {
        let noVer = merge([:], effectiveFrom: "2026-07-16", workdays: ["MO"])
        #expect(noVer["config_version"] as? Int == 1)
        let hasVer = merge(["config_version": 5], effectiveFrom: "2026-07-16", workdays: ["MO"])
        #expect(hasVer["config_version"] as? Int == 5)
    }

    @Test func fileRoundTripKeepsUnknownKeys() throws {
        let merged = merge(baseRaw, effectiveFrom: "2026-07-16", workdays: ["WE"])
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("cfg_test_\(UUID().uuidString).json").path
        defer { try? FileManager.default.removeItem(atPath: tmp) }
        try ConfigLogic.writeRawConfig(merged, toPath: tmp)
        let back = try ConfigLogic.readRawConfig(atPath: tmp)
        #expect(back["my_custom"] as? Int == 1)
    }
}
