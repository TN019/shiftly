import ShiftlyKit
import SwiftUI

let displayCurrencies = ["AUD", "CNY", "USD"]

extension ContentView {
    @ViewBuilder
    var paySection: some View {
        if let config = model.payConfig {
            payMonthCard(config)
            payChartCard(config)
            payDrilldownCard(config)
            payRatesCard(config)
            payExchangeCard(config)
        } else {
            paySetupCard
        }
    }

    // MARK: Setup

    private var paySetupCard: some View {
        card("Pay Setup") {
            Text("Set your hourly rate to start tracking earnings. Casual flat rate: pay = hours × rate; the rate history keeps past months correct after a raise.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Currency").font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: $paySetupCurrency) {
                        ForEach(displayCurrencies, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 90)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hourly rate").font(.caption).foregroundStyle(.secondary)
                    TextField("32.50", text: $paySetupHourly)
                        .frame(width: 80)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Effective From").font(.caption).foregroundStyle(.secondary)
                    styledDatePicker($paySetupDate)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(" ").font(.caption)
                    Button("Start Tracking") {
                        if let hourly = Double(paySetupHourly), hourly > 0 {
                            model.createPayConfig(
                                baseCurrency: paySetupCurrency,
                                hourly: hourly,
                                effectiveFrom: ContentView.ymdString(paySetupDate)
                            )
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(Double(paySetupHourly) == nil)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Current month

    @ViewBuilder
    private func payMonthCard(_ config: PayConfig) -> some View {
        card("") {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("This month")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(Date().formatted(.dateTime.year().month(.wide)))
                        .font(.title3.weight(.semibold))
                }
                Spacer(minLength: 0)
                Picker("", selection: $payDisplayCurrency) {
                    ForEach(displayCurrencies, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 180)
            }
            if let breakdown = model.payCurrentMonth {
                HStack(spacing: 28) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Earnings").font(.caption).foregroundStyle(.secondary)
                        Text(payAmountText(breakdown.totalAmount, config: config))
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .monospacedDigit()
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hours").font(.caption).foregroundStyle(.secondary)
                        Text(String(format: "%.1f h", breakdown.totalHours))
                            .font(.system(.title2, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Shifts").font(.caption).foregroundStyle(.secondary)
                        Text("\(breakdown.items.count)")
                            .font(.system(.title2, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Year to date").font(.caption).foregroundStyle(.secondary)
                        Text(payAmountText(model.payYearToDate, config: config))
                            .font(.system(.title2, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                    }
                    Spacer(minLength: 0)
                }
                if breakdown.hasUnratedShifts {
                    Text("Some shifts predate the first rate segment and count as 0 — add an earlier rate to include them.")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                if payDisplayCurrency != config.base_currency {
                    Text("Converted from \(config.base_currency) at a manually set rate (edit below).")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } else {
                Text("Calculating…")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: Rates

    @ViewBuilder
    private func payRatesCard(_ config: PayConfig) -> some View {
        card("Hourly Rates") {
            ForEach(config.rates.sorted { $0.effective_from > $1.effective_from }, id: \.effective_from) { rate in
                HStack(spacing: 10) {
                    Text(rate.effective_from)
                        .font(.system(.subheadline, design: .monospaced))
                    Text("\(config.base_currency) \(String(format: "%.2f", rate.hourly)) / h")
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()
                    Spacer(minLength: 0)
                    if rate.effective_from == config.rates.map(\.effective_from).max() {
                        Text("Current")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                }
                .padding(.vertical, 5)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
            }
            HStack(spacing: 10) {
                Text("New rate").font(.caption).foregroundStyle(.secondary)
                TextField("35.00", text: $payNewRate)
                    .frame(width: 80)
                styledDatePicker($payNewRateDate)
                Button("Add") {
                    if let hourly = Double(payNewRate), hourly > 0 {
                        model.addPayRate(hourly: hourly, effectiveFrom: ContentView.ymdString(payNewRateDate))
                        payNewRate = ""
                    }
                }
                .buttonStyle(.bordered)
                .disabled(Double(payNewRate) == nil)
                Spacer(minLength: 0)
            }
            Text("A raise is a new segment; earlier months keep using the rate that applied back then.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: Exchange rates

    @ViewBuilder
    private func payExchangeCard(_ config: PayConfig) -> some View {
        card("Exchange Rates") {
            Text("Manual multipliers from \(config.base_currency) for the display switcher (local only, never fetched).")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 14) {
                ForEach(displayCurrencies.filter { $0 != config.base_currency }, id: \.self) { currency in
                    HStack(spacing: 6) {
                        Text("1 \(config.base_currency) =")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("1.0", text: exchangeBinding(currency))
                            .frame(width: 64)
                        Text(currency)
                            .font(.caption.weight(.semibold))
                    }
                }
                Button("Save") {
                    var rates = config.display_rates
                    for (currency, text) in payExchangeEdits {
                        if let value = Double(text), value > 0 {
                            rates[currency] = value
                        }
                    }
                    model.updateDisplayRates(rates)
                    payExchangeEdits = [:]
                }
                .buttonStyle(.bordered)
                .disabled(payExchangeEdits.isEmpty)
                Spacer(minLength: 0)
            }
        }
    }

    private func exchangeBinding(_ currency: String) -> Binding<String> {
        Binding(
            get: {
                payExchangeEdits[currency]
                    ?? model.payConfig.map { String(format: "%.4g", $0.displayMultiplier(for: currency)) }
                    ?? ""
            },
            set: { payExchangeEdits[currency] = $0 }
        )
    }

    func payAmountText(_ baseAmount: Double, config: PayConfig) -> String {
        let amount = baseAmount * config.displayMultiplier(for: payDisplayCurrency)
        return amount.formatted(.currency(code: payDisplayCurrency).presentation(.narrow))
    }
}
