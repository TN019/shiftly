import Foundation

/// Markdown work logs in a user-chosen folder, one file per shift day named
/// `dd-mm-yy.md` (2026-07-19 → `19-07-26.md`), flat in the folder. Files
/// written by older versions under `YYYY/YYYY-MM-DD.md` stay readable and
/// keep receiving appends. Files are plain Markdown with YAML frontmatter —
/// any external editor can own them; Shiftly only creates, appends, reads.
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

    /// "2026-07-19" → "19-07-26.md".
    public static func fileName(for date: String) -> String {
        let parts = date.split(separator: "-")
        guard parts.count == 3, parts[0].count == 4 else { return "\(date).md" }
        return "\(parts[2])-\(parts[1])-\(parts[0].suffix(2)).md"
    }

    /// "19-07-26.md" → "2026-07-19"; nil for anything else.
    public static func date(fromFileName name: String) -> String? {
        guard name.hasSuffix(".md") else { return nil }
        let parts = name.dropLast(3).split(separator: "-")
        guard parts.count == 3, parts.allSatisfy({ $0.count == 2 && Int($0) != nil }) else {
            return nil
        }
        return "20\(parts[2])-\(parts[1])-\(parts[0])"
    }

    /// Where a new file for the day goes.
    public func path(for date: String) -> String {
        "\(rootDir)/\(Self.fileName(for: date))"
    }

    /// Pre-rename layout; still honored when the file is already there.
    private func legacyPath(for date: String) -> String {
        "\(rootDir)/\(date.prefix(4))/\(date).md"
    }

    /// The day's file if one exists in either layout (legacy wins so a
    /// day's entries never split across two files).
    public func existingPath(for date: String) -> String? {
        let legacy = legacyPath(for: date)
        if FileManager.default.fileExists(atPath: legacy) { return legacy }
        let current = path(for: date)
        if FileManager.default.fileExists(atPath: current) { return current }
        return nil
    }

    /// The day's file in its actual location, existing or not-yet-created.
    public func resolvedPath(for date: String) -> String {
        existingPath(for: date) ?? path(for: date)
    }

    public func exists(date: String) -> Bool {
        existingPath(for: date) != nil
    }

    public func read(date: String) -> String? {
        guard let filePath = existingPath(for: date),
              let data = FileManager.default.contents(atPath: filePath) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Create the day's file with frontmatter when missing (shift/hours
    /// pre-filled from the plan); existing files are never touched.
    /// Returns the file path.
    @discardableResult
    public func ensureFile(date: String, shift: PlannedShift?, shiftType: String?) throws -> String {
        if let existing = existingPath(for: date) { return existing }
        let filePath = path(for: date)
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

    /// One search match: the day plus the first matching line as a snippet.
    public struct SearchHit: Equatable, Identifiable {
        public var id: String { date }
        public let date: String
        public let snippet: String
    }

    // MARK: Quick notes — standalone `dd-mm-yy | title.md` files next to
    // the daily logs. The date names when the note was taken; the title is
    // the note. Never confused with daily logs (the " | " marks a note).

    public struct NoteRef: Equatable, Identifiable {
        public var id: String { path }
        public let date: String
        public let title: String
        public let path: String

        public init(date: String, title: String, path: String) {
            self.date = date
            self.title = title
            self.path = path
        }
    }

    /// "2026-07-19" + "买工作鞋" → "19-07-26 | 买工作鞋.md" (filesystem-unsafe
    /// characters in the title become "-").
    public static func noteFileName(date: String, title: String) -> String {
        let safe = title
            .components(separatedBy: CharacterSet(charactersIn: "/:\\"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
        return "\(fileName(for: date).dropLast(3)) | \(safe).md"
    }

    /// Create a quick note (frontmatter + optional body) and return its
    /// path; an existing note of the same day + title is returned
    /// untouched.
    @discardableResult
    public func createNote(title: String, date: String, body: String = "") throws -> String {
        let path = "\(rootDir)/\(Self.noteFileName(date: date, title: title))"
        guard !FileManager.default.fileExists(atPath: path) else { return path }
        try FileManager.default.createDirectory(atPath: rootDir, withIntermediateDirectories: true)
        var content = "---\ndate: \(date)\ntags: []\n---\n\n"
        if !body.isEmpty {
            content += body.hasSuffix("\n") ? body : body + "\n"
        }
        try Data(content.utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
        return path
    }

    /// Quick notes whose title or content matches, newest first.
    public func searchNotes(query: String) -> [NoteRef] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        return notes().filter { note in
            if note.title.localizedCaseInsensitiveContains(needle) { return true }
            guard let data = FileManager.default.contents(atPath: note.path),
                  let content = String(data: data, encoding: .utf8) else { return false }
            return content.localizedCaseInsensitiveContains(needle)
        }
    }

    /// All quick notes, newest date first (title as tiebreaker).
    public func notes() -> [NoteRef] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: rootDir) else {
            return []
        }
        return names.compactMap { name -> NoteRef? in
            guard name.hasSuffix(".md") else { return nil }
            let stem = String(name.dropLast(3))
            guard let sep = stem.range(of: " | "),
                  let date = Self.date(fromFileName: String(stem[..<sep.lowerBound]) + ".md") else {
                return nil
            }
            return NoteRef(
                date: date,
                title: String(stem[sep.upperBound...]),
                path: "\(rootDir)/\(name)"
            )
        }
        .sorted { ($0.date, $0.title) > ($1.date, $1.title) }
    }

    /// Every day (YYYY-MM-DD) with a log file, across both layouts.
    public func allDates() -> Set<String> {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: rootDir) else { return [] }
        var dates = Set<String>()
        for name in names.sorted() {
            if let date = Self.date(fromFileName: name) {
                dates.insert(date)
            } else if name.count == 4, Int(name) != nil,
                      let inYear = try? fm.contentsOfDirectory(atPath: "\(rootDir)/\(name)") {
                for file in inYear where file.hasSuffix(".md") {
                    dates.insert(String(file.dropLast(3)))
                }
            }
        }
        return dates
    }

    /// Case-insensitive full-text search over frontmatter and body,
    /// optionally bounded to [from, to] (YYYY-MM-DD). A plain directory
    /// scan: thousands of small Markdown files stay well under a second.
    public func search(query: String, from: String? = nil, to: String? = nil) -> [SearchHit] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }

        var hits: [SearchHit] = []
        for date in allDates().sorted() {
            if let from, date < from { continue }
            if let to, date > to { continue }
            guard let content = read(date: date),
                  content.localizedCaseInsensitiveContains(needle) else { continue }
            let line = content
                .components(separatedBy: "\n")
                .first { $0.localizedCaseInsensitiveContains(needle) } ?? ""
            hits.append(SearchHit(
                date: date,
                snippet: String(line.trimmingCharacters(in: .whitespaces).prefix(120))
            ))
        }
        return hits.sorted { $0.date > $1.date }
    }

    /// Days (YYYY-MM-DD) with a log file in a month ("YYYY-MM").
    public func datesWithLogs(inMonth month: String) -> Set<String> {
        allDates().filter { $0.hasPrefix(month) }
    }
}
