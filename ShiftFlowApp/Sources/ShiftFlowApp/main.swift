import SwiftUI
import Foundation
import AppKit

private let rootPath = "/Users/tn/Dev/Local/ShiftFlow"
private let configPath = "\(rootPath)/data/config.json"
private let swapsPath = "\(rootPath)/data/swaps.json"
private let leavePath = "\(rootPath)/data/leave.json"
private let syncScriptPath = "\(rootPath)/scripts/sync.applescript"
private let metaPath = "\(rootPath)/data/meta.json"

struct Rule: Codable {
    var effective_from: String
    var workdays: [String]
}

struct Config: Codable {
    var calendar_name: String
    var event_title: String
    var default_start_time: String
    var default_end_time: String
    var history_csv: String?
    var setup_completed: Bool?
    var rules: [Rule]
}

struct SwapItem: Codable, Identifiable {
    var id: UUID { UUID() }
    var from_date: String
    var to_date: String
}

struct LeaveItem: Codable, Identifiable {
    var id: UUID { UUID() }
    var start_date: String
    var end_date: String
}

struct Meta: Codable {
    var last_sync_at: String
    var last_sync_status: String
}

enum SyncState {
    case synced
    case unsynced
    case error(String)
}

@MainActor
final class AppModel: ObservableObject {
    @Published var selectedDays: Set<String> = []
    @Published var startTime = "10:00"
    @Published var endTime = "18:30"
    @Published var effectiveFrom = Date()
    @Published var swapFrom = Date()
    @Published var swapTo = Date()
    @Published var leaveStart = Date()
    @Published var leaveEnd = Date()
    @Published var swaps: [SwapItem] = []
    @Published var leaves: [LeaveItem] = []
    @Published var syncState: SyncState = .unsynced
    @Published var lastSyncText = "-"
    @Published var statusMessage = ""
    @Published var isBusy = false
    @Published var busyMessage = ""

