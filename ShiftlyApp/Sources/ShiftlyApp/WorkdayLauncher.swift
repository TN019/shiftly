import Foundation

/// A LaunchAgent that opens Shiftly at a chosen time on the given workdays
/// (launchd `StartCalendarInterval`, one entry per weekday). Unlike
/// launch-at-login (SMAppService, which is all-or-nothing and tied to
/// login), this fires on a schedule and can target specific days. The
/// agent's day list is regenerated whenever the work schedule changes.
enum WorkdayLauncher {
    static let label = "com.shiftly.workday-launch"

    static var plistPath: String {
        NSHomeDirectory() + "/Library/LaunchAgents/\(label).plist"
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: plistPath)
    }

    /// Shiftly workday codes → launchd weekday numbers (0 = Sunday).
    private static let weekdayNumber: [String: Int] = [
        "SU": 0, "MO": 1, "TU": 2, "WE": 3, "TH": 4, "FR": 5, "SA": 6,
    ]

    /// Write and (re)load the agent. `appBundlePath` should be the .app
    /// bundle (Bundle.main.bundlePath); under `swift run` this is not an
    /// app bundle and the scheduled `open` is a no-op, same caveat as
    /// launch-at-login.
    static func install(appBundlePath: String, workdays: [String], hour: Int, minute: Int) {
        let entries = workdays
            .compactMap { weekdayNumber[$0] }
            .sorted()
            .map { day in
                """
                    <dict>
                      <key>Weekday</key><integer>\(day)</integer>
                      <key>Hour</key><integer>\(hour)</integer>
                      <key>Minute</key><integer>\(minute)</integer>
                    </dict>
                """
            }
            .joined(separator: "\n")

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key><string>\(label)</string>
          <key>ProgramArguments</key>
          <array>
            <string>/usr/bin/open</string>
            <string>\(appBundlePath)</string>
          </array>
          <key>StartCalendarInterval</key>
          <array>
        \(entries)
          </array>
        </dict>
        </plist>
        """

        let dir = (plistPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        // Reload cleanly: bootout any previous instance before rewriting.
        runLaunchctl(["bootout", "gui/\(getuid())", plistPath])
        try? Data(plist.utf8).write(to: URL(fileURLWithPath: plistPath), options: .atomic)
        runLaunchctl(["bootstrap", "gui/\(getuid())", plistPath])
    }

    static func uninstall() {
        runLaunchctl(["bootout", "gui/\(getuid())", plistPath])
        try? FileManager.default.removeItem(atPath: plistPath)
    }

    private static func runLaunchctl(_ args: [String]) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        proc.arguments = args
        proc.standardError = Pipe()
        proc.standardOutput = Pipe()
        try? proc.run()
        proc.waitUntilExit()
    }
}
