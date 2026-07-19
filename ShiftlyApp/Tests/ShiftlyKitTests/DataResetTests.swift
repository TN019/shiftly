import Foundation
import Testing
@testable import ShiftlyKit

@Suite struct DataResetTests {
    private func makeRoot(files: [String]) throws -> String {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("reset_\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: root + "/data", withIntermediateDirectories: true)
        for name in files {
            FileManager.default.createFile(atPath: root + "/data/" + name, contents: Data("{}".utf8))
        }
        return root
    }

    @Test func wipesEveryOwnedFileAndEmptyDirectory() throws {
        let root = try makeRoot(files: DataReset.ownedFiles)
        defer { try? FileManager.default.removeItem(atPath: root) }

        let removed = try DataReset.wipeData(atRoot: root)

        #expect(removed == DataReset.ownedFiles.count)
        #expect(!FileManager.default.fileExists(atPath: root + "/data"), "empty data dir removed")
    }

    @Test func keepsForeignFilesAndTheDirectoryHoldingThem() throws {
        let root = try makeRoot(files: ["config.json", "notes-by-user.txt"])
        defer { try? FileManager.default.removeItem(atPath: root) }

        let removed = try DataReset.wipeData(atRoot: root)

        #expect(removed == 1)
        #expect(FileManager.default.fileExists(atPath: root + "/data/notes-by-user.txt"))
        #expect(FileManager.default.fileExists(atPath: root + "/data"), "dir kept while it has user files")
    }
}
