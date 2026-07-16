import Foundation

public struct ShiftlyPaths {
    public static let shared = ShiftlyPaths()

    public let root: String

    private init() {
        root = Self.resolveRoot()
    }

    /// Explicit-root paths, for tests and tools operating on a chosen root.
    public init(root: String) {
        self.root = root
    }

    public var isValid: Bool { !root.isEmpty }

    public var configPath: String { "\(root)/data/config.json" }
    public var swapsPath: String { "\(root)/data/swaps.json" }
    public var leavePath: String { "\(root)/data/leave.json" }
    public var syncScriptPath: String { "\(root)/scripts/sync.applescript" }
    public var metaPath: String { "\(root)/data/meta.json" }
    public var workHistoryScript: String { "\(root)/scripts/work_history.py" }

    private static func resolveRoot() -> String {
        if let e = Self.rootFromEnvironment() {
            return e
        }
        if let r = findRepoRoot(from: executableDirectory()) {
            return r
        }
        if let r = findRepoRoot(from: URL(fileURLWithPath: #filePath).deletingLastPathComponent()) {
            return r
        }
        return ""
    }

    private static func rootFromEnvironment() -> String? {
        for key in ["SHIFTLY_ROOT", "SHIFTY_ROOT", "SHIFTFLOW_ROOT"] {
            if let e = ProcessInfo.processInfo.environment[key], !e.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return (e as NSString).standardizingPath
            }
        }
        return nil
    }

    private static func executableDirectory() -> URL {
        let path = Bundle.main.executablePath
            ?? ProcessInfo.processInfo.arguments.first
            ?? "/"
        return URL(fileURLWithPath: path).deletingLastPathComponent().standardizedFileURL
    }

    private static func findRepoRoot(from start: URL) -> String? {
        var url = start.standardizedFileURL
        for _ in 0..<16 {
            let example = url.appendingPathComponent("data/config.example.json")
            let cfg = url.appendingPathComponent("data/config.json")
            if FileManager.default.fileExists(atPath: example.path) || FileManager.default.fileExists(atPath: cfg.path) {
                return url.path
            }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { break }
            url = parent
        }
        return nil
    }

    public static func applyRepoRootEnvironment(_ env: inout [String: String], root: String) {
        env["SHIFTLY_ROOT"] = root
        // Legacy names kept for scripts that still read them.
        env["SHIFTY_ROOT"] = root
        env["SHIFTFLOW_ROOT"] = root
    }
}
