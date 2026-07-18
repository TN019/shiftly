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
        "overrides.json",
        "manual_shifts.json",
        "pay.json",
        "routine.json",
        "meta.json",
        "sync_state.json",
        "last_sync_report.json",
        "readback_log.json",
    ]

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
