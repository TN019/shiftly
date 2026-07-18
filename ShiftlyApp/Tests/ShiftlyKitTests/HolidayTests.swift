import Foundation
import Testing
@testable import ShiftlyKit

private func holidayEvent(_ id: String, _ date: String, _ title: String) -> HistoryImporter.PastEvent {
    let shift = ShiftTimeBuilder.makeShift(
        date: date, kind: .auto, title: title, startHHMM: "00:00", endHHMM: "23:59"
    )!
    return HistoryImporter.PastEvent(id: id, start: shift.start, end: shift.end, isAllDay: true, title: title)
}

@Suite struct HolidayTests {
    @Test func mapsEventsToNamedHolidaysAndKeepsExisting() {
        let existing = [HolidayItem(date: "2026-12-25", name: "Kept As Is")]
        let (merged, added) = HistoryImporter.holidays(from: [
            holidayEvent("a", "2026-01-26", "Australia Day"),
            holidayEvent("b", "2026-12-25", "Christmas Day"), // date exists: kept
            holidayEvent("c", "2026-01-26", "Duplicate day"), // first title wins
        ], existing: existing)
        #expect(added == 1)
        #expect(merged == [
            HolidayItem(date: "2026-01-26", name: "Australia Day"),
            HolidayItem(date: "2026-12-25", name: "Kept As Is"),
        ])
    }

    @Test func storeRoundTripsSortedByDate() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("holiday_\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: root) }
        try FileManager.default.createDirectory(atPath: root + "/data", withIntermediateDirectories: true)
        let store = DataStore(paths: ShiftlyPaths(root: root))

        #expect(store.loadHolidays().isEmpty, "missing file reads as empty")
        try store.saveHolidays([
            HolidayItem(date: "2026-12-25", name: "Christmas Day"),
            HolidayItem(date: "2026-01-26", name: ""),
        ])
        let loaded = store.loadHolidays()
        #expect(loaded.map(\.date) == ["2026-01-26", "2026-12-25"])
        #expect(loaded.last?.name == "Christmas Day")
    }
}
