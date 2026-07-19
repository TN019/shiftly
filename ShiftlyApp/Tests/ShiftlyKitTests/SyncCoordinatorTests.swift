import Foundation
import Testing
@testable import ShiftlyKit

/// Test schedule provider that mimics the Python planner over the data
/// files: base rule dates, minus swapped-away days, plus swap targets,
/// minus leave days.
private struct StubProvider: ScheduleProvider {
    let store: DataStore
    let baseDates: [String]
    let range: (String, String)

    func plannedDays(start: String, end: String) throws -> [PlannedDay] {
        var dates = Set(baseDates)
        for swap in (try? store.loadSwaps()) ?? [] {
            dates.remove(swap.from_date)
            if swap.to_date >= start && swap.to_date <= end {
                dates.insert(swap.to_date)
            }
        }
        for leave in (try? store.loadLeaves()) ?? [] {
            dates = dates.filter { $0 < leave.start_date || $0 > leave.end_date }
        }
        return dates.filter { $0 >= start && $0 <= end }.sorted()
            .map { PlannedDay(date: $0, source: "rule", shiftType: "default") }
    }

    func syncRange() throws -> (start: String, end: String) {
        range
    }
}

private struct TempRoot {
    let root: String
    let store: DataStore
    let stateStore: SyncStateStore

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("shiftly_coord_\(UUID().uuidString)").path
        try FileManager.default.createDirectory(
            atPath: root + "/data", withIntermediateDirectories: true
        )
        let config: [String: Any] = [
            "config_version": 1,
            "calendar_name": "Shifts",
            "event_title": "Work Schedule",
            "default_start_time": "10:00",
            "default_end_time": "18:30",
            "setup_completed": true,
            "rules": [],
        ]
        try ConfigLogic.writeRawConfig(config, toPath: root + "/data/config.json")
        try Data("[]".utf8).write(to: URL(fileURLWithPath: root + "/data/swaps.json"))
        try Data("[]".utf8).write(to: URL(fileURLWithPath: root + "/data/leave.json"))
        store = DataStore(paths: ShiftlyPaths(root: root))
        stateStore = SyncStateStore(path: root + "/data/sync_state.json")
    }

    func destroy() {
        try? FileManager.default.removeItem(atPath: root)
    }
}

@Suite struct ReadbackApplierTests {
    @Test func allFourKindsLandInTheRightFiles() throws {
        let tmp = try TempRoot()
        defer { tmp.destroy() }
        let applier = ReadbackApplier(store: tmp.store)

        let written = try applier.apply([
            .moved(fromDate: "2026-07-20", toDate: "2026-07-22", eventID: "e1"),
            .retimed(date: "2026-07-21", eventID: "e2", startHHMM: "12:00", endHHMM: "20:00"),
            .deleted(date: "2026-07-23"),
            .newManual(date: "2026-07-25", eventID: "e3", startHHMM: "09:00", endHHMM: "17:00"),
        ])
        #expect(written == 4)
        #expect(try tmp.store.loadSwaps() == [SwapItem(from_date: "2026-07-20", to_date: "2026-07-22")])
        #expect(tmp.store.loadOverrides() == [TimeOverride(date: "2026-07-21", start: "12:00", end: "20:00")])
        #expect(try tmp.store.loadLeaves() == [LeaveItem(start_date: "2026-07-23", end_date: "2026-07-23")])
        #expect(tmp.store.loadManualShifts() == [ManualShift(date: "2026-07-25", start: "09:00", end: "17:00")])
    }

    @Test func retimeUpsertsAndManualDeduplicates() throws {
        let tmp = try TempRoot()
        defer { tmp.destroy() }
        let applier = ReadbackApplier(store: tmp.store)

        try applier.apply([
            .retimed(date: "2026-07-21", eventID: "e", startHHMM: "12:00", endHHMM: "20:00"),
            .newManual(date: "2026-07-25", eventID: "e", startHHMM: "09:00", endHHMM: "17:00"),
        ])
        try applier.apply([
            .retimed(date: "2026-07-21", eventID: "e", startHHMM: "13:00", endHHMM: "21:00"),
            .newManual(date: "2026-07-25", eventID: "e", startHHMM: "09:00", endHHMM: "17:00"),
        ])
        #expect(tmp.store.loadOverrides() == [TimeOverride(date: "2026-07-21", start: "13:00", end: "21:00")])
        #expect(tmp.store.loadManualShifts().count == 1)
    }
}

