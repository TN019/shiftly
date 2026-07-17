import Foundation

/// Renders a month's earnings as CSV or Markdown. Amounts (and the rate
/// column) are converted to the chosen display currency with the config's
/// manual multiplier, matching what the app shows.
public enum PayslipExporter {
    public static func csv(
        month: String,
        breakdown: PayBreakdown,
        config: PayConfig,
        displayCurrency: String
    ) -> String {
        let multiplier = config.displayMultiplier(for: displayCurrency)
        var lines = ["Date,Start,End,Hours,Rate (\(displayCurrency)),Amount (\(displayCurrency))"]
        for item in breakdown.items {
            let rate = item.hourlyRate.map { String(format: "%.2f", $0 * multiplier) } ?? ""
            lines.append([
                item.date,
                SyncFingerprint.hhmmString(for: item.start),
                SyncFingerprint.hhmmString(for: item.end),
                String(format: "%.2f", item.hours),
                rate,
                String(format: "%.2f", item.amount * multiplier),
            ].joined(separator: ","))
        }
        lines.append("Total,,,\(String(format: "%.2f", breakdown.totalHours)),,\(String(format: "%.2f", breakdown.totalAmount * multiplier))")
        return lines.joined(separator: "\n") + "\n"
    }

    public static func markdown(
        month: String,
        breakdown: PayBreakdown,
        config: PayConfig,
        displayCurrency: String
    ) -> String {
        let multiplier = config.displayMultiplier(for: displayCurrency)
        var lines = [
            "# Shiftly Payslip — \(month)",
            "",
            "Currency: \(displayCurrency)"
                + (displayCurrency == config.base_currency
                    ? ""
                    : " (converted from \(config.base_currency) × \(String(format: "%.4g", multiplier)))"),
            "",
            "| Date | Start | End | Hours | Rate | Amount |",
            "|------|-------|-----|------:|-----:|-------:|",
        ]
        for item in breakdown.items {
            let rate = item.hourlyRate.map { String(format: "%.2f", $0 * multiplier) } ?? "—"
            lines.append("| \(item.date) | \(SyncFingerprint.hhmmString(for: item.start)) | \(SyncFingerprint.hhmmString(for: item.end)) | \(String(format: "%.2f", item.hours)) | \(rate) | \(String(format: "%.2f", item.amount * multiplier)) |")
        }
        lines.append("| **Total** | | | **\(String(format: "%.2f", breakdown.totalHours))** | | **\(String(format: "%.2f", breakdown.totalAmount * multiplier))** |")
        if breakdown.hasUnratedShifts {
            lines.append("")
            lines.append("Shifts marked — predate the first rate segment and count as 0.")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
