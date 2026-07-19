import ShiftlyKit
import SwiftUI

extension ContentView {
    /// Shift page: public holidays. The engine skips rule days that fall on
    /// a holiday (an explicit swap onto one still wins).
    var holidaysSection: some View {
        card("Holidays") {
            Text("No shifts are scheduled on holidays. Swapping a shift onto a holiday on purpose still works.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .center, spacing: 10) {
                styledDatePicker($model.holidayStart)
                Image(systemName: "arrow.left.and.line.vertical.and.arrow.right")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.primary.opacity(0.08)))
                styledDatePicker($model.holidayEnd)
                TextField("Name (optional)", text: $model.holidayName)
                    .frame(width: 150)
                Button {
                    model.addHolidayAndSync()
                } label: {
                    Label("Add", systemImage: "plus.circle.fill")
                }
                .labelStyle(.titleAndIcon)
                .buttonStyle(.bordered)
                .disabled(model.isBusy)
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Text("Import from a holidays calendar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if model.importCalendars.isEmpty {
                    Button("Load Calendars…") {
                        model.loadImportCalendars()
                    }
                    .buttonStyle(.bordered)
                } else {
                    Picker("", selection: $holidayImportCalendarID) {
                        Text("Choose a calendar").tag("")
                        ForEach(model.importCalendars) { calendar in
                            Text(calendar.title).tag(calendar.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 240)
                    Button {
                        model.importHolidays(calendarID: holidayImportCalendarID)
                    } label: {
                        HStack(spacing: 6) {
                            if model.holidayImportRunning {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "square.and.arrow.down")
                            }
                            Text("Import Holidays")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(holidayImportCalendarID.isEmpty || model.holidayImportRunning)
                }
                Spacer(minLength: 0)
            }

            if upcomingHolidays.isEmpty && pastHolidays.isEmpty {
                Text("None")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .italic()
            }
            if !upcomingHolidays.isEmpty {
                Text("Upcoming")
                    .font(.subheadline.weight(.medium))
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(upcomingHolidays) { item in
                        holidayRow(item: item)
                    }
                }
            }
            if !pastHolidays.isEmpty {
                DisclosureGroup(isExpanded: $holidaysPastExpanded) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(pastHolidays) { item in
                                holidayRow(item: item)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .frame(maxHeight: 220)
                } label: {
                    HStack(spacing: 8) {
                        Text("Past")
                            .font(.subheadline.weight(.medium))
                        Text("(\(pastHolidays.count))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                }
                .padding(.top, 2)
            }
        }
        .environment(\.isEnabled, !model.isBusy)
    }

    private var upcomingHolidays: [HolidayItem] {
        model.holidays.filter { item in
            guard let end = localDateFromISO(item.end_date) else { return false }
            return end >= startOfToday
        }
    }

    private var pastHolidays: [HolidayItem] {
        model.holidays
            .filter { item in
                guard let end = localDateFromISO(item.end_date) else { return true }
                return end < startOfToday
            }
            .sorted { $0.start_date > $1.start_date }
    }

    private func holidayRangeText(_ item: HolidayItem) -> String {
        let start = localDateFromISO(item.start_date)?
            .formatted(date: .abbreviated, time: .omitted) ?? item.start_date
        guard item.end_date != item.start_date else { return start }
        let end = localDateFromISO(item.end_date)?
            .formatted(date: .abbreviated, time: .omitted) ?? item.end_date
        return "\(start) – \(end)"
    }

    @ViewBuilder
    private func holidayRow(item: HolidayItem) -> some View {
        HStack(spacing: 8) {
            Text(holidayRangeText(item))
                .font(.system(.body, design: .rounded).weight(.medium).monospacedDigit())
            if !item.name.isEmpty {
                Text(item.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(role: .destructive) {
                model.deleteHoliday(id: item.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove holiday")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }
}