@Suite struct SyncDataSourceTests {
    @Test func defaultTimesOverridesAndManualCompose() throws {
        let tmp = try TempRoot()
        defer { tmp.destroy() }
        try tmp.store.saveOverrides([TimeOverride(date: "2026-07-21", start: "12:00", end: "20:00")])
        try tmp.store.saveManualShifts([ManualShift(date: "2026-07-25", start: "09:00", end: "17:00")])

        let provider = StubProvider(
            store: tmp.store,
            baseDates: ["2026-07-20", "2026-07-21"],
            range: ("2026-07-20", "2026-07-31")
        )
        let source = SyncDataSource(store: tmp.store, provider: provider)
        let shifts = try source.plannedShifts(start: "2026-07-20", end: "2026-07-31")

        #expect(shifts.map(\.date) == ["2026-07-20", "2026-07-21", "2026-07-25"])
        #expect(SyncFingerprint.hhmmString(for: shifts[0].start) == "10:00", "default time")
        #expect(SyncFingerprint.hhmmString(for: shifts[1].start) == "12:00", "override applied")
        #expect(shifts[2].kind == .manual)
    }
}

@Suite struct SyncCoordinatorFlows {
    @Test func fullBidirectionalCycle() throws {
        let tmp = try TempRoot()
        defer { tmp.destroy() }
        let calendar = InMemoryCalendarStore()
        let provider = StubProvider(
            store: tmp.store,
            baseDates: ["2026-07-20", "2026-07-21"],
            range: ("2026-07-01", "2026-08-31")
        )
        let coordinator = SyncCoordinator(
            store: tmp.store, stateStore: tmp.stateStore,
            calendar: calendar, provider: provider
        )

        // Sync 1: both days created.
        let first = try coordinator.sync()
        #expect(first.created == 2)
        #expect(tmp.store.loadMeta()?.last_sync_status == "success")

        // User drags the 20th to the 23rd in Calendar.
        let movedID = tmp.stateStore.load().entries.first { $0.date == "2026-07-20" }!.event_id
        let target = ShiftTimeBuilder.makeShift(
            date: "2026-07-23", kind: .auto, title: "Work Schedule",
            startHHMM: "10:00", endHHMM: "18:30"
        )!
        calendar.userEdit(id: movedID, start: target.start, end: target.end)

        // Sync 2: readback → swaps.json, converged in the same run.
        let second = try coordinator.sync()
        #expect(second.readbacks == [.moved(fromDate: "2026-07-20", toDate: "2026-07-23", eventID: movedID)])
        #expect(second.converged)
        #expect(try tmp.store.loadSwaps() == [SwapItem(from_date: "2026-07-20", to_date: "2026-07-23")])

        // Sync 3: nothing left to do.
        calendar.resetWriteCount()
        let third = try coordinator.sync()
        #expect(third.created == 0 && third.updated == 0 && third.deleted == 0 && third.readbacks.isEmpty)
        #expect(calendar.writeCount == 0)
        #expect(calendar.storage.count == 2)
    }

    @Test func calendarIdentifierIsPersistedInState() throws {
        let tmp = try TempRoot()
        defer { tmp.destroy() }
        let provider = StubProvider(
            store: tmp.store,
            baseDates: ["2026-07-20"],
            range: ("2026-07-01", "2026-08-31")
        )
        let coordinator = SyncCoordinator(
            store: tmp.store, stateStore: tmp.stateStore,
            calendar: InMemoryCalendarStore(), provider: provider,
            calendarIdentifier: "CAL-123"
        )
        _ = try coordinator.sync()
        #expect(tmp.stateStore.load().calendar_id == "CAL-123")
    }

    @Test func failureIsRecordedInMeta() throws {
        struct FailingProvider: ScheduleProvider {
            func plannedDays(start: String, end: String) throws -> [PlannedDay] {
                throw SyncFailure("planner exploded")
            }
            func syncRange() throws -> (start: String, end: String) {
                ("2026-07-01", "2026-07-31")
            }
        }
        let tmp = try TempRoot()
        defer { tmp.destroy() }
        let coordinator = SyncCoordinator(
            store: tmp.store, stateStore: tmp.stateStore,
            calendar: InMemoryCalendarStore(), provider: FailingProvider()
        )
        #expect(throws: (any Error).self) {
            try coordinator.sync()
        }
        let meta = tmp.store.loadMeta()
        #expect(meta?.last_sync_status == "error")
        #expect(meta?.last_sync_error?.contains("planner exploded") == true)
    }
}
