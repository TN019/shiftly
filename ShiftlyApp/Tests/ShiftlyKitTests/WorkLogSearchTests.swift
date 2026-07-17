import Foundation
import Testing
@testable import ShiftlyKit

@Suite struct WorkLogSearchTests {
    private func makeStore() throws -> (WorkLogStore, String) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shiftly_search_\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let store = WorkLogStore(rootDir: dir)
        try store.append(entry: "met with Alice about roster", date: "2026-05-10",
                         timeHHMM: "12:00", shift: nil, shiftType: nil)
        try store.append(entry: "quiet day", date: "2026-06-15",
                         timeHHMM: "12:00", shift: nil, shiftType: nil)
        try store.append(entry: "ALICE again, new roster", date: "2026-07-01",
                         timeHHMM: "12:00", shift: nil, shiftType: nil)
        return (store, dir)
    }

    @Test func matchesBodyCaseInsensitiveNewestFirst() throws {
        let (store, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let hits = store.search(query: "alice")
        #expect(hits.map(\.date) == ["2026-07-01", "2026-05-10"])
        #expect(hits[0].snippet.contains("ALICE again"))
    }

    @Test func dateRangeBounds() throws {
        let (store, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        #expect(store.search(query: "alice", from: "2026-06-01", to: nil).map(\.date) == ["2026-07-01"])
        #expect(store.search(query: "alice", from: nil, to: "2026-06-01").map(\.date) == ["2026-05-10"])
        #expect(store.search(query: "alice", from: "2026-06-01", to: "2026-06-30").isEmpty)
    }

    @Test func matchesFrontmatter() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shiftly_search_\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let store = WorkLogStore(rootDir: dir)
        let shift = ShiftTimeBuilder.makeShift(
            date: "2026-07-10", kind: .auto, title: "W", startHHMM: "22:00", endHHMM: "06:00"
        )
        try store.ensureFile(date: "2026-07-10", shift: shift, shiftType: "night")
        let hits = store.search(query: "shift: night")
        #expect(hits.map(\.date) == ["2026-07-10"])
    }

    @Test func emptyQueryAndNoMatches() throws {
        let (store, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        #expect(store.search(query: "  ").isEmpty)
        #expect(store.search(query: "nonexistent-token").isEmpty)
    }

    @Test func thousandFilesUnderASecond() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shiftly_search_\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try FileManager.default.createDirectory(atPath: dir + "/2026", withIntermediateDirectories: true)
        for i in 1...1000 {
            let date = String(format: "2026-%02d-%02d", (i % 12) + 1, (i % 28) + 1)
            let path = "\(dir)/2026/\(date)-\(i).md" // unique names, same dir layout
            try Data("---\ndate: \(date)\n---\nnote \(i) sample text\n".utf8)
                .write(to: URL(fileURLWithPath: path))
        }
        let store = WorkLogStore(rootDir: dir)
        let startTime = Date()
        _ = store.search(query: "sample")
        #expect(Date().timeIntervalSince(startTime) < 1.0)
    }
}
