import Charts
import ShiftlyKit
import SwiftUI

extension ContentView {
    // MARK: 12-month earnings chart

    @ViewBuilder
    func payChartCard(_ config: PayConfig) -> some View {
        card("Last 12 Months") {
            if model.payMonths.allSatisfy({ $0.breakdown.items.isEmpty }) {
                Text("No earnings in the last 12 months yet.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            } else {
                Chart(model.payMonths) { month in
                    BarMark(
                        x: .value("Month", shortMonthLabel(month.month)),
                        y: .value("Earnings", month.breakdown.totalAmount * config.displayMultiplier(for: payDisplayCurrency))
                    )
                    .foregroundStyle(
                        month.month == paySelectedMonth
                            ? Color.accentColor
                            : Color.accentColor.opacity(0.45)
                    )
                    .cornerRadius(4)
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 180)
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .onTapGesture { location in
                                let origin = geo[proxy.plotAreaFrame].origin
                                if let label: String = proxy.value(atX: location.x - origin.x) {
                                    if let hit = model.payMonths.first(where: { shortMonthLabel($0.month) == label }) {
                                        paySelectedMonth = hit.month
                                    }
                                }
                            }
                    }
                }
                Text("Click a bar for the month's shifts. Amounts in \(payDisplayCurrency).")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: Month drill-down

    @ViewBuilder
    func payDrilldownCard(_ config: PayConfig) -> some View {
        let month = paySelectedMonth ?? model.payMonths.last?.month
        card("") {
            HStack {
                Text(monthTitle(month ?? ""))
                    .font(.headline)
                Spacer(minLength: 0)
                Picker("", selection: Binding(
                    get: { month ?? "" },
                    set: { paySelectedMonth = $0 }
                )) {
                    ForEach(model.payMonths.reversed()) { m in
                        Text(monthTitle(m.month)).tag(m.month)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 160)
            }
            if let data = model.payMonths.first(where: { $0.month == month })?.breakdown {
                if data.items.isEmpty {
                    Text("No shifts this month.")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(data.items) { earning in
                                earningRow(earning, config: config)
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                    HStack {
                        Text(String(format: "%.1f h", data.totalHours))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                        Spacer(minLength: 0)
                        Text(payAmountText(data.totalAmount, config: config))
                            .font(.subheadline.weight(.bold))
                            .monospacedDigit()
                    }
                    .padding(.top, 4)
                    HStack(spacing: 10) {
                        Button("Export CSV…") {
                            exportPayslip(month: month ?? "", breakdown: data, config: config, format: "csv")
                        }
                        .buttonStyle(.bordered)
                        Button("Export Markdown…") {
                            exportPayslip(month: month ?? "", breakdown: data, config: config, format: "md")
                        }
                        .buttonStyle(.bordered)
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    private func earningRow(_ earning: ShiftEarning, config: PayConfig) -> some View {
        HStack(spacing: 12) {
            Text(earning.date)
                .font(.system(.subheadline, design: .monospaced))
            Text("\(SyncFingerprint.hhmmString(for: earning.start))–\(SyncFingerprint.hhmmString(for: earning.end))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Text(String(format: "%.1f h", earning.hours))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            if earning.hourlyRate == nil {
                Text("no rate")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            Spacer(minLength: 0)
            Text(payAmountText(earning.amount, config: config))
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    // MARK: Export

    private func exportPayslip(month: String, breakdown: PayBreakdown, config: PayConfig, format: String) {
        let content = format == "csv"
            ? PayslipExporter.csv(month: month, breakdown: breakdown, config: config, displayCurrency: payDisplayCurrency)
            : PayslipExporter.markdown(month: month, breakdown: breakdown, config: config, displayCurrency: payDisplayCurrency)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "shiftly-payslip-\(month).\(format)"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try Data(content.utf8).write(to: url, options: .atomic)
                model.statusMessage = LF("Payslip exported to %@.", url.lastPathComponent)
            } catch {
                model.statusMessage = LF("Export failed: %@", error.localizedDescription)
            }
        }
    }

    // MARK: Labels

    private func shortMonthLabel(_ month: String) -> String {
        let parts = month.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2 else { return month }
        var comps = DateComponents()
        comps.year = parts[0]
        comps.month = parts[1]
        guard let date = Calendar.current.date(from: comps) else { return month }
        return date.formatted(.dateTime.month(.abbreviated))
    }

    private func monthTitle(_ month: String) -> String {
        let parts = month.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2 else { return month }
        var comps = DateComponents()
        comps.year = parts[0]
        comps.month = parts[1]
        guard let date = Calendar.current.date(from: comps) else { return month }
        return date.formatted(.dateTime.year().month(.wide))
    }
}
