import Foundation

/// Factory reset of a data root: deletes every file Shiftly owns under
/// `<root>/data`. Known files only — anything else a user placed in the
/// folder stays, and the `data` directory itself is removed only once it
/// is empty. Apple Calendar events and work-log markdown files are never
/// touched (the calendar belongs to the user; logs live outside data/).
public enum DataReset {
    /// Everything Shiftly writes into <root>/data (see DATA_AND_API §1).
    public static let ownedFiles = [
        "config.json",
        "swaps.json",
        "leave.json",
        "holidays.json",
        "overrides.json",
        "manual_shifts.json",
        "pay.json",
        "routine.json",
        "meta.json",
        "sync_state.json",
        "last_sync_report.json",
        "readback_log.json",
    ]

    /// Delete every daily log and quick note Shiftly recognizes (current
    /// dd-mm-yy layout, legacy YYYY/YYYY-MM-DD.md, notes `dd-mm-yy | *.md`).
    /// Foreign files stay; emptied folders are removed.
    public static func wipeLogs(logDir: String, notesDir: String) {
        let fm = FileManager.default
        let logs = (logDir as NSString).expandingTildeInPath
        for name in (try? fm.contentsOfDirectory(atPath: logs)) ?? [] {
            if WorkLogStore.date(fromFileName: name) != nil {
                try? fm.removeItem(atPath: "\(logs)/\(name)")
            } else if name.count == 4, Int(name) != nil {
                let yearDir = "\(logs)/\(name)"
                for file in (try? fm.contentsOfDirectory(atPath: yearDir)) ?? []
                where file.hasSuffix(".md") {
                    try? fm.removeItem(atPath: "\(yearDir)/\(file)")
                }
                removeIfEmpty(yearDir)
            }
        }
        let notes = (notesDir as NSString).expandingTildeInPath
        for name in (try? fm.contentsOfDirectory(atPath: notes)) ?? [] {
            let stem = name.hasSuffix(".md") ? String(name.dropLast(3)) : name
            if let sep = stem.range(of: " | "),
               WorkLogStore.date(fromFileName: String(stem[..<sep.lowerBound]) + ".md") != nil {
                try? fm.removeItem(atPath: "\(notes)/\(name)")
            }
        }
        removeIfEmpty(notes)
        removeIfEmpty(logs)
    }

    /// Delete every meeting folder Shiftly recognizes (recordings and
    /// subtitles included); anything else in the folder stays.
    public static func wipeMeetings(dir: String) {
        let fm = FileManager.default
        let root = (dir as NSString).expandingTildeInPath
        for name in (try? fm.contentsOfDirectory(atPath: root)) ?? []
        where MeetingStore.parseFolderName(name) != nil {
            try? fm.removeItem(atPath: "\(root)/\(name)")
        }
        removeIfEmpty(root)
    }

    private static func removeIfEmpty(_ path: String) {
        let fm = FileManager.default
        if let rest = try? fm.contentsOfDirectory(atPath: path),
           rest.allSatisfy({ $0 == ".DS_Store" }) {
            try? fm.removeItem(atPath: path)
        }
    }

    /// Returns how many files were deleted.
    @discardableResult
    public static func wipeData(atRoot root: String) throws -> Int {
        let fm = FileManager.default
        var removed = 0
        for name in ownedFiles {
            let path = "\(root)/data/\(name)"
            if fm.fileExists(atPath: path) {
                try fm.removeItem(atPath: path)
                removed += 1
            }
        }
        let dir = "\(root)/data"
        if let rest = try? fm.contentsOfDirectory(atPath: dir),
           rest.allSatisfy({ $0 == ".DS_Store" }) {
            try? fm.removeItem(atPath: dir)
        }
        return removed
    }
}
