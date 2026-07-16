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
    var overridesSection: some View {
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
                            ForEach(visibleSwaps) { item in
                                overrideSwapRow(item: item)
                            }
                            ForEach(visibleLeaves) { item in
                                overrideLeaveRow(item: item)
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

    var visibleSwaps: [SwapItem] {
        model.swaps.filter { !isSwapPast($0) }
    }

    var visibleLeaves: [LeaveItem] {
        model.leaves.filter { !isLeavePast($0) }
    }

    var overridesVisibleCount: Int {
        visibleSwaps.count + visibleLeaves.count
    }

    private func isSwapPast(_ item: SwapItem) -> Bool {
        guard let f = localDateFromISO(item.from_date), let t = localDateFromISO(item.to_date) else { return false }
        return max(f, t) < startOfToday
    }

    private func isLeavePast(_ item: LeaveItem) -> Bool {
        guard let end = localDateFromISO(item.end_date) else { return false }
        return end < startOfToday
    }

    @ViewBuilder
    private func overrideSwapRow(item: SwapItem) -> some View {
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
                model.deleteSwap(id: item.id)
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
    private func overrideLeaveRow(item: LeaveItem) -> some View {
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
                model.deleteLeave(id: item.id)
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

    private func displayDate(fromISO iso: String) -> String {
        guard let d = isoParser.date(from: iso) else { return iso }
        return d.formatted(date: .abbreviated, time: .omitted)
    }
}
