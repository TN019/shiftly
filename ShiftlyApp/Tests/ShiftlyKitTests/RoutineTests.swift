import Foundation
import Testing
@testable import ShiftlyKit

private final class CallLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [[String]] = []
    var calls: [[String]] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
    func record(_ args: [String]) {
        lock.lock(); storage.append(args); lock.unlock()
    }
}

@Suite struct RoutineRunnerTests {
    @Test func executesEnabledRunnerStepsInOrder() {
        let opens = CallLog()
        let shells = CallLog()
        let runner = RoutineRunner(
            openExecutor: { args in opens.record(args); return (true, nil) },
            shellExecutor: { args in shells.record(args); return (true, nil) },
            appSearchPaths: []
        )
        let results = runner.run([
            RoutineStep(kind: "app", value: "DingTalk"),
            RoutineStep(kind: "app", value: "WeChat", enabled: false),      // skipped
            RoutineStep(kind: "url", value: "https://mail.example.com"),
            RoutineStep(kind: "sync", value: ""),                            // not a runner step
            RoutineStep(kind: "command", value: "echo hi"),
        ])
        #expect(results.count == 3)
        let allOK = results.allSatisfy { $0.success }
        #expect(allOK)
        #expect(opens.calls == [["-a", "DingTalk"], ["https://mail.example.com"]])
        #expect(shells.calls == [["echo hi"]])
    }

    @Test func appArgsUseFreshInstanceAndArgsSeparator() {
        let opens = CallLog()
        let runner = RoutineRunner(
            openExecutor: { args in opens.record(args); return (true, nil) },
            shellExecutor: { _ in (true, nil) },
            appSearchPaths: []
        )
        _ = runner.runStep(RoutineStep(
            kind: "app", value: "Ghostty", args: ["--working-directory=/Users/me/work"]
        ))
        #expect(opens.calls == [["-n", "-a", "Ghostty", "--args", "--working-directory=/Users/me/work"]])
    }

    @Test func validationFailuresDoNotBlockLaterSteps() {
        let opens = CallLog()
        let runner = RoutineRunner(
            openExecutor: { args in opens.record(args); return (true, nil) },
            shellExecutor: { _ in (true, nil) },
            appSearchPaths: []
        )
        let results = runner.run([
            RoutineStep(kind: "url", value: "ftp://nope"),          // invalid scheme
            RoutineStep(kind: "path", value: "/definitely/missing/xyz"),
            RoutineStep(kind: "mystery", value: "?"),
            RoutineStep(kind: "app", value: "DingTalk"),            // still runs
        ])
        #expect(results.map(\.success) == [false, false, false, true])
        #expect(results[0].message?.contains("http") == true)
        #expect(results[1].message?.contains("path") == true)
        #expect(results[2].message?.contains("unknown kind") == true)
        #expect(opens.calls == [["-a", "DingTalk"]])
    }

    @Test func appNameResolvesAgainstInstalledBundles() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("apps_\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: dir) }
        for app in ["DingTalkLite.app", "WeChat.app", "Anki.app"] {
            try FileManager.default.createDirectory(
                atPath: "\(dir)/\(app)", withIntermediateDirectories: true
            )
        }
        // Exact install: name passes through.
        #expect(RoutineRunner.resolvedAppName("WeChat", searchPaths: [dir]) == "WeChat")
        // Product name vs bundle name: prefix match wins (the user's case).
        #expect(RoutineRunner.resolvedAppName("DingTalk", searchPaths: [dir]) == "DingTalkLite")
        // Case-insensitive contains as a last resort.
        #expect(RoutineRunner.resolvedAppName("talk", searchPaths: [dir]) == "DingTalkLite")
        // No match: unchanged, so `open` reports the honest error.
        #expect(RoutineRunner.resolvedAppName("Slack", searchPaths: [dir]) == "Slack")
        // The runner passes the resolved name to `open -a`.
        let opens = CallLog()
        let runner = RoutineRunner(
            openExecutor: { args in opens.record(args); return (true, nil) },
            shellExecutor: { _ in (true, nil) },
            appSearchPaths: [dir]
        )
        _ = runner.runStep(RoutineStep(kind: "app", value: "DingTalk"))
        #expect(opens.calls == [["-a", "DingTalkLite"]])
    }

    @Test func pathStepExpandsTildeAndOpensExisting() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("routine_\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let opens = CallLog()
        let runner = RoutineRunner(
            openExecutor: { args in opens.record(args); return (true, nil) },
            shellExecutor: { _ in (true, nil) },
            appSearchPaths: []
        )
        let result = runner.runStep(RoutineStep(kind: "path", value: dir))
        #expect(result.success)
        #expect(opens.calls == [[dir]])
    }
}

@Suite struct RoutineStoreTests {
    @Test func roundTripAndLegacyEnabledDefault() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("routine_store_\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: root) }
        try FileManager.default.createDirectory(atPath: root + "/data", withIntermediateDirectories: true)
        let store = DataStore(paths: ShiftlyPaths(root: root))

        #expect(store.loadRoutine().isEmpty, "missing file = empty routine")

        let steps = [
            RoutineStep(kind: "app", value: "DingTalk"),
            RoutineStep(kind: "url", value: "https://x.example", enabled: false),
        ]
        try store.saveRoutine(steps)
        #expect(store.loadRoutine() == steps)

        // Entries without "enabled" (hand-written) default to true.
        try Data(#"[{"kind":"app","value":"WeChat"}]"#.utf8)
            .write(to: URL(fileURLWithPath: root + "/data/routine.json"))
        let loaded = store.loadRoutine()
        #expect(loaded.count == 1)
        #expect(loaded[0].enabled)
    }
}
