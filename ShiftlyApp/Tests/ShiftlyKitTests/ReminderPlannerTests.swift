import Foundation
import Testing
@testable import ShiftlyKit

private func shift(_ date: String, _ start: String = "10:00", _ end: String = "18:30") -> PlannedShift {
    ShiftTimeBuilder.makeShift(date: date, kind: .auto, title: "Work", startHHMM: start, endHHMM: end)!
}

@Suite struct ReminderPlannerTests {
    private let now = ShiftTimeBuilder.makeShift(
        date: "2026-07-17", kind: .auto, title: "n", startHHMM: "08:00", endHHMM: "09:00"
    )!.start  // 2026-07-17 08:00 local

    @Test func plansOnlyFutureFireDates() {
        let shifts = [
            shift("2026-07-16"),               // past shift
            shift("2026-07-17", "08:30"),      // fire 07:30 already past
            shift("2026-07-17", "10:00"),      // fire 09:00 — future
            shift("2026-07-18"),               // future
        ]
        let items = ReminderPlanner.plan(shifts: shifts, leadMinutes: 60, now: now)
        #expect(items.map(\.id) == ["shiftly.shift.2026-07-17", "shiftly.shift.2026-07-18"])
        #expect(items[0].fireDate == shift("2026-07-17", "10:00").start.addingTimeInterval(-3600))
        #expect(items[0].body.contains("10:00"))
    }

    @Test func zeroLeadMeansOff() {
        #expect(ReminderPlanner.plan(shifts: [shift("2026-07-18")], leadMinutes: 0, now: now).isEmpty)
    }

    @Test func limitCapsCount() {
        let shifts = (1...30).map { shift(String(format: "2026-08-%02d", $0)) }
        let items = ReminderPlanner.plan(shifts: shifts, leadMinutes: 60, now: now, limit: 20)
        #expect(items.count == 20)
        #expect(items.first?.id == "shiftly.shift.2026-08-01", "soonest shifts win the cap")
    }

    @Test func rescheduleReflectsSwaps() {
        // Before: shift tomorrow. After a swap to the day after, the
        // tomorrow reminder disappears and the new day appears.
        let before = ReminderPlanner.plan(shifts: [shift("2026-07-18")], leadMinutes: 60, now: now)
        let after = ReminderPlanner.plan(shifts: [shift("2026-07-19")], leadMinutes: 60, now: now)
        #expect(before.map(\.id) == ["shiftly.shift.2026-07-18"])
        #expect(after.map(\.id) == ["shiftly.shift.2026-07-19"])
        #expect(after[0].fireDate == shift("2026-07-19").start.addingTimeInterval(-3600))
    }
}
