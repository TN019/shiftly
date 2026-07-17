import Foundation

/// Markdown work logs in a user-chosen folder: `<root>/YYYY/YYYY-MM-DD.md`.
/// Files are plain Markdown with YAML frontmatter — any external editor can
/// own them; Shiftly only creates, appends, and reads.
public struct WorkLogStore {
    public let rootDir: String

    public init(rootDir: String) {
        self.rootDir = (rootDir as NSString).expandingTildeInPath
    }

    /// Default location when config.json has no log_dir.
    public static let defaultDir = "~/Documents/ShiftlyLogs"

    public var rootExists: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: rootDir, isDirectory: &isDir) && isDir.boolValue
    }

    public func path(for date: String) -> String {
        "\(rootDir)/\(date.prefix(4))/\(date).md"
    }

    public func exists(date: String) -> Bool {
        FileManager.default.fileExists(atPath: path(for: date))
    }

    public func read(date: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path(for: date)) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Create the day's file with frontmatter when missing (shift/hours
    /// pre-filled from the plan); existing files are never touched.
    /// Returns the file path.
    @discardableResult
    public func ensureFile(date: String, shift: PlannedShift?, shiftType: String?) throws -> String {
        let filePath = path(for: date)
        guard !FileManager.default.fileExists(atPath: filePath) else { return filePath }
        try FileManager.default.createDirectory(
            atPath: (filePath as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        var front = ["---", "date: \(date)"]
        if let shift {
            let hours = shift.end.timeIntervalSince(shift.start) / 3600
            front.append("shift: \(shiftType ?? "default")")
            front.append("hours: \(String(format: "%.4g", hours))")
        } else {
            front.append("shift: none")
            front.append("hours: 0")
        }
        front.append("tags: []")
        front.append("---")
        front.append("")
        try Data(front.joined(separator: "\n").appending("\n").utf8)
            .write(to: URL(fileURLWithPath: filePath), options: .atomic)
        return filePath
    }

    /// Append a timestamped entry, creating the file first when needed.
    public func append(
        entry: String,
        date: String,
        timeHHMM: String,
        shift: PlannedShift?,
        shiftType: String?
    ) throws {
        let filePath = try ensureFile(date: date, shift: shift, shiftType: shiftType)
        let existing = read(date: date) ?? ""
        let separator = existing.hasSuffix("\n") ? "" : "\n"
        let line = "- \(timeHHMM) \(entry)\n"
        try Data((existing + separator + line).utf8)
            .write(to: URL(fileURLWithPath: filePath), options: .atomic)
    }

    /// Days (YYYY-MM-DD) with a log file in a month ("YYYY-MM").
    public func datesWithLogs(inMonth month: String) -> Set<String> {
        let year = String(month.prefix(4))
        let dir = "\(rootDir)/\(year)"
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return [] }
        return Set(names.compactMap { name in
            guard name.hasSuffix(".md") else { return nil }
            let day = String(name.dropLast(3))
            return day.hasPrefix(month) ? day : nil
        })
    }
}
