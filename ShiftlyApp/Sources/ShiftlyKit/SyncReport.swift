import Foundation

/// Flat, Codable form of a ReadbackChange, for the journal and report files.
public struct ReadbackRecord: Codable, Equatable, Identifiable {
    public enum Kind: String, Codable {
        case moved, retimed, deleted, newManual
    }

    public var id: UUID
    public var at: String
    public var kind: Kind
    public var date: String
    public var to_date: String?
    public var start: String?
    public var end: String?
    public var undone: Bool

    public init(change: ReadbackChange, at: String, id: UUID = UUID()) {
        self.id = id
        self.at = at
        self.undone = false
        switch change {
        case .moved(let from, let to, _):
            kind = .moved
            date = from
            to_date = to
        case .retimed(let date, _, let start, let end):
            kind = .retimed
            self.date = date
            self.start = start
            self.end = end
        case .deleted(let date):
            kind = .deleted
            self.date = date
        case .newManual(let date, _, let start, let end):
            kind = .newManual
            self.date = date
            self.start = start
            self.end = end
        }
    }
}

/// Summary of the most recent sync run: data/last_sync_report.json.
public struct SyncReportFile: Codable, Equatable {
    public var at: String
    public var status: String
    public var error: String?
    public var created: Int
    public var updated: Int
    public var deleted: Int
    public var readback_count: Int
    public var ignored_foreign: [String]
    public var converged: Bool

    public init(
        at: String, status: String, error: String? = nil,
        created: Int = 0, updated: Int = 0, deleted: Int = 0,
        readback_count: Int = 0, ignored_foreign: [String] = [], converged: Bool = true
    ) {
        self.at = at
        self.status = status
        self.error = error
        self.created = created
        self.updated = updated
        self.deleted = deleted
        self.readback_count = readback_count
        self.ignored_foreign = ignored_foreign
        self.converged = converged
    }
}

/// Append-only log of readback changes with undo flags:
/// data/readback_log.json (engine-owned, capped).
public struct ReadbackJournal {
    public static let cap = 50

    public let path: String

    public init(path: String) {
        self.path = path
    }

    public init(paths: ShiftlyPaths = .shared) {
        self.init(path: "\(paths.root)/data/readback_log.json")
    }

    public func load() -> [ReadbackRecord] {
        guard let data = FileManager.default.contents(atPath: path) else { return [] }
        return (try? JSONDecoder().decode([ReadbackRecord].self, from: data)) ?? []
    }

    public func append(_ changes: [ReadbackChange], at timestamp: String) throws {
        guard !changes.isEmpty else { return }
        var records = load()
        records.append(contentsOf: changes.map { ReadbackRecord(change: $0, at: timestamp) })
        try save(Array(records.suffix(Self.cap)))
    }

    public func markUndone(id: UUID) throws {
        var records = load()
        guard let i = records.firstIndex(where: { $0.id == id }) else { return }
        records[i].undone = true
        try save(records)
    }

    private func save(_ records: [ReadbackRecord]) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(records).write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}

/// Reverts a single readback by removing the data record it created.
/// The caller runs a sync afterwards, which writes the calendar back to the
/// restored plan.
public struct ReadbackUndoService {
    private let store: DataStore
    private let journal: ReadbackJournal

    public init(store: DataStore, journal: ReadbackJournal) {
        self.store = store
        self.journal = journal
    }

    /// Returns false when the record was not found (already gone or edited
    /// out of the data files by hand).
    @discardableResult
    public func undo(_ record: ReadbackRecord) throws -> Bool {
        guard !record.undone else { return false }
        let removed: Bool
        switch record.kind {
        case .moved:
            var swaps = (try? store.loadSwaps()) ?? []
            let match = swaps.lastIndex {
                $0.from_date == record.date && $0.to_date == record.to_date
            }
            removed = match != nil
            if let i = match {
                swaps.remove(at: i)
                try store.saveSwaps(swaps)
            }
        case .retimed:
            var overrides = store.loadOverrides()
            let match = overrides.firstIndex { $0.date == record.date }
            removed = match != nil
            if let i = match {
                overrides.remove(at: i)
                try store.saveOverrides(overrides)
            }
        case .deleted:
            var leaves = (try? store.loadLeaves()) ?? []
            let match = leaves.lastIndex {
                $0.start_date == record.date && $0.end_date == record.date
            }
            removed = match != nil
            if let i = match {
                leaves.remove(at: i)
                try store.saveLeaves(leaves)
            }
        case .newManual:
            var manuals = store.loadManualShifts()
            let match = manuals.firstIndex { $0.date == record.date }
            removed = match != nil
            if let i = match {
                manuals.remove(at: i)
                try store.saveManualShifts(manuals)
            }
        }
        if removed {
            try journal.markUndone(id: record.id)
        }
        return removed
    }
}

extension DataStore {
    public func loadSyncReport() -> SyncReportFile? {
        let path = "\(paths.root)/data/last_sync_report.json"
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? JSONDecoder().decode(SyncReportFile.self, from: data)
    }

    public func saveSyncReport(_ report: SyncReportFile) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(report)
        try data.write(
            to: URL(fileURLWithPath: "\(paths.root)/data/last_sync_report.json"),
            options: .atomic
        )
    }
}
