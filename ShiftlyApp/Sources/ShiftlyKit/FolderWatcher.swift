import CoreServices
import Foundation

/// Recursive folder watcher over FSEvents with built-in coalescing.
/// Change callbacks arrive on the main queue with the affected paths.
public final class FolderWatcher {
    private let paths: [String]
    private let latency: TimeInterval
    private let onChange: ([String]) -> Void
    private var stream: FSEventStreamRef?

    public init(
        paths: [String],
        latency: TimeInterval = 0.5,
        onChange: @escaping ([String]) -> Void
    ) {
        self.paths = paths.map { ($0 as NSString).expandingTildeInPath }
        self.latency = latency
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    public func start() {
        guard stream == nil else { return }
        let existing = paths.filter { FileManager.default.fileExists(atPath: $0) }
        guard !existing.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, count, eventPaths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            guard let raw = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }
            watcher.onChange(Array(raw.prefix(count)))
        }

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            existing as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents
            )
        ) else {
            return
        }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    public func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