    let dayOrder = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]
    let dayLabels: [String: String] = [
        "MO": "Mon", "TU": "Tue", "WE": "Wed", "TH": "Thu", "FR": "Fri", "SA": "Sat", "SU": "Sun"
    ]

    func load() {
        loadConfig()
        loadSwaps()
        loadLeaves()
        loadMeta()
    }

    func saveSchedule() {
        do {
            var config = try readConfig()
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            config.default_start_time = startTime
            config.default_end_time = endTime
            config.setup_completed = true
            config.rules = [
                Rule(effective_from: df.string(from: effectiveFrom), workdays: dayOrder.filter { selectedDays.contains($0) })
            ]
            try writeJSON(config, to: configPath)
            syncState = .unsynced
            statusMessage = "Schedule saved."
        } catch {
            statusMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    func addSwap() {
        do {
            var list = try readSwaps()
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            list.append(SwapItem(from_date: df.string(from: swapFrom), to_date: df.string(from: swapTo)))
            try writeJSON(list.map { ["from_date": $0.from_date, "to_date": $0.to_date] }, to: swapsPath)
            swaps = list
            syncState = .unsynced
            statusMessage = "Swap added."
        } catch {
            statusMessage = "Add swap failed: \(error.localizedDescription)"
        }
    }

    func addLeave() {
        do {
            var list = try readLeaves()
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            list.append(LeaveItem(start_date: df.string(from: leaveStart), end_date: df.string(from: leaveEnd)))
            try writeJSON(list.map { ["start_date": $0.start_date, "end_date": $0.end_date] }, to: leavePath)
            leaves = list
            syncState = .unsynced
            statusMessage = "Leave added."
        } catch {
            statusMessage = "Add leave failed: \(error.localizedDescription)"
        }
    }

    func deleteSwap(index: Int) {
        guard swaps.indices.contains(index) else { return }
        swaps.remove(at: index)
        do {
            try writeJSON(swaps.map { ["from_date": $0.from_date, "to_date": $0.to_date] }, to: swapsPath)
            syncState = .unsynced
        } catch {
            statusMessage = "Delete swap failed: \(error.localizedDescription)"
        }
    }

    func deleteLeave(index: Int) {
        guard leaves.indices.contains(index) else { return }
        leaves.remove(at: index)
        do {
            try writeJSON(leaves.map { ["start_date": $0.start_date, "end_date": $0.end_date] }, to: leavePath)
            syncState = .unsynced
        } catch {
            statusMessage = "Delete leave failed: \(error.localizedDescription)"
        }
    }

    func syncNow() {
        guard !isBusy else { return }
        isBusy = true
        busyMessage = "Syncing with Calendar…"
        let path = syncScriptPath
        Task { @MainActor in
            let outcome: (ok: Bool, err: String) = await Task.detached(priority: .userInitiated) {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                proc.arguments = [path]
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
            }.value
            isBusy = false
            busyMessage = ""
            if outcome.ok {
                syncState = .synced
                statusMessage = "Synced."
                loadMeta()
            } else {
                syncState = .error(outcome.err)
                statusMessage = "Sync failed."
            }
        }
    }

    func saveScheduleAndSync() {
        saveSchedule()
        syncNow()
    }

    func addSwapAndSync() {
        addSwap()
        syncNow()
    }

    func addLeaveAndSync() {
        addLeave()
        syncNow()
    }

    func openCalendar() {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        proc.arguments = ["-a", "Calendar"]
        try? proc.run()
    }

    private func loadConfig() {
        do {
            let config = try readConfig()
            startTime = config.default_start_time
            endTime = config.default_end_time
            if let first = config.rules.first {
                selectedDays = Set(first.workdays)
                let df = DateFormatter()
                df.dateFormat = "yyyy-MM-dd"
                effectiveFrom = df.date(from: first.effective_from) ?? Date()
            }
        } catch {
            statusMessage = "Config load failed."
        }
    }

    private func loadSwaps() {
        swaps = (try? readSwaps()) ?? []
    }

    private func loadLeaves() {
        leaves = (try? readLeaves()) ?? []
    }

    private func loadMeta() {
        guard let data = FileManager.default.contents(atPath: metaPath),
              let meta = try? JSONDecoder().decode(Meta.self, from: data) else { return }
        lastSyncText = meta.last_sync_at.isEmpty ? "-" : meta.last_sync_at
        if meta.last_sync_status == "success" { syncState = .synced }
    }

    private func readConfig() throws -> Config {
        let data = try Data(contentsOf: URL(fileURLWithPath: configPath))
        return try JSONDecoder().decode(Config.self, from: data)
    }

    private func readSwaps() throws -> [SwapItem] {
        let data = try Data(contentsOf: URL(fileURLWithPath: swapsPath))
        return try JSONDecoder().decode([SwapItem].self, from: data)
    }

    private func readLeaves() throws -> [LeaveItem] {
        let data = try Data(contentsOf: URL(fileURLWithPath: leavePath))
        return try JSONDecoder().decode([LeaveItem].self, from: data)
    }

    private func writeJSON<T: Encodable>(_ value: T, to path: String) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(value)
        try data.write(to: URL(fileURLWithPath: path))
    }
}

struct ContentView: View {
    @StateObject private var model = AppModel()
    @FocusState private var timeFocus: TimeField?
    @State private var overridesListExpanded = false

    private enum TimeField: Hashable {
        case start
        case end
    }

    private var startOfToday: Date {
        Calendar.current.startOfDay(for: Date())
    }

    private func localDateFromISO(_ iso: String) -> Date? {
        let trimmed = iso.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        var comps = DateComponents()
        comps.year = y
        comps.month = m
        comps.day = d
        return Calendar.current.date(from: comps)
    }

    private func isSwapPast(_ item: SwapItem) -> Bool {
        guard let f = localDateFromISO(item.from_date), let t = localDateFromISO(item.to_date) else { return false }
        return max(f, t) < startOfToday
    }

    private func isLeavePast(_ item: LeaveItem) -> Bool {
        guard let end = localDateFromISO(item.end_date) else { return false }
        return end < startOfToday
    }

    private var visibleSwaps: [(Int, SwapItem)] {
        model.swaps.enumerated().filter { !isSwapPast($0.element) }.map { ($0.offset, $0.element) }
    }

    private var visibleLeaves: [(Int, LeaveItem)] {
        model.leaves.enumerated().filter { !isLeavePast($0.element) }.map { ($0.offset, $0.element) }
    }

