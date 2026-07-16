import Foundation
import Testing
@testable import ShiftlyKit

private let TITLE = "Work Schedule"

private func shift(_ date: String, _ start: String = "10:00", _ end: String = "18:30", kind: ShiftKind = .auto) -> PlannedShift {
    ShiftTimeBuilder.makeShift(date: date, kind: kind, title: TITLE, startHHMM: start, endHHMM: end)!
}

/// One full sync pass: plan, execute writes, persist entries.
private func syncOnce(
    planned: [PlannedShift],
    store: InMemoryCalendarStore,
    state: SyncStateFile
) throws -> (plan: SyncPlan, state: SyncStateFile) {
    let window = DateInterval(start: Date.distantPast, end: Date.distantFuture)
    let plan = SyncEngine.plan(
        planned: planned,
        events: try store.events(in: window),
        state: state,
        eventTitle: TITLE
    )
    let entries = try SyncEngine.execute(plan, on: store)
    return (plan, SyncStateFile(entries: entries))
}

/// Simulates the data-file side of readback application: derive the next
/// planned set the way swaps/overrides/leave/manual records would.
private func applyReadbacks(_ readbacks: [ReadbackChange], to planned: [PlannedShift]) -> [PlannedShift] {
    var byDate = Dictionary(planned.map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })
    for change in readbacks {
        switch change {
        case .moved(let from, let to, _):
            let moved = byDate.removeValue(forKey: from)
            if moved != nil {
                byDate[to] = shift(to)
            }
        case .retimed(let date, _, let s, let e):
            byDate[date] = shift(date, s, e)
        case .deleted(let date):
            byDate[date] = nil
        case .newManual(let date, _, let s, let e):
            byDate[date] = shift(date, s, e, kind: .manual)
        }
    }
    return byDate.values.sorted { $0.date < $1.date }
}

@Suite struct SyncEngineFlows {
    @Test func firstSyncCreatesEverythingThenConverges() throws {
        let store = InMemoryCalendarStore()
        let planned = [shift("2026-07-20"), shift("2026-07-21"), shift("2026-07-23")]

        let first = try syncOnce(planned: planned, store: store, state: .empty)
        #expect(first.plan.creates.count == 3)
        #expect(store.storage.count == 3)

        store.resetWriteCount()
        let second = try syncOnce(planned: planned, store: store, state: first.state)
        #expect(second.plan.isNoop)
        #expect(store.writeCount == 0, "second sync must not touch the calendar")
    }

    @Test func shiftlySideTimeChangeUpdatesOnlyThatEvent() throws {
        let store = InMemoryCalendarStore()
        let planned = [shift("2026-07-20"), shift("2026-07-21")]
        let s1 = try syncOnce(planned: planned, store: store, state: .empty)
        let idsBefore = Set(store.storage.keys)

        // Change only the 21st in Shiftly.
        let newPlanned = [shift("2026-07-20"), shift("2026-07-21", "12:00", "20:00")]
        store.resetWriteCount()
        let s2 = try syncOnce(planned: newPlanned, store: store, state: s1.state)
        #expect(s2.plan.updates.count == 1)
        #expect(s2.plan.creates.isEmpty && s2.plan.deletes.isEmpty && s2.plan.readbacks.isEmpty)
        #expect(store.writeCount == 1)
        #expect(Set(store.storage.keys) == idsBefore, "eventIdentifiers must be stable across updates")
    }

    @Test func cancelledDayDeletesItsEvent() throws {
        let store = InMemoryCalendarStore()
        let planned = [shift("2026-07-20"), shift("2026-07-21")]
        let s1 = try syncOnce(planned: planned, store: store, state: .empty)

        // Leave on the 21st: planner stops emitting it.
        let s2 = try syncOnce(planned: [shift("2026-07-20")], store: store, state: s1.state)
        #expect(s2.plan.deletes.count == 1)
        #expect(store.storage.count == 1)
    }

    @Test func userMoveBecomesSwapAndConverges() throws {
        let store = InMemoryCalendarStore()
        var planned = [shift("2026-07-20"), shift("2026-07-21")]
        let s1 = try syncOnce(planned: planned, store: store, state: .empty)

        // User drags the 20th's event to the 22nd.
        let movedID = s1.state.entries.first { $0.date == "2026-07-20" }!.event_id
        let target = shift("2026-07-22")
        store.userEdit(id: movedID, start: target.start, end: target.end)

        let s2 = try syncOnce(planned: planned, store: store, state: s1.state)
        #expect(s2.plan.readbacks == [.moved(fromDate: "2026-07-20", toDate: "2026-07-22", eventID: movedID)])
        #expect(s2.plan.creates.isEmpty && s2.plan.deletes.isEmpty && s2.plan.updates.isEmpty)

        // Apply the swap to the data files, re-plan, converge.
        planned = applyReadbacks(s2.plan.readbacks, to: planned)
        store.resetWriteCount()
        let s3 = try syncOnce(planned: planned, store: store, state: s2.state)
        #expect(s3.plan.isNoop, "post-readback pass must converge")
        #expect(store.writeCount == 0)
    }

