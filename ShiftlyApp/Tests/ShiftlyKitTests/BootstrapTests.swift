import Foundation
import Testing
@testable import ShiftlyKit

@Suite struct BootstrapDataDirectoryTests {
    private func tempRoot() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("shiftly_boot_\(UUID().uuidString)").path
    }

    @Test func freshRootGetsStarterFiles() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }

        let created = try ShiftlyPaths.bootstrapDataDirectory(atRoot: root)
        #expect(created)
        let cfg = try ConfigLogic.readRawConfig(atPath: "\(root)/data/config.json")
        #expect(cfg["calendar_name"] as? String == "Shifts")
        #expect(cfg["setup_completed"] as? Bool == false)
        let store = DataStore(paths: ShiftlyPaths(root: root))
        #expect(try store.loadSwaps().isEmpty)
        #expect(try store.loadLeaves().isEmpty)
    }

    @Test func existingDataIsNeverTouched() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try FileManager.default.createDirectory(atPath: "\(root)/data", withIntermediateDirectories: true)
        try ConfigLogic.writeRawConfig(
            ["calendar_name": "MyShifts", "my_custom": 7],
            toPath: "\(root)/data/config.json"
        )
        try Data(#"[{"from_date":"2026-01-05","to_date":"2026-01-07"}]"#.utf8)
            .write(to: URL(fileURLWithPath: "\(root)/data/swaps.json"))

        let created = try ShiftlyPaths.bootstrapDataDirectory(atRoot: root)
        #expect(!created)
        let cfg = try ConfigLogic.readRawConfig(atPath: "\(root)/data/config.json")
        #expect(cfg["calendar_name"] as? String == "MyShifts")
        #expect(cfg["my_custom"] as? Int == 7)
        let store = DataStore(paths: ShiftlyPaths(root: root))
        #expect(try store.loadSwaps().count == 1)
    }
}

@Suite struct ScriptLocatorTests {
    @Test func dataRootScriptsWinOverBundle() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("shiftly_loc_\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: root) }
        try FileManager.default.createDirectory(atPath: "\(root)/scripts", withIntermediateDirectories: true)
        try Data("print()".utf8).write(to: URL(fileURLWithPath: "\(root)/scripts/planner.py"))

        #expect(ScriptLocator.locate("planner.py", root: root) == "\(root)/scripts/planner.py")
        // Missing everywhere (test bundle carries no scripts): nil, not a bad path.
        #expect(ScriptLocator.locate("nonexistent.py", root: root) == nil)
    }
}
