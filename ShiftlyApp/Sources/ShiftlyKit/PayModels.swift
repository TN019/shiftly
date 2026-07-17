import Foundation

/// One hourly-rate segment; the rate with the latest effective_from on or
/// before a shift's date applies.
public struct PayRate: Codable, Equatable {
    public var effective_from: String
    public var hourly: Double

    public init(effective_from: String, hourly: Double) {
        self.effective_from = effective_from
        self.hourly = hourly
    }
}

/// data/pay.json — casual flat-rate model (no overtime, no allowances;
/// those stay as future schema extensions). Amounts are kept in
/// `base_currency`; `display_rates` are user-maintained multipliers for
/// switching the display currency (local-first: no network rates).
public struct PayConfig: Codable, Equatable {
    public var version: Int
    public var base_currency: String
    public var rates: [PayRate]
    public var display_rates: [String: Double]

    public init(
        version: Int = 1,
        base_currency: String = "AUD",
        rates: [PayRate] = [],
        display_rates: [String: Double] = ["AUD": 1.0, "CNY": 4.7, "USD": 0.66]
    ) {
        self.version = version
        self.base_currency = base_currency
        self.rates = rates
        self.display_rates = display_rates
    }

    /// The hourly rate applicable on a date, nil before the first segment.
    public func hourlyRate(on date: String) -> Double? {
        rates
            .filter { $0.effective_from <= date }
            .max { $0.effective_from < $1.effective_from }?
            .hourly
    }

    /// Multiplier from base currency to a display currency (1.0 for base
    /// or unknown currencies).
    public func displayMultiplier(for currency: String) -> Double {
        if currency == base_currency { return 1.0 }
        return display_rates[currency] ?? 1.0
    }
}

extension ShiftlyPaths {
    public var payConfigPath: String { "\(root)/data/pay.json" }
}

extension DataStore {
    /// nil = not configured yet (the Pay page shows setup guidance).
    public func loadPayConfig() -> PayConfig? {
        guard let data = FileManager.default.contents(atPath: paths.payConfigPath) else { return nil }
        return try? JSONDecoder().decode(PayConfig.self, from: data)
    }

    public func savePayConfig(_ config: PayConfig) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(config).write(
            to: URL(fileURLWithPath: paths.payConfigPath), options: .atomic
        )
    }
}