    @Test func userRetimeBecomesOverrideAndConverges() throws {
        let store = InMemoryCalendarStore()
        var planned = [shift("2026-07-20")]
        let s1 = try syncOnce(planned: planned, store: store, state: .empty)

        let id = s1.state.entries[0].event_id
        let edited = shift("2026-07-20", "12:00", "20:00")
        store.userEdit(id: id, start: edited.start, end: edited.end)

        let s2 = try syncOnce(planned: planned, store: store, state: s1.state)
        #expect(s2.plan.readbacks == [.retimed(date: "2026-07-20", eventID: id, startHHMM: "12:00", endHHMM: "20:00")])

        planned = applyReadbacks(s2.plan.readbacks, to: planned)
        store.resetWriteCount()
        let s3 = try syncOnce(planned: planned, store: store, state: s2.state)
        #expect(s3.plan.isNoop)
        #expect(store.writeCount == 0)
    }

    @Test func userDeleteBecomesDayOffAndConverges() throws {
        let store = InMemoryCalendarStore()
        var planned = [shift("2026-07-20"), shift("2026-07-21")]
        let s1 = try syncOnce(planned: planned, store: store, state: .empty)

        let id = s1.state.entries.first { $0.date == "2026-07-21" }!.event_id
        store.userDelete(id: id)

        let s2 = try syncOnce(planned: planned, store: store, state: s1.state)
        #expect(s2.plan.readbacks == [.deleted(date: "2026-07-21")])

        planned = applyReadbacks(s2.plan.readbacks, to: planned)
        store.resetWriteCount()
        let s3 = try syncOnce(planned: planned, store: store, state: s2.state)
        #expect(s3.plan.isNoop)
        #expect(store.writeCount == 0)
    }

    @Test func userCreatedShiftBecomesManualAndConverges() throws {
        let store = InMemoryCalendarStore()
        var planned = [shift("2026-07-20")]
        let s1 = try syncOnce(planned: planned, store: store, state: .empty)

        // User creates a shift-style event on a free day.
        let extra = shift("2026-07-25", "09:00", "17:00")
        _ = try store.createEvent(title: TITLE, start: extra.start, end: extra.end)
        store.resetWriteCount()

        let s2 = try syncOnce(planned: planned, store: store, state: s1.state)
        guard case .newManual(let date, _, let s, let e)? = s2.plan.readbacks.first else {
            Issue.record("expected newManual, got \(s2.plan.readbacks)")
            return
        }
        #expect(date == "2026-07-25" && s == "09:00" && e == "17:00")

        planned = applyReadbacks(s2.plan.readbacks, to: planned)
        let s3 = try syncOnce(planned: planned, store: store, state: s2.state)
        #expect(s3.plan.isNoop)
        #expect(store.writeCount == 0, "manual event must be adopted, not rewritten")
    }

    @Test func foreignEventsAreNeverTouched() throws {
        let dentist = ShiftTimeBuilder.makeShift(
            date: "2026-07-20", kind: .auto, title: "Dentist",
            startHHMM: "11:00", endHHMM: "12:00"
        )!
        let store = InMemoryCalendarStore(events: [
            CalendarEventInfo(id: "user-1", title: "Dentist", start: dentist.start, end: dentist.end)
        ])
        let planned = [shift("2026-07-20")]

        let s1 = try syncOnce(planned: planned, store: store, state: .empty)
        #expect(s1.plan.ignoredForeign.map(\.id) == ["user-1"])
        #expect(store.storage["user-1"] != nil, "foreign event must survive")
        #expect(store.storage.count == 2)

        let s2 = try syncOnce(planned: planned, store: store, state: s1.state)
        #expect(s2.plan.isNoop)
        #expect(s2.plan.ignoredForeign.map(\.id) == ["user-1"], "still reported, still untouched")
    }

