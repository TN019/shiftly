import Foundation
import Testing
@testable import ShiftlyKit

@Suite struct FolderWatcherTests {
    @Test func firesOnExternalWriteWithAffectedPath() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shiftly_watch_\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let semaphore = DispatchSemaphore(value: 0)
        let box = PathBox()
        let watcher = FolderWatcher(paths: [dir], latency: 0.2) { changed in
            box.append(changed)
            semaphore.signal()
        }
        watcher.start()
        defer { watcher.stop() }

        // Give FSEvents a beat to become active, then write.
        Thread.sleep(forTimeInterval: 0.3)
        try Data("[]".utf8).write(to: URL(fileURLWithPath: dir + "/swaps.json"))

        // Early callbacks may only carry directory-creation events; keep
        // draining until the file path shows up.
        let deadline = Date().addingTimeInterval(5)
        while !box.paths.contains(where: { $0.contains("swaps.json") }) && Date() < deadline {
            _ = semaphore.wait(timeout: .now() + 0.5)
        }
        #expect(box.paths.contains { $0.contains("swaps.json") })
    }

    @Test func firesForSubdirectoryFiles() throws {
        // Log layout is <root>/YYYY/YYYY-MM-DD.md; recursion must cover it.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shiftly_watch_\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: dir + "/2026", withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let semaphore = DispatchSemaphore(value: 0)
        let watcher = FolderWatcher(paths: [dir], latency: 0.2) { _ in
            semaphore.signal()
        }
        watcher.start()
        defer { watcher.stop() }

        Thread.sleep(forTimeInterval: 0.3)
        try Data("note".utf8).write(to: URL(fileURLWithPath: dir + "/2026/2026-07-17.md"))

        #expect(semaphore.wait(timeout: .now() + 5) == .success, "recursive event fired")
    }

    @Test func missingPathsAreSkippedSafely() {
        let watcher = FolderWatcher(paths: ["/nonexistent/\(UUID().uuidString)"]) { _ in }
        watcher.start() // must not crash
        watcher.stop()
        watcher.stop() // double stop safe
        #expect(Bool(true))
    }
}

/// Callback runs on the main queue; tests wait on a semaphore from the test
/// thread, so collect into a lock-guarded box.
private final class PathBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var paths: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ new: [String]) {
        lock.lock()
        storage.append(contentsOf: new)
        lock.unlock()
    }
}
