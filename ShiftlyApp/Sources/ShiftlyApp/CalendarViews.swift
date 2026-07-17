import ShiftlyKit
import SwiftUI

/// Identity + context for the day popover.
struct SelectedDay: Identifiable {
    let ymd: String
    var id: String { ymd }
}

/// What a calendar day shows. Precedence: leave > manual > swap-in > rule.
enum DayCategory {
    case none
    case rule
    case swapIn
    case manual
    case leave

    var color: Color {
        switch self {
        case .none: return .clear
        case .rule: return .accentColor
        case .swapIn: return .orange
        case .manual: return .purple
        case .leave: return .gray
        }
    }

    var label: String {
        switch self {
        case .none: return "No shift"
        case .rule: return "Shift"
        case .swapIn: return "Shift (swapped)"
        case .manual: return "Shift (manual)"
        case .leave: return "Leave / day off"
        }
    }
}

extension ContentView {
    var calendarSection: some View {
        card("") {
            VStack(alignment: .leading, spacing: 12) {
                monthHeader
                weekdayHeader
                monthGrid
                legend
            }
        }
        .environment(\.isEnabled, !model.isBusy)
        .onAppear {
            requestMonth()
        }
    }

    private var monthHeader: some View {
        HStack(spacing: 10) {
            Text(calMonth.formatted(.dateTime.year().month(.wide)))
                .font(.title3.weight(.semibold))
            Spacer(minLength: 0)
            Button {
                shiftMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.bordered)
            Button("Today") {
                calMonth = Self.startOfMonth(Date())
                requestMonth()
            }
            .buttonStyle(.bordered)
            Button {
                shiftMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.bordered)
        }
    }

    private var weekdayHeader: some View {
        let cal = Calendar.current
        let symbols = cal.shortStandaloneWeekdaySymbols
        let ordered = (0..<7).map { symbols[(cal.firstWeekday - 1 + $0) % 7] }
        return HStack(spacing: 6) {
            ForEach(ordered, id: \.self) { day in
                Text(day)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var monthGrid: some View {
        let days = Self.gridDays(for: calMonth)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                if let day {
                    dayCell(day)
                } else {
                    Color.clear.frame(height: 64)
                }
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let ymd = Self.ymdString(date)
        let category = dayCategory(ymd)
        let shift = model.monthShifts[ymd]
        let isToday = Calendar.current.isDateInToday(date)
        return Button {
            calSelectedDay = SelectedDay(ymd: ymd)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(Calendar.current.component(.day, from: date))")
                        .font(.subheadline.weight(isToday ? .bold : .regular))
                        .foregroundStyle(isToday ? Color.accentColor : Color.primary)
                        .padding(4)
                        .background(
                            Circle().fill(isToday ? Color.accentColor.opacity(0.18) : Color.clear)
                        )
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
                if let shift {
                    Text("\(SyncFingerprint.hhmmString(for: shift.start))–\(SyncFingerprint.hhmmString(for: shift.end))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if category != .none {
                    Capsule()
                        .fill(category.color.opacity(category == .leave ? 0.45 : 0.85))
                        .frame(height: 4)
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(isToday ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.07), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: Binding(
            get: { calSelectedDay?.ymd == ymd },
            set: { if !$0 { calSelectedDay = nil } }
        )) {
            dayPopover(ymd: ymd, category: category, shift: shift)
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(.rule)
            legendItem(.swapIn)
            legendItem(.manual)
            legendItem(.leave)
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }

    private func legendItem(_ category: DayCategory) -> some View {
        HStack(spacing: 5) {
            Capsule().fill(category.color.opacity(0.85)).frame(width: 14, height: 4)
            Text(L(category.label))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Day popover

    @ViewBuilder
    private func dayPopover(ymd: String, category: DayCategory, shift: PlannedShift?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Capsule().fill(category.color.opacity(0.85)).frame(width: 14, height: 4)
                Text(localDateFromISO(ymd)?.formatted(date: .complete, time: .omitted) ?? ymd)
                    .font(.subheadline.weight(.semibold))
            }
            HStack(spacing: 6) {
                Text(L(category.label))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let shift {
                    Text("\(SyncFingerprint.hhmmString(for: shift.start))–\(SyncFingerprint.hhmmString(for: shift.end))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            if shift != nil {
                HStack(spacing: 8) {
                    Text("Swap to")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    DatePicker("", selection: $calSwapTarget, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                    Button("Swap") {
                        if let day = localDateFromISO(ymd) {
                            model.swapFrom = day
                            model.swapTo = calSwapTarget
                            calSelectedDay = nil
                            model.addSwapAndSync()
                        }
                    }
                    .buttonStyle(.bordered)
                }
                Button("Take leave on this day") {
                    if let day = localDateFromISO(ymd) {
                        model.leaveStart = day
                        model.leaveEnd = day
                        calSelectedDay = nil
                        model.addLeaveAndSync()
                    }
                }
                .buttonStyle(.bordered)
            } else if category == .leave {
                Text("Covered by a leave range — manage it under Today → Overrides.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 220)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Button("Add leave on this day") {
                    if let day = localDateFromISO(ymd) {
                        model.leaveStart = day
                        model.leaveEnd = day
                        calSelectedDay = nil
                        model.addLeaveAndSync()
                    }
                }
                .buttonStyle(.bordered)
            }

            Button("Write log entry") {}
                .buttonStyle(.bordered)
                .disabled(true)
                .help("Work logs arrive in milestone M5")
        }
        .padding(14)
        .frame(minWidth: 240)
    }

    // MARK: Categorization & month math

    private func dayCategory(_ ymd: String) -> DayCategory {
        if isOnLeave(ymd) {
            return .leave
        }
        guard let shift = model.monthShifts[ymd] else {
            return .none
        }
        if shift.kind == .manual {
            return .manual
        }
        if model.swaps.contains(where: { $0.to_date == ymd }) {
            return .swapIn
        }
        return .rule
    }

    private func isOnLeave(_ ymd: String) -> Bool {
        model.leaves.contains { leave in
            let a = min(leave.start_date, leave.end_date)
            let b = max(leave.start_date, leave.end_date)
            return ymd >= a && ymd <= b
        }
    }

    func requestMonth() {
        let cal = Calendar.current
        let start = Self.startOfMonth(calMonth)
        guard let dayRange = cal.range(of: .day, in: .month, for: start),
              let last = cal.date(byAdding: .day, value: dayRange.count - 1, to: start) else {
            return
        }
        model.loadMonth(start: Self.ymdString(start), end: Self.ymdString(last))
    }

    private func shiftMonth(by delta: Int) {
        if let next = Calendar.current.date(byAdding: .month, value: delta, to: calMonth) {
            calMonth = Self.startOfMonth(next)
            requestMonth()
        }
    }

    static func startOfMonth(_ date: Date) -> Date {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month], from: date)) ?? date
    }

    static func ymdString(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Cells for the month grid: leading nils to align the first weekday,
    /// then every day of the month.
    static func gridDays(for month: Date) -> [Date?] {
        let cal = Calendar.current
        let start = startOfMonth(month)
        guard let dayRange = cal.range(of: .day, in: .month, for: start) else { return [] }
        let firstWeekday = cal.component(.weekday, from: start)
        let leading = (firstWeekday - cal.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for offset in 0..<dayRange.count {
            cells.append(cal.date(byAdding: .day, value: offset, to: start))
        }
        return cells
    }
}
