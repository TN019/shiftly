import Foundation

/// One step of the work routine (data/routine.json).
///
/// Kinds:
/// - "app":     open an application by name; optional launch args
///              (e.g. Ghostty's --working-directory=…)
/// - "url":     open in the default browser (http/https only)
/// - "path":    reveal/open a file or folder
/// - "command": run a shell line via /bin/zsh -lc (user-authored, same
///              trust level as the user's own shell profile)
/// - "sync":    one calendar sync (handled by the app/CLI, not the runner)
/// - "log":     append a timestamped entry to today's work log (ditto)
public struct RoutineStep: Codable, Equatable, Identifiable {
    public var kind: String
    public var value: String
    public var args: [String]?
    /// Unchecked steps stay in the list but are skipped.
    public var enabled: Bool

    public var id: String { "\(kind)|\(value)|\((args ?? []).joined(separator: " "))" }

    public init(kind: String, value: String, args: [String]? = nil, enabled: Bool = true) {
        self.kind = kind
        self.value = value
        self.args = args
        self.enabled = enabled
    }

    private enum CodingKeys: String, CodingKey {
        case kind, value, args, enabled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(String.self, forKey: .kind)
        value = try c.decode(String.self, forKey: .value)
        args = try c.decodeIfPresent([String].self, forKey: .args)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }

    public static let knownKinds = ["app", "url", "path", "command", "sync", "log"]

    /// Steps the RoutineRunner executes itself; "sync" and "log" need the
    /// caller's context (calendar engine, log store).
    public var isRunnerStep: Bool {
        ["app", "url", "path", "command"].contains(kind)
    }
}

public struct RoutineStepResult: Equatable {
    public let step: RoutineStep
    public let success: Bool
    public let message: String?

    public init(step: RoutineStep, success: Bool, message: String? = nil) {
        self.step = step
        self.success = success
        self.message = message
    }
}

extension ShiftlyPaths {
    public var routinePath: String { "\(root)/data/routine.json" }
}

extension DataStore {
    public func loadRoutine() -> [RoutineStep] {
        guard let data = FileManager.default.contents(atPath: paths.routinePath) else { return [] }
        return (try? JSONDecoder().decode([RoutineStep].self, from: data)) ?? []
    }

    public func saveRoutine(_ steps: [RoutineStep]) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(steps).write(
            to: URL(fileURLWithPath: paths.routinePath), options: .atomic
        )
    }
}

/// Executes runner steps in order. One failing step is reported but never
/// blocks the rest. Executors are injectable so sequencing is testable
/// without launching real apps or shells.
public struct RoutineRunner {
    public typealias Executor = (_ arguments: [String]) -> (ok: Bool, error: String?)

    private let openExecutor: Executor
    private let shellExecutor: Executor

    public init(
        openExecutor: @escaping Executor = RoutineRunner.systemOpen,
        shellExecutor: @escaping Executor = RoutineRunner.systemShell
    ) {
        self.openExecutor = openExecutor
        self.shellExecutor = shellExecutor
    }

    /// Runs the enabled steps of the list, skipping disabled ones. "sync"
    /// and "log" are left to the caller; unknown kinds are executed so a
    /// config typo surfaces as a reported failure instead of a silent skip.
    @discardableResult
    public func run(_ steps: [RoutineStep]) -> [RoutineStepResult] {
        steps
            .filter { $0.enabled && !["sync", "log"].contains($0.kind) }
            .map { runStep($0) }
    }

    public func runStep(_ step: RoutineStep) -> RoutineStepResult {
        switch step.kind {
        case "app":
            var list = ["-a", step.value]
            if let args = step.args, !args.isEmpty {
                // -n: fresh instance so launch args (like Ghostty's
                // --working-directory) apply even when already running.
                list.insert("-n", at: 0)
                list.append("--args")
                list.append(contentsOf: args)
            }
            let outcome = openExecutor(list)
            return RoutineStepResult(step: step, success: outcome.ok, message: outcome.error)
        case "url":
            guard step.value.hasPrefix("http://") || step.value.hasPrefix("https://") else {
                return RoutineStepResult(step: step, success: false,
                                         message: "url must start with http(s)://")
            }
            let outcome = openExecutor([step.value])
            return RoutineStepResult(step: step, success: outcome.ok, message: outcome.error)
        case "path":
            let expanded = (step.value as NSString).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: expanded) else {
                return RoutineStepResult(step: step, success: false, message: "path does not exist")
            }
            let outcome = openExecutor([expanded])
            return RoutineStepResult(step: step, success: outcome.ok, message: outcome.error)
        case "command":
            let outcome = shellExecutor([step.value])
            return RoutineStepResult(step: step, success: outcome.ok, message: outcome.error)
        default:
            return RoutineStepResult(step: step, success: false,
                                     message: "unknown kind \(step.kind)")
        }
    }

    // MARK: Production executors

    public static let systemOpen: Executor = { arguments in
        runProcess("/usr/bin/open", arguments)
    }

    public static let systemShell: Executor = { arguments in
        runProcess("/bin/zsh", ["-lc"] + arguments)
    }

    private static func runProcess(_ path: String, _ arguments: [String]) -> (ok: Bool, error: String?) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = arguments
        let errPipe = Pipe()
        proc.standardError = errPipe
        do {
            try proc.run()
            proc.waitUntilExit()
            if proc.terminationStatus == 0 {
                return (true, nil)
            }
            let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (false, (err?.isEmpty == false) ? err : "exit \(proc.terminationStatus)")
        } catch {
            return (false, error.localizedDescription)
        }
    }
}
