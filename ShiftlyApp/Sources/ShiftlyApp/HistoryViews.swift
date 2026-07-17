import ShiftlyKit
import SwiftUI

extension ContentView {
    var historySection: some View {
        card("") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            historyExpanded.toggle()
                            if !historyExpanded {
                                historyActiveTool = nil
                                historySearchFocused = false
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: historyExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                                .frame(width: 14, alignment: .center)
                            Text("Work History")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                    Button("Refresh") {
                        model.refreshWorkHistory()
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isBusy || !model.paths.isValid)
                }

                if historyExpanded {
                    HStack {
                        Spacer(minLength: 0)
                        HStack(spacing: 4) {
                            ForEach(HistoryTool.allCases) { tool in
                                historyToolIconButton(tool)
                            }
                        }
                    }

                    if let tool = historyActiveTool {
                        historyToolPanel(tool)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.primary.opacity(0.06))
                            )
                    }

                    if !model.workHistoryNote.isEmpty {
                        Text(model.workHistoryNote)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    if model.workHistory.isEmpty && model.workHistoryNote.isEmpty && model.paths.isValid {
                        Text("No entries.")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    } else if !model.workHistory.isEmpty && filteredWorkHistory.isEmpty {
                        Text("No matches for current filters.")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    } else if !filteredWorkHistory.isEmpty {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                ForEach(filteredWorkHistory) { row in
                                    HStack(spacing: 12) {
                                        Text("Day \(row.ordinal)")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.tertiary)
                                            .frame(width: 72, alignment: .leading)
                                        Text(row.ymd)
                                            .font(.system(.body, design: .rounded).monospacedDigit())
                                        Spacer(minLength: 0)
                                        Text(weekdayLabel(forYMD: row.ymd))
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(Color.primary.opacity(0.05))
                                    )
                                }
                            }
                        }
                        .frame(maxHeight: 240)
                    }
                }
            }
        }
        .environment(\.isEnabled, !model.isBusy)
    }

    private func historyToolIconButton(_ tool: HistoryTool) -> some View {
        let on = historyActiveTool == tool
        return Button {
            if historyActiveTool == tool {
                historyActiveTool = nil
                historySearchFocused = false
            } else {
                historyActiveTool = tool
                if tool == .search {
                    DispatchQueue.main.async {
                        NSApp.activate(ignoringOtherApps: true)
                        historySearchFocused = true
                    }
                } else {
                    historySearchFocused = false
                }
            }
        } label: {
            Image(systemName: tool.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(on ? Color.accentColor : Color.secondary)
                .frame(width: 30, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(on ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05))
                )
        }
        .buttonStyle(.plain)
        .help(tool.helpText)
    }

    @ViewBuilder
    private func historyToolPanel(_ tool: HistoryTool) -> some View {
        switch tool {
        case .period:
            HStack(alignment: .center, spacing: 10) {
                Text("Range").font(.caption).foregroundStyle(.secondary)
                Picker("Range", selection: $historyPeriod) {
                    ForEach(HistoryPeriodFilter.allCases) { p in
                        Text(p.rawValue).tag(p)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(minWidth: 140, alignment: .leading)
                if historyPeriod == .custom {
                    Text("From").font(.caption).foregroundStyle(.secondary)
                    styledDatePicker($historyRangeFrom)
                    Text("To").font(.caption).foregroundStyle(.secondary)
                    styledDatePicker($historyRangeTo)
                }
                Spacer(minLength: 0)
            }
        case .sort:
            HStack(spacing: 10) {
                Text("Order").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $historyNewestFirst) {
                    Text("Oldest first").tag(false)
                    Text("Newest first").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
                Spacer(minLength: 0)
            }
        case .quick:
            HStack(spacing: 8) {
                Button("This week") { historyPeriod = .thisWeek }
                    .buttonStyle(.bordered)
                Button("This month") { historyPeriod = .thisMonth }
                    .buttonStyle(.bordered)
                Button("All time") { historyPeriod = .all }
                    .buttonStyle(.bordered)
                Spacer(minLength: 0)
            }
        case .search:
            TextField("Search by date (e.g. 2026-04)", text: $historyDateSearch)
                .textFieldStyle(.roundedBorder)
                .focused($historySearchFocused)
                .frame(maxWidth: .infinity)
        case .weekday:
            HStack(spacing: 6) {
                ForEach(0 ..< 7, id: \.self) { idx in
                    let wd = idx + 1
                    let sym = Calendar.current.shortStandaloneWeekdaySymbols[wd - 1]
                    let on = historyWeekdayFilter.contains(wd)
                    Button(sym) {
                        if on { historyWeekdayFilter.remove(wd) } else { historyWeekdayFilter.insert(wd) }
                    }
                    .buttonStyle(.plain)
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(on ? Color.accentColor : Color.secondary.opacity(0.16), in: Capsule())
                    .foregroundStyle(on ? Color.white : Color.primary)
                }
            }
        }
    }

    var filteredWorkHistory: [WorkHistoryRow] {
        var rows = model.workHistory
        let q = historyDateSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            rows = rows.filter { $0.ymd.localizedCaseInsensitiveContains(q) }
        }
        rows = rows.filter { historyDateInPeriod($0) }
        if !historyWeekdayFilter.isEmpty {
            rows = rows.filter { row in
                guard let d = historyRowDate(row) else { return false }
                let wd = Calendar.current.component(.weekday, from: d)
                return historyWeekdayFilter.contains(wd)
            }
        }
        return rows.sorted { a, b in
            guard let da = historyRowDate(a), let db = historyRowDate(b) else {
                return a.ymd < b.ymd
            }
            if historyNewestFirst { return da > db }
            return da < db
        }
    }

    private var historyPeriodBounds: (start: Date, end: Date)? {
        let cal = Calendar.current
        let today = Date()
        switch historyPeriod {
        case .all:
            return nil
        case .thisWeek:
            guard let iv = cal.dateInterval(of: .weekOfYear, for: today) else { return nil }
            let s = cal.startOfDay(for: iv.start)
            guard let last = cal.date(byAdding: .day, value: 6, to: s) else { return nil }
            return (s, cal.startOfDay(for: last))
        case .thisMonth:
            let c = cal.dateComponents([.year, .month], from: today)
            guard let monthStart = cal.date(from: c),
                  let monthRange = cal.range(of: .day, in: .month, for: monthStart),
                  let endDay = cal.date(byAdding: .day, value: monthRange.count - 1, to: monthStart) else { return nil }
            return (cal.startOfDay(for: monthStart), cal.startOfDay(for: endDay))
        case .custom:
            let a = cal.startOfDay(for: historyRangeFrom)
            let b = cal.startOfDay(for: historyRangeTo)
            return a <= b ? (a, b) : (b, a)
        }
    }

    private func historyRowDate(_ row: WorkHistoryRow) -> Date? {
        localDateFromISO(row.ymd)
    }

    private func historyDateInPeriod(_ row: WorkHistoryRow) -> Bool {
        guard let bounds = historyPeriodBounds else { return true }
        guard let d = historyRowDate(row) else { return false }
        let cal = Calendar.current
        let ds = cal.startOfDay(for: d)
        return ds >= bounds.start && ds <= bounds.end
    }

    private func weekdayLabel(forYMD ymd: String) -> String {
        let parts = ymd.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return "—" }
        var comps = DateComponents()
        comps.year = parts[0]
        comps.month = parts[1]
        comps.day = parts[2]
        guard let date = Calendar.current.date(from: comps) else { return "—" }
        let f = DateFormatter()
        f.locale = .current
        f.dateFormat = "EEEE"
        return f.string(from: date)
    }
}
