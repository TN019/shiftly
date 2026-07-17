import Foundation
import Testing
@testable import ShiftlyKit

private func makeBreakdown() -> (PayBreakdown, PayConfig) {
    let config = PayConfig(
        base_currency: "AUD",
        rates: [PayRate(effective_from: "2026-07-01", hourly: 30)],
        display_rates: ["CNY": 5.0]
    )
    let shifts = [
        ShiftTimeBuilder.makeShift(date: "2026-07-06", kind: .auto, title: "W", startHHMM: "10:00", endHHMM: "18:30")!,
        ShiftTimeBuilder.makeShift(date: "2026-07-20", kind: .auto, title: "W", startHHMM: "22:00", endHHMM: "06:00")!,
    ]
    return (PayEngine.breakdown(shifts: shifts, config: config), config)
}

@Suite struct PayslipExporterTests {
    @Test func csvColumnsAndTotals() {
        let (breakdown, config) = makeBreakdown()
        let csv = PayslipExporter.csv(month: "2026-07", breakdown: breakdown, config: config, displayCurrency: "AUD")
        let lines = csv.split(separator: "\n").map(String.init)
        #expect(lines[0] == "Date,Start,End,Hours,Rate (AUD),Amount (AUD)")
        #expect(lines[1] == "2026-07-06,10:00,18:30,8.50,30.00,255.00")
        #expect(lines[2] == "2026-07-20,22:00,06:00,8.00,30.00,240.00")
        #expect(lines[3] == "Total,,,16.50,,495.00")
        let columns = lines.map { $0.split(separator: ",", omittingEmptySubsequences: false).count }
        #expect(Set(columns) == [6], "every row has 6 columns")
    }

    @Test func csvConvertsCurrency() {
        let (breakdown, config) = makeBreakdown()
        let csv = PayslipExporter.csv(month: "2026-07", breakdown: breakdown, config: config, displayCurrency: "CNY")
        let lines = csv.split(separator: "\n").map(String.init)
        #expect(lines[0].contains("Rate (CNY)"))
        #expect(lines[1].hasSuffix("150.00,1275.00"), "30×5 rate, 255×5 amount")
        #expect(lines[3].hasSuffix("2475.00"))
    }

    @Test func markdownTableAndUnratedNote() {
        let config = PayConfig(rates: [PayRate(effective_from: "2026-07-10", hourly: 30)])
        let shifts = [
            ShiftTimeBuilder.makeShift(date: "2026-07-06", kind: .auto, title: "W", startHHMM: "10:00", endHHMM: "18:30")!,
        ]
        let breakdown = PayEngine.breakdown(shifts: shifts, config: config)
        let md = PayslipExporter.markdown(month: "2026-07", breakdown: breakdown, config: config, displayCurrency: "AUD")
        #expect(md.contains("# Shiftly Payslip — 2026-07"))
        #expect(md.contains("| 2026-07-06 | 10:00 | 18:30 | 8.50 | — | 0.00 |"))
        #expect(md.contains("predate the first rate segment"))
        #expect(md.contains("| **Total** | | | **8.50** | | **0.00** |"))
    }

    @Test func markdownNotesConversion() {
        let (breakdown, config) = makeBreakdown()
        let md = PayslipExporter.markdown(month: "2026-07", breakdown: breakdown, config: config, displayCurrency: "CNY")
        #expect(md.contains("converted from AUD × 5"))
    }
}
