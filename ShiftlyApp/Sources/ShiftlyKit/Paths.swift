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

    /// UserDefaults key holding the root chosen in the first-run flow.
    /// Environment variables still win, so dev setups stay unaffected.
    public static let rootDefaultsKey = "shiftly.root"

    private static func resolveRoot() -> String {
        if let e = Self.rootFromEnvironment() {
            return e
        }
        if let saved = UserDefaults.standard.string(forKey: rootDefaultsKey),
           FileManager.default.fileExists(atPath: "\(saved)/data/config.json") {
            return saved
        }
        if let r = findRepoRoot(from: executableDirectory()) {
            return r
        }
        if let r = findRepoRoot(from: URL(fileURLWithPath: #filePath).deletingLastPathComponent()) {
            return r
        }
        return ""
    }

    /// Remember a root chosen in the UI for future launches.
    public static func persistRoot(_ root: String) {
        UserDefaults.standard.set(root, forKey: rootDefaultsKey)
    }

    /// Create the minimal data files a fresh root needs (no-op for files
    /// that already exist). Returns true when a new config.json was written.
    @discardableResult
    public static func bootstrapDataDirectory(atRoot root: String) throws -> Bool {
        let fm = FileManager.default
        try fm.createDirectory(atPath: "\(root)/data", withIntermediateDirectories: true)
        for name in ["swaps.json", "leave.json"] {
            let path = "\(root)/data/\(name)"
            if !fm.fileExists(atPath: path) {
                try Data("[]\n".utf8).write(to: URL(fileURLWithPath: path))
            }
        }
        let configPath = "\(root)/data/config.json"
        guard !fm.fileExists(atPath: configPath) else { return false }
        try ConfigLogic.writeRawConfig([
            "config_version": 1,
            "calendar_name": "Shifts",
            "event_title": "Work Schedule",
            "default_start_time": "10:00",
            "default_end_time": "18:30",
            "setup_completed": false,
            "rules": [],
        ], toPath: configPath)
        return true
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
