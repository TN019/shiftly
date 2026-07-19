import EventKit
import Foundation
import ShiftlyKit

// shiftly — the AI/scripting entry point. Every command prints JSON to
// stdout (a `--json` flag is accepted for compatibility but JSON is always
// on); errors go to stderr as {"error": ...} with a non-zero exit code.
// Root resolution matches the app: SHIFTLY_ROOT (and legacy names) →
// remembered folder → executable walk-up.

// MARK: - Output helpers

func emit(_ object: Any) {
    let data = (try? JSONSerialization.data(
        withJSONObject: object, options: [.prettyPrinted, .sortedKeys]
    )) ?? Data("{}".utf8)
    print(String(data: data, encoding: .utf8) ?? "{}")
}

func fail(_ message: String, code: Int32 = 1) -> Never {
    let data = (try? JSONSerialization.data(withJSONObject: ["error": message])) ?? Data()
    FileHandle.standardError.write(data)
    FileHandle.standardError.write(Data("\n".utf8))
    exit(code)
}

// MARK: - Argument helpers

struct Args {
    private var options: [String: String] = [:]
    private var flags: Set<String> = []
    var positional: [String] = []

    init(_ raw: [String]) {
        var index = 0
        while index < raw.count {
            let word = raw[index]
            if word.hasPrefix("--") {
                let key = String(word.dropFirst(2))
                if index + 1 < raw.count, !raw[index + 1].hasPrefix("--") {
                    options[key] = raw[index + 1]
                    index += 2
                } else {
                    flags.insert(key)
                    index += 1
                }
            } else {
                positional.append(word)
                index += 1
            }
        }
    }

    func value(_ key: String) -> String? { options[key] }

    func require(_ key: String) -> String {
        guard let value = options[key] else {
            fail("missing --\(key)", code: 2)
        }
        return value
    }

    func date(_ key: String) -> String {
        let value = require(key)
        guard value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else {
            fail("--\(key) must be YYYY-MM-DD, got \(value)", code: 2)
        }
        return value
    }
}

func todayYMD() -> String {
    let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
    return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
}

func shiftJSON(_ shift: PlannedShift) -> [String: Any] {
    [
        "date": shift.date,
        "kind": shift.kind.rawValue,
        "start": SyncFingerprint.hhmmString(for: shift.start),
        "end": SyncFingerprint.hhmmString(for: shift.end),
        "hours": (shift.end.timeIntervalSince(shift.start) / 3600 * 100).rounded() / 100,
    ]
}

// MARK: - Environment

let paths = ShiftlyPaths.shared
guard paths.isValid else {
    fail("no data root: set SHIFTLY_ROOT or run the Shiftly app once to choose a folder", code: 2)
}
let store = DataStore(paths: paths)
let dataSource = SyncDataSource(store: store, provider: PlannerScriptProvider(root: paths.root))

func logStore() -> WorkLogStore {
    let dir = (try? store.loadConfig())?.log_dir ?? WorkLogStore.defaultDir
    return WorkLogStore(rootDir: dir)
}

// MARK: - Commands

let arguments = Array(CommandLine.arguments.dropFirst()).filter { $0 != "--json" }
guard let command = arguments.first else {
    fail("usage: shiftly <schedule|swap|leave|holiday|shifts|pay|log|report|routine|sync> …", code: 2)
}
let sub = arguments.count > 1 && !arguments[1].hasPrefix("--") ? arguments[1] : ""
let args = Args(Array(arguments.dropFirst(sub.isEmpty ? 1 : 2)))

