import Foundation
import Testing
@testable import ShiftlyKit

private func tempLogDir() -> String {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("shiftly_logs_\(UUID().uuidString)").path
}

private func dayShift(_ date: String) -> PlannedShift {
    ShiftTimeBuilder.makeShift(date: date, kind: .auto, title: "W", startHHMM: "10:00", endHHMM: "18:30")!
}

@Suite struct WorkLogStoreTests {
    @Test func layoutAndFrontmatterWithShift() throws {
        let dir = tempLogDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let store = WorkLogStore(rootDir: dir)

        let path = try store.ensureFile(date: "2026-07-17", shift: dayShift("2026-07-17"), shiftType: "day")
        #expect(path == "\(dir)/2026/2026-07-17.md")
        let content = store.read(date: "2026-07-17")!
        #expect(content.hasPrefix("---\ndate: 2026-07-17\nshift: day\nhours: 8.5\ntags: []\n---\n"))
    }

    @Test func frontmatterWithoutShift() throws {
        let dir = tempLogDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let store = WorkLogStore(rootDir: dir)
        try store.ensureFile(date: "2026-07-19", shift: nil, shiftType: nil)
        let content = store.read(date: "2026-07-19")!
        #expect(content.contains("shift: none"))
        #expect(content.contains("hours: 0"))
    }

    @Test func ensureNeverTouchesExistingFiles() throws {
        let dir = tempLogDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try FileManager.default.createDirectory(atPath: dir + "/2026", withIntermediateDirectories: true)
        let hand = "my own file, no frontmatter\n"
        try Data(hand.utf8).write(to: URL(fileURLWithPath: dir + "/2026/2026-07-17.md"))
        let store = WorkLogStore(rootDir: dir)
        try store.ensureFile(date: "2026-07-17", shift: dayShift("2026-07-17"), shiftType: "day")
        #expect(store.read(date: "2026-07-17") == hand)
    }

    @Test func appendCreatesAndAccumulates() throws {
        let dir = tempLogDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let store = WorkLogStore(rootDir: dir)

        try store.append(entry: "first note", date: "2026-07-17", timeHHMM: "12:30",
                         shift: dayShift("2026-07-17"), shiftType: "day")
        try store.append(entry: "second note", date: "2026-07-17", timeHHMM: "18:00",
                         shift: dayShift("2026-07-17"), shiftType: "day")
        let content = store.read(date: "2026-07-17")!
        #expect(content.contains("- 12:30 first note\n"))
        #expect(content.hasSuffix("- 18:00 second note\n"))
        #expect(content.components(separatedBy: "---").count == 3, "frontmatter written once")
    }

    @Test func datesWithLogsScansMonth() throws {
        let dir = tempLogDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let store = WorkLogStore(rootDir: dir)
        try store.ensureFile(date: "2026-07-01", shift: nil, shiftType: nil)
        try store.ensureFile(date: "2026-07-15", shift: nil, shiftType: nil)
        try store.ensureFile(date: "2026-08-01", shift: nil, shiftType: nil)
        #expect(store.datesWithLogs(inMonth: "2026-07") == ["2026-07-01", "2026-07-15"])
        #expect(store.datesWithLogs(inMonth: "2026-06").isEmpty)
    }

    @Test func missingRootReportsNotExists() {
        let store = WorkLogStore(rootDir: tempLogDir())
        #expect(!store.rootExists)
        #expect(store.read(date: "2026-07-17") == nil)
    }
}
