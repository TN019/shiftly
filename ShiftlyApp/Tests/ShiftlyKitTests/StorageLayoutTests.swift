import Foundation
import Testing
@testable import ShiftlyKit

private func tempDir() throws -> String {
    let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("storage_\(UUID().uuidString)").path
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    return path
}

@Suite struct StorageLayoutTests {
    @Test func provisionCreatesTheStandardLayout() throws {
        let selected = try tempDir()
        defer { try? FileManager.default.removeItem(atPath: selected) }

        let root = try StorageLayout.provision(selectedPath: selected)

        #expect(root == selected + "/app")
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: selected + "/app/data/config.json"))
        #expect(fm.fileExists(atPath: selected + "/app/meetings"))
        #expect(fm.fileExists(atPath: selected + "/logs"))
        #expect(fm.fileExists(atPath: selected + "/notes"))
        let config = try DataStore(paths: ShiftlyPaths(root: root)).loadConfig()
        #expect(config.log_dir == selected + "/logs")
        #expect(config.notes_dir == selected + "/notes")
        #expect(config.meetings_dir == selected + "/app/meetings")
    }

    @Test func provisionAdoptsLegacyDataRootAsIs() throws {
        let selected = try tempDir()
        defer { try? FileManager.default.removeItem(atPath: selected) }
        try ShiftlyPaths.bootstrapDataDirectory(atRoot: selected)

        let root = try StorageLayout.provision(selectedPath: selected)

        #expect(root == selected, "legacy root adopted unchanged")
        #expect(!FileManager.default.fileExists(atPath: selected + "/app"))
    }

    @Test func moveContentsMovesEverythingAndRemovesSource() throws {
        let base = try tempDir()
        defer { try? FileManager.default.removeItem(atPath: base) }
        let src = base + "/old"
        let dst = base + "/new/nested"
        try FileManager.default.createDirectory(atPath: src + "/sub", withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: src + "/a.md", contents: Data("a".utf8))
        FileManager.default.createFile(atPath: src + "/sub/b.md", contents: Data("b".utf8))

        try StorageLayout.moveContents(of: src, to: dst)

        let fm = FileManager.default
        #expect(fm.fileExists(atPath: dst + "/a.md"))
        #expect(fm.fileExists(atPath: dst + "/sub/b.md"))
        #expect(!fm.fileExists(atPath: src), "emptied source removed")
    }

    @Test func moveContentsRefusesCollisionsAndSelfNesting() throws {
        let base = try tempDir()
        defer { try? FileManager.default.removeItem(atPath: base) }
        let src = base + "/old"
        let dst = base + "/new"
        try FileManager.default.createDirectory(atPath: src, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: dst, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: src + "/a.md", contents: Data("src".utf8))
        FileManager.default.createFile(atPath: dst + "/a.md", contents: Data("dst".utf8))

        #expect(throws: (any Error).self) {
            try StorageLayout.moveContents(of: src, to: dst)
        }
        let kept = FileManager.default.contents(atPath: dst + "/a.md")
        #expect(kept == Data("dst".utf8), "collision aborts, nothing overwritten")
        #expect(FileManager.default.fileExists(atPath: src + "/a.md"), "source untouched")

        #expect(throws: (any Error).self) {
            try StorageLayout.moveContents(of: src, to: src + "/inner")
        }
    }

    @Test func resetWipesRecognizedLogsNotesAndMeetings() throws {
        let base = try tempDir()
        defer { try? FileManager.default.removeItem(atPath: base) }
        let logs = base + "/logs"
        let notes = base + "/notes"
        let meetings = base + "/meetings"
        try FileManager.default.createDirectory(atPath: logs + "/2026", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: notes, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: logs + "/19-07-26.md", contents: Data())
        FileManager.default.createFile(atPath: logs + "/2026/2026-07-17.md", contents: Data())
        FileManager.default.createFile(atPath: logs + "/keep-me.md", contents: Data())
        FileManager.default.createFile(atPath: notes + "/19-07-26 | idea.md", contents: Data())
        let store = MeetingStore(rootDir: meetings)
        _ = try store.newRecordingPath(date: "2026-07-19", timeHHMM: "21:30")
        try FileManager.default.createDirectory(atPath: meetings + "/keep dir", withIntermediateDirectories: true)

        DataReset.wipeLogs(logDir: logs, notesDir: notes)
        DataReset.wipeMeetings(dir: meetings)

        let fm = FileManager.default
        #expect(!fm.fileExists(atPath: logs + "/19-07-26.md"))
        #expect(!fm.fileExists(atPath: logs + "/2026"))
        #expect(fm.fileExists(atPath: logs + "/keep-me.md"), "foreign file preserved")
        #expect(!fm.fileExists(atPath: notes), "emptied notes folder removed")
        #expect(!fm.fileExists(atPath: meetings + "/19-07-26 | 21-30"))
        #expect(fm.fileExists(atPath: meetings + "/keep dir"), "foreign folder preserved")
    }
}
