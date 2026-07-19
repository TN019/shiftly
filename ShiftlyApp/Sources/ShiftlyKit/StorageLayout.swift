import Foundation

/// The standard storage layout provisioned under the folder a user picks:
///
///     <selected>/
///     ├── app/
///     │   ├── data/       ← Shiftly's data root (ShiftlyPaths.root = <selected>/app)
///     │   └── meetings/
///     ├── logs/
///     └── notes/
///
/// Every location stays individually relocatable afterwards — a location
/// change *moves* the existing content (nothing is left behind).
public enum StorageLayout {
    /// Provision the layout and return the data root (`<selected>/app`).
    /// A folder that already is a data root (its `data/config.json`
    /// exists) is adopted as-is, so legacy setups keep working.
    @discardableResult
    public static func provision(selectedPath: String) throws -> String {
        let fm = FileManager.default
        let selected = (selectedPath as NSString).expandingTildeInPath
        if fm.fileExists(atPath: selected + "/data/config.json") {
            return selected
        }
        let appRoot = selected + "/app"
        for dir in [
            appRoot + "/data",
            appRoot + "/meetings",
            selected + "/logs",
            selected + "/notes",
        ] {
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        try ShiftlyPaths.bootstrapDataDirectory(atRoot: appRoot)
        var raw = try ConfigLogic.readRawConfig(atPath: appRoot + "/data/config.json")
        if raw["log_dir"] == nil { raw["log_dir"] = selected + "/logs" }
        if raw["notes_dir"] == nil { raw["notes_dir"] = selected + "/notes" }
        if raw["meetings_dir"] == nil { raw["meetings_dir"] = appRoot + "/meetings" }
        try ConfigLogic.writeRawConfig(raw, toPath: appRoot + "/data/config.json")
        return appRoot
    }

    /// Move everything inside `source` into `destination` (created on
    /// demand) and remove the emptied source folder. Refuses to move a
    /// folder into itself and refuses when any item would collide at the
    /// destination — nothing is ever overwritten, and a collision aborts
    /// before anything moved.
    public static func moveContents(of source: String, to destination: String) throws {
        let fm = FileManager.default
        let src = (source as NSString).expandingTildeInPath
        let dst = (destination as NSString).expandingTildeInPath
        guard src != dst else { return }
        guard !dst.hasPrefix(src + "/") else {
            throw SyncFailure("cannot move \(src) into itself")
        }
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: src, isDirectory: &isDir), isDir.boolValue else {
            try fm.createDirectory(atPath: dst, withIntermediateDirectories: true)
            return
        }
        try fm.createDirectory(atPath: dst, withIntermediateDirectories: true)
        let names = try fm.contentsOfDirectory(atPath: src).filter { $0 != ".DS_Store" }
        if let clash = names.first(where: { fm.fileExists(atPath: "\(dst)/\($0)") }) {
            throw SyncFailure("\"\(clash)\" already exists at the destination")
        }
        for name in names {
            try fm.moveItem(atPath: "\(src)/\(name)", toPath: "\(dst)/\(name)")
        }
        try? fm.removeItem(atPath: src)
    }
}
