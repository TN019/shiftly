import Foundation
import Testing
@testable import ShiftlyKit

private func makeRoot() throws -> (root: String, store: DataStore, journal: ReadbackJournal) {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("shiftly_report_\(UUID().uuidString)").path
    try FileManager.default.createDirectory(atPath: root + "/data", withIntermediateDirectories: true)
    try Data("[]".utf8).write(to: URL(fileURLWithPath: root + "/data/swaps.json"))
    try Data("[]".utf8).write(to: URL(fileURLWithPath: root + "/data/leave.json"))
    let paths = ShiftlyPaths(root: root)
    return (root, DataStore(paths: paths), ReadbackJournal(paths: paths))
}

@Suite struct ReadbackJournalTests {
    @Test func appendLoadAndMarkUndone() throws {
        let (root, _, journal) = try makeRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }

        try journal.append([
            .moved(fromDate: "2026-07-20", toDate: "2026-07-22", eventID: "e1"),
            .deleted(date: "2026-07-23"),
        ], at: "2026-07-17T10:00:00+08:00")

        var records = journal.load()
        #expect(records.count == 2)
        #expect(records[0].kind == .moved && records[0].to_date == "2026-07-22")
        #expect(records.allSatisfy { !$0.undone })

        try journal.markUndone(id: records[1].id)
        records = journal.load()
        #expect(records[1].undone)
        #expect(!records[0].undone)
    }

    @Test func journalIsCapped() throws {
        let (root, _, journal) = try makeRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }

        for i in 0..<(ReadbackJournal.cap + 10) {
            try journal.append([.deleted(date: "2026-01-\(String(format: "%02d", (i % 28) + 1))")],
                               at: "t\(i)")
        }
        #expect(journal.load().count == ReadbackJournal.cap)
        #expect(journal.load().last?.at == "t\(ReadbackJournal.cap + 9)")
    }
}

@Suite struct ReadbackUndoTests {
    @Test func undoRemovesExactlyTheRecordItCreated() throws {
        let (root, store, journal) = try makeRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let applier = ReadbackApplier(store: store)
        let undo = ReadbackUndoService(store: store, journal: journal)

        let changes: [ReadbackChange] = [
            .moved(fromDate: "2026-07-20", toDate: "2026-07-22", eventID: "e1"),
            .retimed(date: "2026-07-21", eventID: "e2", startHHMM: "12:00", endHHMM: "20:00"),
            .deleted(date: "2026-07-23"),
            .newManual(date: "2026-07-25", eventID: "e3", startHHMM: "09:00", endHHMM: "17:00"),
        ]
        try applier.apply(changes)
        try journal.append(changes, at: "t0")
        // Unrelated pre-existing data must survive undo.
        var swaps = try store.loadSwaps()
        swaps.append(SwapItem(from_date: "2026-08-01", to_date: "2026-08-02"))
        try store.saveSwaps(swaps)

        for record in journal.load() {
            #expect(try undo.undo(record))
        }

        #expect(try store.loadSwaps() == [SwapItem(from_date: "2026-08-01", to_date: "2026-08-02")])
        #expect(store.loadOverrides().isEmpty)
        #expect(try store.loadLeaves().isEmpty)
        #expect(store.loadManualShifts().isEmpty)
        let allUndone = journal.load().allSatisfy { $0.undone }
        #expect(allUndone)
    }

    @Test func undoTwiceOrMissingRecordReturnsFalse() throws {
        let (root, store, journal) = try makeRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let applier = ReadbackApplier(store: store)
        let undo = ReadbackUndoService(store: store, journal: journal)

        let change: ReadbackChange = .deleted(date: "2026-07-23")
        try applier.apply([change])
        try journal.append([change], at: "t0")
        let record = journal.load()[0]

        #expect(try undo.undo(record))
        let reloaded = journal.load()[0]
        #expect(try !undo.undo(reloaded), "already undone")

        // A journal record whose data was hand-edited away.
        try journal.append([.retimed(date: "2026-07-24", eventID: "e", startHHMM: "1:00", endHHMM: "2:00")], at: "t1")
        let orphan = journal.load().last!
        #expect(try !undo.undo(orphan))
    }
}

@Suite struct SyncReportFileTests {
    @Test func reportRoundTrip() throws {
        let (root, store, _) = try makeRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }

        #expect(store.loadSyncReport() == nil)
        let report = SyncReportFile(
            at: "2026-07-17T10:00:00+08:00", status: "error", error: "no permission",
            created: 1, updated: 2, deleted: 3, readback_count: 4,
            ignored_foreign: ["Dentist"], converged: false
        )
        try store.saveSyncReport(report)
        #expect(store.loadSyncReport() == report)
    }
}
