import Foundation
import Testing
@testable import ShiftlyKit

private func holidayEvent(
    _ id: String, _ startDate: String, _ title: String, endDate: String? = nil
) -> HistoryImporter.PastEvent {
    let start = ShiftTimeBuilder.makeShift(
        date: startDate, kind: .auto, title: title, startHHMM: "00:00", endHHMM: "23:59"
    )!
    let end = ShiftTimeBuilder.makeShift(
        date: endDate ?? startDate, kind: .auto, title: title, startHHMM: "00:00", endHHMM: "23:59"
    )!
    return HistoryImporter.PastEvent(
        id: id, start: start.start, end: end.end, isAllDay: true, title: title
    )
}

@Suite struct HolidayTests {
    @Test func mapsEventsToRangesAndKeepsExisting() {
        let existing = [HolidayItem(date: "2026-12-25", name: "Kept As Is")]
        let (merged, added) = HistoryImporter.holidays(from: [
            holidayEvent("a", "2026-01-26", "Australia Day"),
            holidayEvent("b", "2026-12-25", "Christmas Day"), // start exists: kept
            holidayEvent("c", "2026-01-26", "Duplicate day"), // duplicate start skipped
            holidayEvent("d", "2026-04-03", "Easter", endDate: "2026-04-06"), // multi-day span
        ], existing: existing)
        #expect(added == 2)
        #expect(merged == [
            HolidayItem(date: "2026-01-26", name: "Australia Day"),
            HolidayItem(start_date: "2026-04-03", end_date: "2026-04-06", name: "Easter"),
            HolidayItem(date: "2026-12-25", name: "Kept As Is"),
        ])
    }

    @Test func storeRoundTripsSortedByStartDate() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("holiday_\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: root) }
        try FileManager.default.createDirectory(atPath: root + "/data", withIntermediateDirectories: true)
        let store = DataStore(paths: ShiftlyPaths(root: root))

        #expect(store.loadHolidays().isEmpty, "missing file reads as empty")
        try store.saveHolidays([
            HolidayItem(start_date: "2026-12-25", end_date: "2026-12-26", name: "Christmas"),
            HolidayItem(date: "2026-01-26", name: ""),
        ])
        let loaded = store.loadHolidays()
        #expect(loaded.map(\.start_date) == ["2026-01-26", "2026-12-25"])
        #expect(loaded.last == HolidayItem(start_date: "2026-12-25", end_date: "2026-12-26", name: "Christmas"))
    }
}

private extension HolidayItem {
    /// Single-day shorthand for tests.
    init(date: String, name: String) {
        self.init(start_date: date, end_date: date, name: name)
    }
}