func run() throws {
switch (command, sub) {

case ("schedule", "show"):
    let config = try store.loadConfig()
    emit([
        "default_start_time": config.default_start_time,
        "default_end_time": config.default_end_time,
        "rules": config.rules.map { rule in
            var dict: [String: Any] = ["effective_from": rule.effective_from, "workdays": rule.workdays]
            if let type = rule.shift_type { dict["shift_type"] = type }
            return dict
        },
        "shift_types": (config.shift_types ?? []).map {
            ["id": $0.id, "label": $0.label, "start": $0.start, "end": $0.end]
        },
    ])

case ("schedule", "set"):
    let workdays = args.require("workdays").split(separator: ",").map(String.init)
    let valid = Set(["MO", "TU", "WE", "TH", "FR", "SA", "SU"])
    guard !workdays.isEmpty, workdays.allSatisfy({ valid.contains($0) }) else {
        fail("--workdays must be a comma list of MO,TU,WE,TH,FR,SA,SU", code: 2)
    }
    let config = try store.loadConfig()
    let rules = try store.saveSchedule(
        startTime: args.value("start") ?? config.default_start_time,
        endTime: args.value("end") ?? config.default_end_time,
        effectiveFrom: args.date("from"),
        workdays: workdays,
        shiftType: args.value("shift-type")
    )
    emit(["rules": rules.map { ["effective_from": $0.effective_from, "workdays": $0.workdays, "shift_type": $0.shift_type ?? "default"] }])

case ("swap", "add"):
    var swaps = (try? store.loadSwaps()) ?? []
    swaps.append(SwapItem(from_date: args.date("from"), to_date: args.date("to")))
    try store.saveSwaps(swaps)
    emit(["swaps": swaps.map { ["from_date": $0.from_date, "to_date": $0.to_date] }])

case ("swap", "list"):
    let swaps = (try? store.loadSwaps()) ?? []
    emit(["swaps": swaps.enumerated().map { ["index": $0.offset, "from_date": $0.element.from_date, "to_date": $0.element.to_date] }])

case ("swap", "remove"):
    guard let indexText = args.positional.first ?? args.value("index"), let index = Int(indexText) else {
        fail("usage: shiftly swap remove <index>", code: 2)
    }
    var swaps = (try? store.loadSwaps()) ?? []
    guard swaps.indices.contains(index) else {
        fail("index \(index) out of range (0..\(swaps.count - 1))", code: 2)
    }
    swaps.remove(at: index)
    try store.saveSwaps(swaps)
    emit(["swaps": swaps.map { ["from_date": $0.from_date, "to_date": $0.to_date] }])

case ("leave", "add"):
    var leaves = (try? store.loadLeaves()) ?? []
    leaves.append(LeaveItem(start_date: args.date("start"), end_date: args.date("end")))
    try store.saveLeaves(leaves)
    emit(["leave": leaves.map { ["start_date": $0.start_date, "end_date": $0.end_date] }])

case ("leave", "list"):
    let leaves = (try? store.loadLeaves()) ?? []
    emit(["leave": leaves.enumerated().map { ["index": $0.offset, "start_date": $0.element.start_date, "end_date": $0.element.end_date] }])

case ("leave", "remove"):
    guard let indexText = args.positional.first ?? args.value("index"), let index = Int(indexText) else {
        fail("usage: shiftly leave remove <index>", code: 2)
    }
    var leaves = (try? store.loadLeaves()) ?? []
    guard leaves.indices.contains(index) else {
        fail("index \(index) out of range (0..\(leaves.count - 1))", code: 2)
    }
    leaves.remove(at: index)
    try store.saveLeaves(leaves)
    emit(["leave": leaves.map { ["start_date": $0.start_date, "end_date": $0.end_date] }])

case ("holiday", "add"):
    var start = args.date("start")
    var end = args.value("end") != nil ? args.date("end") : start
    if end < start { swap(&start, &end) }
    var holidays = store.loadHolidays()
    guard !holidays.contains(where: { $0.start_date == start && $0.end_date == end }) else {
        fail("holiday \(start)..\(end) already exists", code: 2)
    }
    holidays.append(HolidayItem(start_date: start, end_date: end, name: args.value("name") ?? ""))
    try store.saveHolidays(holidays)
    emit(["holidays": store.loadHolidays().map { ["start_date": $0.start_date, "end_date": $0.end_date, "name": $0.name] }])

case ("holiday", "list"):
    emit(["holidays": store.loadHolidays().enumerated().map {
        ["index": $0.offset, "start_date": $0.element.start_date, "end_date": $0.element.end_date, "name": $0.element.name]
    }])

case ("holiday", "remove"):
    guard let indexText = args.positional.first ?? args.value("index"), let index = Int(indexText) else {
        fail("usage: shiftly holiday remove <index>", code: 2)
    }
    var holidays = store.loadHolidays()
    guard holidays.indices.contains(index) else {
        fail("index \(index) out of range (0..\(holidays.count - 1))", code: 2)
    }
    holidays.remove(at: index)
    try store.saveHolidays(holidays)
    emit(["holidays": holidays.map { ["start_date": $0.start_date, "end_date": $0.end_date, "name": $0.name] }])

case ("shifts", "list"):
    let shifts = try dataSource.plannedShifts(start: args.date("from"), end: args.date("to"))
    emit(["shifts": shifts.map(shiftJSON)])

case ("pay", "report"):
    guard let config = store.loadPayConfig() else {
        fail("pay not configured: create data/pay.json in the app's Pay section first", code: 2)
    }
    let month = args.require("month")
    guard month.range(of: #"^\d{4}-\d{2}$"#, options: .regularExpression) != nil else {
        fail("--month must be YYYY-MM", code: 2)
    }
    let parts = month.split(separator: "-").compactMap { Int($0) }
    var comps = DateComponents()
    comps.year = parts[0]
    comps.month = parts[1]
    let cal = Calendar.current
    guard let monthStart = cal.date(from: comps),
          let dayCount = cal.range(of: .day, in: .month, for: monthStart)?.count else {
        fail("invalid month \(month)", code: 2)
    }
    let shifts = try dataSource.plannedShifts(
        start: "\(month)-01",
        end: String(format: "%@-%02d", month, dayCount)
    )
    let breakdown = PayEngine.breakdown(shifts: shifts, config: config)
    emit([
        "month": month,
        "currency": config.base_currency,
        "total_hours": (breakdown.totalHours * 100).rounded() / 100,
        "total_amount": (breakdown.totalAmount * 100).rounded() / 100,
        "has_unrated_shifts": breakdown.hasUnratedShifts,
        "items": breakdown.items.map { item in
            [
                "date": item.date,
                "hours": (item.hours * 100).rounded() / 100,
                "hourly_rate": item.hourlyRate as Any,
                "amount": (item.amount * 100).rounded() / 100,
            ]
        },
    ])

case ("log", "append"):
    guard let text = args.positional.first, !text.isEmpty else {
        fail("usage: shiftly log append \"text\" [--date YYYY-MM-DD]", code: 2)
    }
    let date = args.value("date") ?? todayYMD()
    let planned = (try? dataSource.plannedShifts(start: date, end: date)) ?? []
    let days = (try? PlannerScriptProvider(root: paths.root).plannedDays(start: date, end: date)) ?? []
    try logStore().append(
        entry: text,
        date: date,
        timeHHMM: SyncFingerprint.hhmmString(for: Date()),
        shift: planned.first,
        shiftType: days.first?.shiftType
    )
    emit(["date": date, "path": logStore().resolvedPath(for: date)])

case ("log", "show"):
    let date = args.value("date") ?? todayYMD()
    guard let content = logStore().read(date: date) else {
        fail("no log for \(date)", code: 3)
    }
    emit(["date": date, "content": content])

case ("log", "path"):
    let date = args.value("date") ?? todayYMD()
    emit(["date": date, "path": logStore().resolvedPath(for: date), "exists": logStore().exists(date: date)])

case ("report", "hours"):
    let period = args.value("period") ?? "week"
    let cal = Calendar.current
    let now = Date()
    let interval: DateInterval
    switch period {
    case "week":
        guard let week = cal.dateInterval(of: .weekOfYear, for: now) else { fail("no week interval") }
        interval = week
    case "month":
        guard let month = cal.dateInterval(of: .month, for: now) else { fail("no month interval") }
        interval = month
    default:
        fail("--period must be week or month", code: 2)
    }
    let df = DateFormatter()
    df.dateFormat = "yyyy-MM-dd"
    let start = df.string(from: interval.start)
    let end = df.string(from: interval.end.addingTimeInterval(-1))
    let shifts = try dataSource.plannedShifts(start: start, end: end)
    let totalHours = shifts.reduce(0.0) { $0 + $1.end.timeIntervalSince($1.start) / 3600 }
    emit([
        "period": period,
        "from": start,
        "to": end,
        "shift_count": shifts.count,
        "total_hours": (totalHours * 100).rounded() / 100,
        "shifts": shifts.map(shiftJSON),
    ])

case ("routine", "show"):
    let steps = store.loadRoutine()
    emit(["routine": steps.map { step -> [String: Any] in
        var dict: [String: Any] = ["kind": step.kind, "value": step.value, "enabled": step.enabled]
        if let args = step.args { dict["args"] = args }
        return dict
    }])

case ("routine", "run"):
    let steps = store.loadRoutine().filter(\.enabled)
    guard !steps.isEmpty else {
        fail("routine is empty — add steps in the app's Settings or data/routine.json", code: 2)
    }
    let runner = RoutineRunner()
    var results: [[String: Any]] = []
    for step in steps {
        switch step.kind {
        case "log":
            let date = todayYMD()
            let planned = (try? dataSource.plannedShifts(start: date, end: date)) ?? []
            let days = (try? PlannerScriptProvider(root: paths.root).plannedDays(start: date, end: date)) ?? []
            do {
                try logStore().append(
                    entry: step.value.isEmpty ? "Started work" : step.value,
                    date: date,
                    timeHHMM: SyncFingerprint.hhmmString(for: Date()),
                    shift: planned.first,
                    shiftType: days.first?.shiftType
                )
                results.append(["kind": "log", "value": step.value, "success": true])
            } catch {
                results.append(["kind": "log", "value": step.value, "success": false,
                                "message": String(describing: error)])
            }
        case "sync":
            // Calendar sync needs EventKit consent; keep it a separate,
            // explicit command in CLI context.
            results.append(["kind": "sync", "value": "", "success": false,
                            "message": "run `shiftly sync now` separately (needs calendar access)"])
        default:
            let result = runner.runStep(step)
            var dict: [String: Any] = ["kind": step.kind, "value": step.value, "success": result.success]
            if let message = result.message { dict["message"] = message }
            results.append(dict)
        }
    }
    emit(["results": results])

case ("sync", "now"):
    if let window = args.value("window") {
        guard ["month", "next_month"].contains(window) else {
            fail("--window must be month or next_month", code: 2)
        }
        if window == "next_month" {
            setenv("SHIFTLY_SYNC_MODE", "next_month", 1)
        }
    }
    let semaphore = DispatchSemaphore(value: 0)
    var exitCode: Int32 = 1
    Task {
        let ekStore = EKEventStore()
        guard await CalendarAccess.request(using: ekStore) else {
            try? store.saveMeta(Meta(
                last_sync_at: ISO8601DateFormatter().string(from: Date()),
                last_sync_status: "error",
                last_sync_error: "calendar access denied"
            ))
            FileHandle.standardError.write(Data(#"{"error": "calendar access denied: grant access via the app first"}"# .utf8 + [0x0a]))
            exitCode = 3
            semaphore.signal()
            return
        }
        do {
            let config = try store.loadConfig()
            let stateStore = SyncStateStore(paths: paths)
            let calendar = try EKCalendarStore.locateOrCreateCalendar(
                named: config.calendar_name, in: ekStore,
                preferredID: stateStore.load().calendar_id
            )
            let coordinator = SyncCoordinator(
                store: store,
                stateStore: stateStore,
                calendar: EKCalendarStore(eventStore: ekStore, calendar: calendar),
                provider: PlannerScriptProvider(root: paths.root),
                calendarIdentifier: calendar.calendarIdentifier
            )
            let outcome = try coordinator.sync()
            emit([
                "created": outcome.created,
                "updated": outcome.updated,
                "deleted": outcome.deleted,
                "readbacks": outcome.readbacks.count,
                "converged": outcome.converged,
            ])
            exitCode = 0
        } catch {
            FileHandle.standardError.write(
                (try? JSONSerialization.data(withJSONObject: ["error": String(describing: error)])) ?? Data()
            )
            FileHandle.standardError.write(Data("\n".utf8))
            exitCode = 1
        }
        semaphore.signal()
    }
    semaphore.wait()
    exit(exitCode)

default:
    fail("unknown command: \(command) \(sub) — see docs/DATA_AND_API.md §3", code: 2)
}
}

do {
    try run()
} catch {
    fail(String(describing: error))
}
