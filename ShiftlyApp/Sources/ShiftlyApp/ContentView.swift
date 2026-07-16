import ShiftlyKit
import SwiftUI

struct ContentView: View {
    @StateObject var model = AppModel()
    @FocusState var timeFocus: TimeField?
    @FocusState var historySearchFocused: Bool
    @State var overridesListExpanded = false
    @State var historyExpanded = false
    @State var historyDateSearch = ""
    @State var historyPeriod: HistoryPeriodFilter = .all
    @State var historyRangeFrom = Date()
    @State var historyRangeTo = Date()
    @State var historyWeekdayFilter: Set<Int> = []
    @State var historyNewestFirst = false
    @State var historyActiveTool: HistoryTool? = nil

    enum TimeField: Hashable {
        case start
        case end
    }

    enum HistoryTool: Int, CaseIterable, Identifiable {
        case period
        case sort
        case quick
        case search
        case weekday

        var id: Int { rawValue }

        var systemImage: String {
            switch self {
            case .period: return "line.3.horizontal.decrease.circle"
            case .sort: return "arrow.up.arrow.down"
            case .quick: return "bolt.fill"
            case .search: return "magnifyingglass"
            case .weekday: return "slider.horizontal.3"
            }
        }

        var helpText: String {
            switch self {
            case .period: return "Time period"
            case .sort: return "Sort order"
            case .quick: return "Quick range"
            case .search: return "Search by date"
            case .weekday: return "Weekday"
            }
        }
    }

    enum HistoryPeriodFilter: String, CaseIterable, Identifiable {
        case all = "All time"
        case thisWeek = "This week"
        case thisMonth = "This month"
        case custom = "Custom range"
        var id: String { rawValue }
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
                    historySection
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

    func resignAllFocus() {
        timeFocus = nil
        historySearchFocused = false
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Shiftly").font(.title2).bold()
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
            if !model.rulesSummary.isEmpty {
                Text(model.rulesSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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

    // MARK: shared helpers

    func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
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
        case .error: return "Error"
        }
    }

    @ViewBuilder
    func styledDatePicker(_ selection: Binding<Date>) -> some View {
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

    var startOfToday: Date {
        Calendar.current.startOfDay(for: Date())
    }

    func localDateFromISO(_ iso: String) -> Date? {
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
}
