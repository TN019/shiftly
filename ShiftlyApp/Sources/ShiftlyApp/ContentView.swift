import ShiftlyKit
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case today, calendar, pay, log, settings

    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: return "Today"
        case .calendar: return "Calendar"
        case .pay: return "Pay"
        case .log: return "Log"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .today: return "sun.max"
        case .calendar: return "calendar"
        case .pay: return "dollarsign.circle"
        case .log: return "text.book.closed"
        case .settings: return "gearshape"
        }
    }
}

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
    @State var calMonth: Date = ContentView.startOfMonth(Date())
    @State var calSelectedDay: SelectedDay? = nil
    @State var calSwapTarget: Date = Date()
    @AppStorage("shiftly.section") private var storedSection = AppSection.today.rawValue

    private var sectionSelection: Binding<AppSection?> {
        Binding(
            get: { AppSection(rawValue: storedSection) ?? .today },
            set: { storedSection = ($0 ?? .today).rawValue }
        )
    }

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
            NavigationSplitView {
                List(AppSection.allCases, selection: sectionSelection) { section in
                    Label(section.label, systemImage: section.systemImage)
                        .tag(section)
                }
                .navigationSplitViewColumnWidth(min: 165, ideal: 185, max: 230)
                .listStyle(.sidebar)
            } detail: {
                detailPage(for: AppSection(rawValue: storedSection) ?? .today)
            }
            .navigationTitle("Shiftly")
            .frame(minWidth: 860, minHeight: 560)
            .onExitCommand {
                resignAllFocus()
            }
            .onAppear {
                model.load()
                model.startAutoSyncIfEnabled()
                DispatchQueue.main.async {
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
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                )
            }
        }
    }

    @ViewBuilder
    private func detailPage(for section: AppSection) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if model.needsRootSetup {
                    firstRunSection
                } else {
                    switch section {
                    case .today: todayPage
                    case .calendar: calendarPage
                    case .pay: payPage
                    case .log: logPage
                    case .settings: settingsPage
                    }
                }
                if !model.statusMessage.isEmpty {
                    HStack(spacing: 10) {
                        Text(model.statusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if model.showSettingsHint {
                            Button("Open Settings") {
                                model.openCalendarPrivacySettings()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(.top, 2)
                }
                Color.clear
                    .frame(minHeight: 60)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        resignAllFocus()
                    }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Pages

    @ViewBuilder
    private var todayPage: some View {
        header
        nextShiftCard
        weeklySection
        overridesSection
        syncReportSection
        actions
    }

    @ViewBuilder
    private var calendarPage: some View {
        calendarSection
        historySection
    }

    @ViewBuilder
    private var payPage: some View {
        placeholderCard(
            title: "Pay",
            systemImage: "dollarsign.circle",
            text: "Pay tracking arrives in milestone M4: hourly rates, overtime and allowances, monthly charts, and payslip export."
        )
    }

    @ViewBuilder
    private var logPage: some View {
        placeholderCard(
            title: "Work Log",
            systemImage: "text.book.closed",
            text: "Markdown work logs arrive in milestone M5: daily notes in a folder of your choice, quick capture, and calendar integration."
        )
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Today").font(.title2).bold()
                Text(Date().formatted(date: .complete, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
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

    private var nextShiftCard: some View {
        card("") {
            HStack(spacing: 12) {
                Image(systemName: "clock.badge.checkmark")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                if let shift = model.nextShift {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Next shift")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(shift.start.formatted(date: .abbreviated, time: .shortened)) – \(shift.end.formatted(date: .omitted, time: .shortened))")
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                    }
                    Spacer(minLength: 0)
                    Text(shift.start > Date()
                         ? shift.start.formatted(.relative(presentation: .named))
                         : "in progress")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No upcoming shift in the next 45 days")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }
        }
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

    // MARK: Settings page

    @ViewBuilder
    private var settingsPage: some View {
        card("Calendar") {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Calendar name").font(.caption).foregroundStyle(.secondary)
                    TextField("Shifts", text: $model.calendarName)
                        .frame(width: 180)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Event title").font(.caption).foregroundStyle(.secondary)
                    TextField("Work Schedule", text: $model.eventTitle)
                        .frame(width: 180)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(" ").font(.caption)
                    Button("Save") { model.saveCalendarSettings() }
                        .buttonStyle(.bordered)
                }
                Spacer(minLength: 0)
            }
            Text("Renaming the calendar makes the next sync create/claim a calendar with the new name; existing events in the old calendar are not moved.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }

        card("Sync") {
            HStack(spacing: 14) {
                Text("Auto-sync").font(.subheadline)
                Picker("", selection: $model.autoSyncHours) {
                    Text("Off").tag(0)
                    Text("Hourly").tag(1)
                    Text("Every 6h").tag(6)
                    Text("Every 12h").tag(12)
                    Text("Daily").tag(24)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 110)
                Toggle("Launch at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                .toggleStyle(.checkbox)
                Spacer(minLength: 0)
            }
            Text("Auto-sync runs while Shiftly is open; pair it with Launch at login to survive reboots. Headless syncing without the app uses the launchd template (see README).")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }

        card("Data Folder") {
            HStack(spacing: 10) {
                Text(model.paths.root)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                Button("Show in Finder") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: model.paths.root)
                }
                .buttonStyle(.bordered)
                Button("Change…") { chooseDataFolder() }
                    .buttonStyle(.bordered)
            }
            Text("Changing the folder does not move existing data. The SHIFTLY_ROOT environment variable overrides this choice when set.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var firstRunSection: some View {
        card("Welcome to Shiftly") {
            Text("Choose a folder to hold Shiftly's data (schedule, swaps, leave). A starter config is created if the folder is empty — an existing Shiftly data folder is picked up as is.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("After that: set your weekly schedule, then press Sync Now — macOS will ask for Calendar access on the first sync.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Button("Choose Data Folder…") {
                chooseDataFolder()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func placeholderCard(title: String, systemImage: String, text: String) -> some View {
        card(title) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
        }
    }

    private func chooseDataFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Use This Folder"
        panel.message = "Choose the folder where Shiftly stores its data."
        if panel.runModal() == .OK, let url = panel.url {
            model.adoptRoot(url)
        }
    }

    // MARK: Shared helpers

    func resignAllFocus() {
        timeFocus = nil
        historySearchFocused = false
    }

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
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
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
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
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