    @Test func cancelPlusUserEditKeepsCalendarVersion() throws {
        let store = InMemoryCalendarStore()
        let s1 = try syncOnce(planned: [shift("2026-07-20")], store: store, state: .empty)

        // Shiftly cancels the day; the user simultaneously retimed the event.
        let id = s1.state.entries[0].event_id
        let edited = shift("2026-07-20", "14:00", "22:00")
        store.userEdit(id: id, start: edited.start, end: edited.end)

        let s2 = try syncOnce(planned: [], store: store, state: s1.state)
        guard case .newManual(let date, _, _, _)? = s2.plan.readbacks.first else {
            Issue.record("expected newManual (calendar wins), got \(s2.plan.readbacks)")
            return
        }
        #expect(date == "2026-07-20")
        #expect(store.storage[id] != nil, "conflict: calendar wins, event survives")
    }
}

@Suite struct SyncEngineRecovery {
    @Test func stateLossReclaimsWithoutDuplicates() throws {
        let store = InMemoryCalendarStore()
        let planned = [shift("2026-07-20"), shift("2026-07-21")]
        _ = try syncOnce(planned: planned, store: store, state: .empty)
        #expect(store.storage.count == 2)

        // sync_state.json lost: run with empty state.
        store.resetWriteCount()
        let recovered = try syncOnce(planned: planned, store: store, state: .empty)
        #expect(store.storage.count == 2, "no duplicate events after state loss")
        #expect(recovered.plan.creates.isEmpty)
        #expect(recovered.state.entries.count == 2)

        let converged = try syncOnce(planned: planned, store: store, state: recovered.state)
        #expect(converged.plan.isNoop)
    }

    @Test func legacyMarkedEventsAreClaimedOrCleared() throws {
        let onPlan = shift("2026-07-20")
        let stale = shift("2026-07-01")
        let store = InMemoryCalendarStore(events: [
            CalendarEventInfo(id: "old-1", title: TITLE, start: onPlan.start, end: onPlan.end,
                              notes: "[SF_SYNC]\ntype=shift\nsource=auto"),
            CalendarEventInfo(id: "old-2", title: TITLE, start: stale.start, end: stale.end,
                              notes: "[SF_SYNC]\ntype=shift\nsource=auto"),
        ])
        let planned = [shift("2026-07-20")]

        let s1 = try syncOnce(planned: planned, store: store, state: .empty)
        #expect(s1.plan.creates.isEmpty, "matching legacy event claimed, not duplicated")
        #expect(store.storage["old-1"] != nil)
        #expect(store.storage["old-2"] == nil, "stale legacy event cleared like the old engine would")
        #expect(s1.state.entries.map(\.event_id) == ["old-1"])

        let s2 = try syncOnce(planned: planned, store: store, state: s1.state)
        #expect(s2.plan.isNoop)
    }
}

@Suite struct ShiftTimeBuilderTests {
    @Test func overnightShiftEndsNextDay() {
        let s = shift("2026-07-20", "22:00", "06:00")
        #expect(s.end > s.start)
        #expect(Calendar.current.dateComponents([.day], from: s.start, to: s.end).day == 0)
        #expect(SyncFingerprint.dayString(for: s.end) == "2026-07-21")
    }

    @Test func invalidInputsReturnNil() {
        #expect(ShiftTimeBuilder.makeShift(date: "garbage", kind: .auto, title: TITLE,
                                           startHHMM: "10:00", endHHMM: "18:00") == nil)
        #expect(ShiftTimeBuilder.makeShift(date: "2026-07-20", kind: .auto, title: TITLE,
                                           startHHMM: "banana", endHHMM: "18:00") == nil)
    }
}

@Suite struct SyncStateStoreTests {
    private func tempPath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("sync_state_\(UUID().uuidString)/sync_state.json").path
    }

    @Test func missingFileIsEmptyState() {
        #expect(SyncStateStore(path: tempPath()).load() == .empty)
    }

    @Test func roundTrip() throws {
        let store = SyncStateStore(path: tempPath())
        var state = SyncStateFile()
        state.entries = [SyncEntry(date: "2026-07-20", kind: .auto, event_id: "x", fingerprint: "f")]
        state.last_sync_at = "2026-07-16T12:00:00+08:00"
        try store.save(state)
        #expect(store.load() == state)
    }

    @Test func corruptFileIsBackedUpAndTreatedAsEmpty() throws {
        let path = tempPath()
        let store = SyncStateStore(path: path)
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        try Data("{broken".utf8).write(to: URL(fileURLWithPath: path))
        #expect(store.load() == .empty)
        #expect(FileManager.default.fileExists(atPath: path + ".corrupt"))
    }
}
