import Foundation
import Testing
@testable import ShiftlyKit

@Suite struct ModelsCodingTests {
    @Test func swapItemFileFormatHasNoId() throws {
        let item = SwapItem(from_date: "2026-01-05", to_date: "2026-01-07")
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let json = String(data: try enc.encode([item]), encoding: .utf8)!
        #expect(json == #"[{"from_date":"2026-01-05","to_date":"2026-01-07"}]"#)
    }

    @Test func swapItemIdStableAcrossAccesses() throws {
        let data = Data(#"[{"from_date":"2026-01-05","to_date":"2026-01-07"}]"#.utf8)
        let items = try JSONDecoder().decode([SwapItem].self, from: data)
        #expect(items[0].id == items[0].id)
    }

    @Test func leaveItemRoundTrip() throws {
        let data = Data(#"[{"start_date":"2026-01-08","end_date":"2026-01-09"}]"#.utf8)
        let items = try JSONDecoder().decode([LeaveItem].self, from: data)
        #expect(items[0].start_date == "2026-01-08")
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let json = String(data: try enc.encode(items), encoding: .utf8)!
        #expect(json == #"[{"end_date":"2026-01-09","start_date":"2026-01-08"}]"#)
    }

    @Test func configDecodeIgnoresUnknownKeys() throws {
        let data = Data("""
        {"config_version":1,"calendar_name":"Shifts","event_title":"Work",
         "default_start_time":"10:00","default_end_time":"18:30",
         "my_custom":1,"rules":[]}
        """.utf8)
        let cfg = try JSONDecoder().decode(Config.self, from: data)
        #expect(cfg.calendar_name == "Shifts")
    }
}

@Suite struct DataStoreScheduleTests {
    @Test func mergeKeepsRulesSortedByDate() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("store_test_\(UUID().uuidString).json").path
        defer { try? FileManager.default.removeItem(atPath: tmp) }
        try ConfigLogic.writeRawConfig([
            "calendar_name": "Shifts",
            "rules": [["effective_from": "2026-05-01", "workdays": ["FR"]]],
        ], toPath: tmp)

        let raw = try ConfigLogic.readRawConfig(atPath: tmp)
        let merged = ConfigLogic.mergeSchedule(
            into: raw, startTime: "10:00", endTime: "18:30",
            effectiveFrom: "2026-01-15", workdays: ["MO"]
        )
        let rules = (merged["rules"] as? [[String: Any]]) ?? []
        #expect(rules.map { $0["effective_from"] as? String } == ["2026-01-15", "2026-05-01"])
    }
}