    private var overridesVisibleCount: Int {
        visibleSwaps.count + visibleLeaves.count
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(nsColor: .windowBackgroundColor), Color(nsColor: .underPageBackgroundColor)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    weeklySection
                    overridesSection
                    actions
                    if !model.statusMessage.isEmpty {
                        Text(model.statusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                    Color.clear
                        .frame(minHeight: 120)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            resignAllFocus()
                        }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 780)
            .onExitCommand {
                resignAllFocus()
            }
            .onAppear {
                model.load()
                DispatchQueue.main.async {
                    resignAllFocus()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    resignAllFocus()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    resignAllFocus()
                }
            }

            if model.isBusy {
                Color.black.opacity(0.38)
                    .ignoresSafeArea()
                    .allowsHitTesting(true)
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                        .controlSize(.large)
                    Text(model.busyMessage.isEmpty ? "Working…" : model.busyMessage)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)
                }
                .padding(32)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.ultraThickMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
            }
        }
    }

    private func resignAllFocus() {
        timeFocus = nil
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("ShiftFlow").font(.title2).bold()
                Text("Shifts calendar scheduler")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
                .contentShape(Rectangle())
                .frame(minHeight: 48)
                .onTapGesture {
                    resignAllFocus()
                }
            HStack(spacing: 8) {
                Circle().fill(statusColor).frame(width: 9, height: 9)
                Text(statusLabel).fontWeight(.semibold)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.thinMaterial, in: Capsule())

            Text("Last Sync: \(model.lastSyncText)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
        .padding(.bottom, 4)
    }

    private var weeklySection: some View {
        card("Weekly Schedule") {
            HStack {
                ForEach(model.dayOrder, id: \.self) { code in
                    let isSelected = model.selectedDays.contains(code)
                    Button(model.dayLabels[code] ?? code) {
                        if model.selectedDays.contains(code) { model.selectedDays.remove(code) } else { model.selectedDays.insert(code) }
                    }
                    .buttonStyle(.plain)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.16), in: Capsule())
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                }
                Spacer(minLength: 0)
                    .contentShape(Rectangle())
                    .frame(minHeight: 40)
                    .onTapGesture {
                        resignAllFocus()
                    }
            }
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Start").font(.caption).foregroundStyle(.secondary)
                    TextField("10:00", text: $model.startTime)
                        .frame(width: 86)
                        .focused($timeFocus, equals: .start)
                        .onSubmit { resignAllFocus() }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("End").font(.caption).foregroundStyle(.secondary)
                    TextField("18:30", text: $model.endTime)
                        .frame(width: 86)
                        .focused($timeFocus, equals: .end)
                        .onSubmit { resignAllFocus() }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Effective From").font(.caption).foregroundStyle(.secondary)
                    styledDatePicker($model.effectiveFrom)
                }
                Spacer(minLength: 0)
                    .contentShape(Rectangle())
                    .frame(minHeight: 44)
                    .onTapGesture {
                        resignAllFocus()
                    }
            }
            HStack {
                Button("Save") { model.saveSchedule() }
                    .buttonStyle(.bordered)
                    .disabled(model.isBusy)
                Button("Save + Sync") {
                    model.saveScheduleAndSync()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isBusy)
            }
        }
        .environment(\.isEnabled, !model.isBusy)
    }

    private var overridesSection: some View {
        card("Overrides") {
            HStack(alignment: .center, spacing: 10) {
                Text("Swap")
                    .font(.subheadline.weight(.medium))
                    .frame(width: 48, alignment: .leading)
                    .foregroundStyle(.secondary)
                styledDatePicker($model.swapFrom)
                flowArrowSwap()
                styledDatePicker($model.swapTo)
                Button {
                    model.addSwapAndSync()
                } label: {
                    Label("Add", systemImage: "plus.circle.fill")
                }
                .labelStyle(.titleAndIcon)
                .buttonStyle(.bordered)
                .disabled(model.isBusy)
                Spacer(minLength: 0)
                    .contentShape(Rectangle())
                    .frame(minHeight: 36)
                    .onTapGesture {
                        resignAllFocus()
                    }
            }
            HStack(alignment: .center, spacing: 10) {
                Text("Leave")
                    .font(.subheadline.weight(.medium))
                    .frame(width: 48, alignment: .leading)
                    .foregroundStyle(.secondary)
                styledDatePicker($model.leaveStart)
                flowArrowRange()
                styledDatePicker($model.leaveEnd)
                Button {
                    model.addLeaveAndSync()
                } label: {
                    Label("Add", systemImage: "plus.circle.fill")
                }
                .labelStyle(.titleAndIcon)
                .buttonStyle(.bordered)
                .disabled(model.isBusy)
                Spacer(minLength: 0)
                    .contentShape(Rectangle())
                    .frame(minHeight: 36)
                    .onTapGesture {
                        resignAllFocus()
                    }
            }

            DisclosureGroup(isExpanded: $overridesListExpanded) {
                if overridesVisibleCount == 0 {
                    Text("None")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .italic()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(visibleSwaps, id: \.0) { idx, item in
                                overrideSwapRow(idx: idx, item: item)
                            }
                            ForEach(visibleLeaves, id: \.0) { idx, item in
                                overrideLeaveRow(idx: idx, item: item)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .frame(maxHeight: 240)
                }
            } label: {
                HStack(spacing: 8) {
                    Text("Current Overrides")
                        .font(.subheadline.weight(.medium))
                    Text("(\(overridesVisibleCount))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }
            .padding(.top, 4)
        }
        .environment(\.isEnabled, !model.isBusy)
    }

    @ViewBuilder
    private func overrideSwapRow(idx: Int, item: SwapItem) -> some View {
        HStack(spacing: 8) {
            Text("Swap")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.white.opacity(0.08)))
            Text(displayDate(fromISO: item.from_date))
                .font(.system(.body, design: .rounded).weight(.medium).monospacedDigit())
            Image(systemName: "arrow.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
            Text(displayDate(fromISO: item.to_date))
                .font(.system(.body, design: .rounded).weight(.medium).monospacedDigit())
            Spacer()
            Button(role: .destructive) {
                model.deleteSwap(index: idx)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove swap")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    @ViewBuilder
    private func overrideLeaveRow(idx: Int, item: LeaveItem) -> some View {
        HStack(spacing: 8) {
            Text("Leave")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.white.opacity(0.08)))
            Text(displayDate(fromISO: item.start_date))
                .font(.system(.body, design: .rounded).weight(.medium).monospacedDigit())
            Image(systemName: "arrow.left.and.line.vertical.and.arrow.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            Text(displayDate(fromISO: item.end_date))
                .font(.system(.body, design: .rounded).weight(.medium).monospacedDigit())
            Spacer()
            Button(role: .destructive) {
                model.deleteLeave(index: idx)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove leave")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    private var actions: some View {
        card("") {
            HStack {
                Button("Sync Now") { model.syncNow() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isBusy)
                Button("Open Calendar") { model.openCalendar() }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Refresh") { model.load() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(model.isBusy)
            }
        }
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !title.isEmpty {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            content()
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var statusColor: Color {
        switch model.syncState {
        case .synced: return .green
        case .unsynced: return .orange
        case .error: return .red
        }
    }

    private var statusLabel: String {
        switch model.syncState {
        case .synced: return "Synced"
        case .unsynced: return "Unsynced"
        case .error(let msg):
            return msg.isEmpty ? "Error" : "Error"
        }
    }

    @ViewBuilder
    private func styledDatePicker(_ selection: Binding<Date>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            DatePicker("", selection: selection, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
    }

    private func flowArrowSwap() -> some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(.secondary)
            .frame(width: 28, height: 28)
            .background(Circle().fill(Color.white.opacity(0.08)))
    }

    private func flowArrowRange() -> some View {
        Image(systemName: "arrow.left.and.line.vertical.and.arrow.right")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .frame(width: 28, height: 28)
            .background(Circle().fill(Color.white.opacity(0.08)))
    }

    private static let isoParser: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    private func displayDate(fromISO iso: String) -> String {
        guard let d = Self.isoParser.date(from: iso) else { return iso }
        return d.formatted(date: .abbreviated, time: .omitted)
    }
}

@main
struct ShiftFlowAppMain: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 840, height: 780)
    }
}
