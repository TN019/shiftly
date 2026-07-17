import Foundation
import Testing
@testable import ShiftlyKit

private func shift(_ date: String, _ start: String = "10:00", _ end: String = "18:30") -> PlannedShift {
    ShiftTimeBuilder.makeShift(date: date, kind: .auto, title: "Work", startHHMM: start, endHHMM: end)!
}

@Suite struct PayConfigTests {
    @Test func rateSegmentation() {
        let config = PayConfig(rates: [
            PayRate(effective_from: "2026-01-01", hourly: 30),
            PayRate(effective_from: "2026-07-15", hourly: 35),
        ])
        #expect(config.hourlyRate(on: "2025-12-31") == nil)
        #expect(config.hourlyRate(on: "2026-01-01") == 30)
        #expect(config.hourlyRate(on: "2026-07-14") == 30)
        #expect(config.hourlyRate(on: "2026-07-15") == 35)
    }

    @Test func displayMultiplier() {
        let config = PayConfig(base_currency: "AUD", display_rates: ["CNY": 4.7, "USD": 0.66])
        #expect(config.displayMultiplier(for: "AUD") == 1.0)
        #expect(config.displayMultiplier(for: "CNY") == 4.7)
        #expect(config.displayMultiplier(for: "JPY") == 1.0, "unknown currency falls back to 1")
    }

    @Test func fileRoundTripAndMissing() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("shiftly_pay_\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: root) }
        try FileManager.default.createDirectory(atPath: root + "/data", withIntermediateDirectories: true)
        let store = DataStore(paths: ShiftlyPaths(root: root))
        #expect(store.loadPayConfig() == nil, "missing file = not configured, no crash")
        let config = PayConfig(base_currency: "AUD", rates: [PayRate(effective_from: "2026-01-01", hourly: 32.5)])
        try store.savePayConfig(config)
        #expect(store.loadPayConfig() == config)
    }
}

@Suite struct PayEngineTests {
    private let config = PayConfig(rates: [
        PayRate(effective_from: "2026-01-01", hourly: 30),
        PayRate(effective_from: "2026-07-15", hourly: 35),
    ])

    @Test func regularWeek() {
        // Two 8.5h shifts at $30.
        let breakdown = PayEngine.breakdown(
            shifts: [shift("2026-07-06"), shift("2026-07-07")],
            config: config
        )
        #expect(breakdown.items.count == 2)
        #expect(abs(breakdown.totalHours - 17.0) < 0.001)
        #expect(abs(breakdown.totalAmount - 510.0) < 0.001)
        #expect(!breakdown.hasUnratedShifts)
    }

    @Test func overnightShiftCountsFullHours() {
        // 22:00–06:00 = 8h, attributed to the start day.
        let breakdown = PayEngine.breakdown(
            shifts: [shift("2026-07-20", "22:00", "06:00")],
            config: config
        )
        #expect(abs(breakdown.items[0].hours - 8.0) < 0.001)
        #expect(breakdown.items[0].date == "2026-07-20")
        #expect(abs(breakdown.totalAmount - 8 * 35) < 0.001)
    }

    @Test func midMonthRaiseSplitsCorrectly() {
        // 8.5h on the 14th at 30, 8.5h on the 15th at 35.
        let breakdown = PayEngine.breakdown(
            shifts: [shift("2026-07-14"), shift("2026-07-15")],
            config: config
        )
        #expect(abs(breakdown.items[0].amount - 8.5 * 30) < 0.001)
        #expect(abs(breakdown.items[1].amount - 8.5 * 35) < 0.001)
    }

    @Test func shiftsBeforeFirstRateEarnZeroAndFlag() {
        let breakdown = PayEngine.breakdown(shifts: [shift("2025-12-30")], config: config)
        #expect(breakdown.hasUnratedShifts)
        #expect(breakdown.items[0].hourlyRate == nil)
        #expect(breakdown.totalAmount == 0)
        #expect(abs(breakdown.totalHours - 8.5) < 0.001, "hours still counted")
    }

    @Test func monthGrouping() {
        let byMonth = PayEngine.byMonth(
            shifts: [shift("2026-06-30"), shift("2026-07-01"), shift("2026-07-02")],
            config: config
        )
        #expect(byMonth.keys.sorted() == ["2026-06", "2026-07"])
        #expect(byMonth["2026-07"]?.items.count == 2)
    }
}
