import ShiftlyKit
import SwiftUI

private let isoParser: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(secondsFromGMT: 0)
    return f
}()

extension ContentView {
    // MARK: Swap

    var swapSection: some View {
        card("Swap") {
            HStack(alignment: .center, spacing: 10) {
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

            recordsList(
                upcoming: upcomingSwaps.map(swapRowData),
                past: pastSwaps.map(swapRowData),
                pastExpanded: $swapPastExpanded
            )
        }
        .environment(\.isEnabled, !model.isBusy)
    }

    // MARK: Leave

    var leaveSection: some View {
        card("Leave") {
            HStack(alignment: .center, spacing: 10) {
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

            recordsList(
                upcoming: upcomingLeaves.map(leaveRowData),
                past: pastLeaves.map(leaveRowData),
                pastExpanded: $leavePastExpanded
            )
        }
        .environment(\.isEnabled, !model.isBusy)
    }

    // MARK: Shared record rows

    struct OverrideRowData: Identifiable {
        let id: UUID
        let fromText: String
        let toText: String
        let arrow: String
        let deleteHelp: String
        let onDelete: () -> Void
    }

    @ViewBuilder
    private func recordsList(
        upcoming: [OverrideRowData],
        past: [OverrideRowData],
        pastExpanded: Binding<Bool>
    ) -> some View {
        if upcoming.isEmpty && past.isEmpty {
            Text("None")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .italic()
        } else {
            if !upcoming.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(upcoming) { row in
                        overrideRow(row)
                    }
                }
            }
            if !past.isEmpty {
                DisclosureGroup(isExpanded: pastExpanded) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(past) { row in
                                overrideRow(row)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .frame(maxHeight: 220)
                } label: {
                    HStack(spacing: 8) {
                        Text("Past")
                            .font(.subheadline.weight(.medium))
                        Text("(\(past.count))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    @ViewBuilder
    private func overrideRow(_ row: OverrideRowData) -> some View {
        HStack(spacing: 8) {
            Text(row.fromText)
                .font(.system(.body, design: .rounded).weight(.medium).monospacedDigit())
            Image(systemName: row.arrow)
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
            Text(row.toText)
                .font(.system(.body, design: .rounded).weight(.medium).monospacedDigit())
            Spacer()
            Button(role: .destructive) {
                row.onDelete()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help(row.deleteHelp)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private func swapRowData(_ item: SwapItem) -> OverrideRowData {
        OverrideRowData(
            id: item.id,
            fromText: displayDate(fromISO: item.from_date),
            toText: displayDate(fromISO: item.to_date),
            arrow: "arrow.right",
            deleteHelp: L("Remove swap"),
            onDelete: { [id = item.id] in model.deleteSwap(id: id) }
        )
    }

    private func leaveRowData(_ item: LeaveItem) -> OverrideRowData {
        OverrideRowData(
            id: item.id,
            fromText: displayDate(fromISO: item.start_date),
            toText: displayDate(fromISO: item.end_date),
            arrow: "arrow.left.and.line.vertical.and.arrow.right",
            deleteHelp: L("Remove leave"),
            onDelete: { [id = item.id] in model.deleteLeave(id: id) }
        )
    }

    // MARK: Partitioning

    private var upcomingSwaps: [SwapItem] {
        model.swaps.filter { !isSwapPast($0) }
    }

    private var pastSwaps: [SwapItem] {
        model.swaps.filter(isSwapPast).sorted { max($0.from_date, $0.to_date) > max($1.from_date, $1.to_date) }
    }

    private var upcomingLeaves: [LeaveItem] {
        model.leaves.filter { !isLeavePast($0) }
    }

    private var pastLeaves: [LeaveItem] {
        model.leaves.filter(isLeavePast).sorted { $0.end_date > $1.end_date }
    }

    private func isSwapPast(_ item: SwapItem) -> Bool {
        guard let f = localDateFromISO(item.from_date), let t = localDateFromISO(item.to_date) else { return false }
        return max(f, t) < startOfToday
    }

    private func isLeavePast(_ item: LeaveItem) -> Bool {
        guard let end = localDateFromISO(item.end_date) else { return false }
        return end < startOfToday
    }

    // MARK: Bits

    private func flowArrowSwap() -> some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(.secondary)
            .frame(width: 28, height: 28)
            .background(Circle().fill(Color.primary.opacity(0.08)))
    }

    private func flowArrowRange() -> some View {
        Image(systemName: "arrow.left.and.line.vertical.and.arrow.right")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .frame(width: 28, height: 28)
            .background(Circle().fill(Color.primary.opacity(0.08)))
    }

    func displayDate(fromISO iso: String) -> String {
        guard let d = isoParser.date(from: iso) else { return iso }
        return d.formatted(date: .abbreviated, time: .omitted)
    }
}
