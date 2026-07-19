import Foundation

/// Money earned by one shift.
public struct ShiftEarning: Equatable, Identifiable {
    public var id: String { date }
    public let date: String
    public let start: Date
    public let end: Date
    public let hours: Double
    /// Hourly rate in the base currency; nil when the shift predates the
    /// first rate segment (earns 0, flagged in the breakdown).
    public let hourlyRate: Double?
    public let amount: Double
}

/// Earnings for a date range, in the base currency.
public struct PayBreakdown: Equatable {
    public var items: [ShiftEarning] = []
    public var totalHours: Double = 0
    public var totalAmount: Double = 0
    /// True when some shifts predate the first rate segment.
    public var hasUnratedShifts = false

    public init() {}
}

/// Pure earnings math over engine-solved shifts (casual flat rate).
///
/// - Hours come from the real start/end instants, so overnight shifts count
///   in full; a shift is attributed to its start day (`PlannedShift.date`).
/// - The rate segment with the latest effective_from on or before the
///   shift's date applies; shifts before the first segment earn 0 and set
///   `hasUnratedShifts`.
public enum PayEngine {
    public static func breakdown(shifts: [PlannedShift], config: PayConfig) -> PayBreakdown {
        var result = PayBreakdown()
        for shift in shifts.sorted(by: { $0.date < $1.date }) {
            let span = shift.end.timeIntervalSince(shift.start) / 3600
            // Paid hours: the unpaid break comes off every shift, but a
            // shift shorter than the break just pays nothing extra-negative.
            let hours = max(0, span - Double(config.unpaid_break_minutes) / 60)
            let rate = config.hourlyRate(on: shift.date)
            let amount = (rate ?? 0) * hours
            if rate == nil {
                result.hasUnratedShifts = true
            }
            result.items.append(ShiftEarning(
                date: shift.date,
                start: shift.start,
                end: shift.end,
                hours: hours,
                hourlyRate: rate,
                amount: amount
            ))
            result.totalHours += hours
            result.totalAmount += amount
        }
        return result
    }

    /// Month key ("YYYY-MM") → breakdown, for charts and drill-down.
    public static func byMonth(shifts: [PlannedShift], config: PayConfig) -> [String: PayBreakdown] {
        let grouped = Dictionary(grouping: shifts) { String($0.date.prefix(7)) }
        return grouped.mapValues { breakdown(shifts: $0, config: config) }
    }
}
