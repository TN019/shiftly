import Foundation

/// Summary of one full sync run, for meta.json and the report UI.
public struct SyncOutcome: Equatable {
    public var created = 0
    public var updated = 0
    public var deleted = 0
    public var readbacks: [ReadbackChange] = []
    public var ignoredForeignTitles: [String] = []
    public var converged = true

    public init() {}
}

public struct SyncFailure: Error, CustomStringConvertible {
    public let description: String

    public init(_ description: String) {
        self.description = description
    }
}

/// Orchestrates a full bidirectional sync (design §3 five steps):
/// plan → execute writes → apply readbacks to data files → re-plan →
/// second pass (must converge) → persist sync_state.json and meta.json.
public final class SyncCoordinator {
    private let store: DataStore
    private let stateStore: SyncStateStore
    private let calendar: CalendarStore
    private let provider: ScheduleProvider
    private let dataSource: SyncDataSource
    private let applier: ReadbackApplier
    /// Identifier of the calendar being synced into; persisted in
    /// sync_state.json so later runs stick to the same calendar even when
    /// several share the configured name.
    private let calendarIdentifier: String?

    public init(
        store: DataStore,
        stateStore: SyncStateStore,
        calendar: CalendarStore,
        provider: ScheduleProvider,
        calendarIdentifier: String? = nil
    ) {
        self.store = store
        self.stateStore = stateStore
        self.calendar = calendar
        self.provider = provider
        self.dataSource = SyncDataSource(store: store, provider: provider)
        self.applier = ReadbackApplier(store: store)
        self.calendarIdentifier = calendarIdentifier
    }

    /// Runs the sync; writes meta.json, last_sync_report.json and the
    /// readback journal with success or error before returning.
    public func sync() throws -> SyncOutcome {
        let stamp = Self.timestamp()
        do {
            let outcome = try run()
            try? writeMeta(status: "success", error: nil)
            try? ReadbackJournal(paths: store.paths).append(outcome.readbacks, at: stamp)
            try? store.saveSyncReport(SyncReportFile(
                at: stamp, status: "success",
                created: outcome.created, updated: outcome.updated, deleted: outcome.deleted,
                readback_count: outcome.readbacks.count,
                ignored_foreign: outcome.ignoredForeignTitles,
                converged: outcome.converged
            ))
            return outcome
        } catch {
            try? writeMeta(status: "error", error: String(describing: error))
            try? store.saveSyncReport(SyncReportFile(
                at: stamp, status: "error", error: String(describing: error)
            ))
            throw error
        }
    }

    private func run() throws -> SyncOutcome {
        let config = try store.loadConfig()
        let (start, end) = try provider.syncRange()
        guard let window = Self.window(start: start, end: end) else {
            throw SyncFailure("invalid sync range \(start)..\(end)")
        }

        var outcome = SyncOutcome()
        let state = stateStore.load()

        // Pass 1
        let plan = SyncEngine.plan(
            planned: try dataSource.plannedShifts(start: start, end: end),
            events: try calendar.events(in: window),
            state: state,
            eventTitle: config.event_title
        )
        var entries = try SyncEngine.execute(plan, on: calendar)
        outcome.created += plan.creates.count
        outcome.updated += plan.updates.count
        outcome.deleted += plan.deletes.count
        outcome.readbacks = plan.readbacks
        outcome.ignoredForeignTitles = plan.ignoredForeign.map(\.title)

        // Readbacks change the data files; re-plan and reconcile once more.
        if !plan.readbacks.isEmpty {
            try applier.apply(plan.readbacks)
            let secondPlan = SyncEngine.plan(
                planned: try dataSource.plannedShifts(start: start, end: end),
                events: try calendar.events(in: window),
                state: SyncStateFile(entries: entries),
                eventTitle: config.event_title
            )
            entries = try SyncEngine.execute(secondPlan, on: calendar)
            outcome.created += secondPlan.creates.count
            outcome.updated += secondPlan.updates.count
            outcome.deleted += secondPlan.deletes.count
            outcome.converged = secondPlan.readbacks.isEmpty
        }

        var newState = stateStore.load()
        newState.entries = entries
        newState.last_sync_at = Self.timestamp()
        newState.calendar_id = calendarIdentifier ?? newState.calendar_id
        try stateStore.save(newState)
        return outcome
    }

    private func writeMeta(status: String, error: String?) throws {
        try store.saveMeta(Meta(
            last_sync_at: Self.timestamp(),
            last_sync_status: status,
            last_sync_error: error
        ))
    }

    static func window(start: String, end: String) -> DateInterval? {
        guard let s = ShiftTimeBuilder.makeShift(
            date: start, kind: .auto, title: "w", startHHMM: "00:00", endHHMM: "23:59"
        ), let e = ShiftTimeBuilder.makeShift(
            date: end, kind: .auto, title: "w", startHHMM: "00:00", endHHMM: "23:59"
        ), s.start <= e.end else {
            return nil
        }
        return DateInterval(start: s.start, end: e.end)
    }

    private static func timestamp() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = .current
        return f.string(from: Date())
    }
}
