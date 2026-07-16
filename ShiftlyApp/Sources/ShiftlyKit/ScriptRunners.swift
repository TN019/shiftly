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

/// Runs `scripts/sync.applescript` via osascript.
/// Blocking — call off the main thread.
public enum SyncScriptRunner {
    public static func run(root: String, scriptPath: String) -> (ok: Bool, err: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = [scriptPath]
        var env = ProcessInfo.processInfo.environment
        ShiftlyPaths.applyRepoRootEnvironment(&env, root: root)
        proc.environment = env
        let pipe = Pipe()
        proc.standardError = pipe
        do {
            try proc.run()
            proc.waitUntilExit()
            if proc.terminationStatus == 0 {
                return (true, "")
            }
            let msg = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "sync error"
            return (false, msg)
        } catch {
            return (false, error.localizedDescription)
        }
    }
}
