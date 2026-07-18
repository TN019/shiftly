import Foundation
import Testing
@testable import ShiftlyKit

private func event(_ id: String, _ date: String, _ start: String, _ end: String) -> HistoryImporter.PastEvent {
    let shift = ShiftTimeBuilder.makeShift(
        date: date, kind: .auto, title: "Shift", startHHMM: start, endHHMM: end
    )!
    return HistoryImporter.PastEvent(id: id, start: shift.start, end: shift.end, isAllDay: false)
}

private func allDayEvent(_ id: String, _ date: String) -> HistoryImporter.PastEvent {
    let shift = ShiftTimeBuilder.makeShift(
        date: date, kind: .auto, title: "Shift", startHHMM: "00:00", endHHMM: "23:59"
    )!
    return HistoryImporter.PastEvent(id: id, start: shift.start, end: shift.end, isAllDay: true)
}

private func map(
    _ events: [HistoryImporter.PastEvent],
    before cutoff: String = "2026-07-18"
) -> (shifts: [ManualShift], mergedDays: Int) {
    HistoryImporter.shifts(from: events, before: cutoff, defaultStart: "10:00", defaultEnd: "18:30")
}

@Suite struct HistoryImporterTests {
    @Test func mapsPastEventsWithRealTimesAndSkipsFuture() {
        let (shifts, merged) = map([
            event("a", "2026-02-24", "09:30", "17:15"),
            event("b", "2026-03-03", "12:00", "20:00"),
            event("c", "2026-07-18", "10:00", "18:00"), // cutoff day itself
            event("d", "2026-08-01", "10:00", "18:00"), // future
        ])
        #expect(merged == 0)
        #expect(shifts == [
            ManualShift(date: "2026-02-24", start: "09:30", end: "17:15", source: "import"),
            ManualShift(date: "2026-03-03", start: "12:00", end: "20:00", source: "import"),
        ])
    }

    @Test func multipleEventsOnOneDayMergeToSpan() {
        let (shifts, merged) = map([
            event("a", "2026-05-10", "09:00", "13:00"),
            event("b", "2026-05-10", "17:00", "21:00"),
        ])
        #expect(merged == 1)
        #expect(shifts == [ManualShift(date: "2026-05-10", start: "09:00", end: "21:00", source: "import")])
    }

    @Test func allDayEventsUseConfiguredDefaultTimes() {
        let (shifts, merged) = map([
            allDayEvent("a", "2026-04-01"),
            allDayEvent("b", "2026-04-02"),
        ])
        #expect(merged == 0)
        #expect(shifts == [
            ManualShift(date: "2026-04-01", start: "10:00", end: "18:30", source: "import"),
            ManualShift(date: "2026-04-02", start: "10:00", end: "18:30", source: "import"),
        ])
    }

    @Test func timedEventWinsOverAllDayOnSameDay() {
        let (shifts, _) = map([
            allDayEvent("a", "2026-04-01"),
            event("b", "2026-04-01", "11:00", "19:00"),
        ])
        #expect(shifts == [ManualShift(date: "2026-04-01", start: "11:00", end: "19:00", source: "import")])
    }

    @Test func recurringOccurrencesShareIdButAllCount() {
        // Occurrences of a recurring event arrive with the same id and
        // different starts; each past day must become a shift.
        let (shifts, _) = map([
            event("recurring", "2026-06-01", "10:00", "18:30"),
            event("recurring", "2026-06-08", "10:00", "18:30"),
            event("recurring", "2026-06-15", "10:00", "18:30"),
        ])
        #expect(shifts.map(\.date) == ["2026-06-01", "2026-06-08", "2026-06-15"])
    }

    @Test func applyNeverOverwritesExistingDates() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("import_\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: root) }
        try FileManager.default.createDirectory(atPath: root + "/data", withIntermediateDirectories: true)
        let store = DataStore(paths: ShiftlyPaths(root: root))
        try store.saveManualShifts([
            ManualShift(date: "2026-03-03", start: "08:00", end: "16:00", source: "calendar")
        ])

        let summary = try HistoryImporter.apply([
            ManualShift(date: "2026-02-24", start: "09:30", end: "17:15", source: "import"),
            ManualShift(date: "2026-03-03", start: "12:00", end: "20:00", source: "import"),
        ], mergedDays: 0, to: store)

        #expect(summary.imported == 1)
        #expect(summary.skippedExisting == 1)
        let saved = store.loadManualShifts()
        #expect(saved.count == 2)
        #expect(saved.first { $0.date == "2026-03-03" }?.start == "08:00", "existing readback untouched")
        #expect(saved.first?.date == "2026-02-24", "sorted by date")
    }

    @Test func importedHistoryFlowsIntoPayWithRateSegments() {
        // Imported shifts before the first rate segment are unpaid but still
        // counted; each later shift uses the segment in effect on its date.
        let config = PayConfig(base_currency: "AUD", rates: [
            PayRate(effective_from: "2026-03-01", hourly: 20),
            PayRate(effective_from: "2026-06-01", hourly: 23.5),
        ])
        let shifts = [
            ShiftTimeBuilder.makeShift(date: "2026-02-10", kind: .manual, title: "S", startHHMM: "09:00", endHHMM: "17:00")!, // before first segment
            ShiftTimeBuilder.makeShift(date: "2026-03-01", kind: .manual, title: "S", startHHMM: "09:00", endHHMM: "17:00")!, // first paid day
            ShiftTimeBuilder.makeShift(date: "2026-05-31", kind: .manual, title: "S", startHHMM: "09:00", endHHMM: "17:00")!, // last day of segment 1
            ShiftTimeBuilder.makeShift(date: "2026-06-01", kind: .manual, title: "S", startHHMM: "09:00", endHHMM: "17:00")!, // first day of segment 2
        ]
        let breakdown = PayEngine.breakdown(shifts: shifts, config: config)
        #expect(breakdown.hasUnratedShifts, "pre-segment day flagged")
        #expect(breakdown.items[0].amount == 0)
        #expect(abs(breakdown.items[1].amount - 8 * 20) < 0.001)
        #expect(abs(breakdown.items[2].amount - 8 * 20) < 0.001)
        #expect(abs(breakdown.items[3].amount - 8 * 23.5) < 0.001)
        #expect(abs(breakdown.totalHours - 32) < 0.001, "unpaid hours still counted")
    }
}
