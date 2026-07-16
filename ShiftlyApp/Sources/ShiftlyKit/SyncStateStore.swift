import Foundation

/// Persistence for data/sync_state.json.
///
/// Missing file → empty state (first run). Corrupt file → moved aside to
/// `sync_state.json.corrupt` and treated as empty; the engine then recovers
/// by re-claiming existing events instead of duplicating them.
public struct SyncStateStore {
    public let path: String

    public init(path: String) {
        self.path = path
    }

    public init(paths: ShiftlyPaths = .shared) {
        self.init(path: "\(paths.root)/data/sync_state.json")
    }

    public func load() -> SyncStateFile {
        guard let data = FileManager.default.contents(atPath: path) else {
            return .empty
        }
        do {
            return try JSONDecoder().decode(SyncStateFile.self, from: data)
        } catch {
            try? FileManager.default.removeItem(atPath: path + ".corrupt")
            try? FileManager.default.moveItem(atPath: path, toPath: path + ".corrupt")
            return .empty
        }
    }

    public func save(_ state: SyncStateFile) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(state)
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}
