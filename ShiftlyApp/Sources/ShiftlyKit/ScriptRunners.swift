import Foundation

/// Runs `scripts/work_history.py` and decodes its JSON output.
/// Blocking — call off the main thread.
public enum WorkHistoryScriptRunner {
    public static func run(root: String, scriptPath: String) -> (rows: [WorkHistoryRow], note: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        proc.arguments = [scriptPath]
        var env = ProcessInfo.processInfo.environment
        ShiftlyPaths.applyRepoRootEnvironment(&env, root: root)
        proc.environment = env
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        do {
            try proc.run()
            proc.waitUntilExit()
            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            let errText = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            if proc.terminationStatus != 0 {
                return ([], errText.isEmpty ? "work_history.py failed." : errText.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            let rows = try JSONDecoder().decode([WorkHistoryRow].self, from: outData)
            return (rows, "")
        } catch {
            return ([], error.localizedDescription)
        }
    }
}

// The osascript-based SyncScriptRunner was removed together with the app's
// AppleScript sync path; the AppleScript menu (scripts/main.applescript)
// still invokes sync.applescript directly for the legacy flow.
