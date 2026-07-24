import Foundation

/// Destination logic for the one-click Scripto install (Settings →
/// Meetings). The clone itself is driven by the app; this is the pure,
/// testable part.
public enum ScriptoInstall {
    public static let repoURL = "https://github.com/TN019/scripto.git"

    /// Picks the clone destination. When `startPath` (normally the app
    /// bundle) sits inside a Shiftly git checkout — running dist/Shiftly.app
    /// straight from the repo — the clone lands next to that checkout
    /// (`../scripto`, the conventional dev layout). Everywhere else it goes
    /// under `~/Library/Application Support/Shiftly/scripto`, which survives
    /// the app being moved and never lives on an iCloud-synced folder.
    public static func targetDirectory(
        near startPath: String, fileManager fm: FileManager = .default
    ) -> String {
        var dir = URL(fileURLWithPath: (startPath as NSString).expandingTildeInPath)
            .standardizedFileURL
        while dir.pathComponents.count > 1 {
            if fm.fileExists(atPath: dir.appendingPathComponent(".git").path),
               fm.fileExists(atPath: dir.appendingPathComponent("ShiftlyApp/Package.swift").path) {
                return dir.deletingLastPathComponent().appendingPathComponent("scripto").path
            }
            dir.deleteLastPathComponent()
        }
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return appSupport.appendingPathComponent("Shiftly/scripto").path
    }

    /// True when `path` already looks like a usable Scripto checkout
    /// (same test the transcribe action uses).
    public static func looksLikeCheckout(
        _ path: String, fileManager fm: FileManager = .default
    ) -> Bool {
        fm.fileExists(atPath: (path as NSString).expandingTildeInPath + "/pyproject.toml")
    }
}
