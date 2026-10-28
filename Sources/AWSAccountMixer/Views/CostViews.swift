import Charts
import SwiftUI

extension Double {
    func cost(_ currency: String, compact: Bool = false) -> String {
        formatted(.currency(code: currency).precision(.fractionLength(compact && self >= 100 ? 0 : 2)))
    }
}

/// Cost in an account row: month to date + forecast. Clicking opens the details.
struct CostSummary: View {
    let account: Account
    @Environment(CostStore.self) private var costs
    @State private var showsDetail = false

    var body: some View {
        if let report = costs.report(for: account) {
            Button {
                showsDetail = true
            } label: {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(report.monthToDate.cost(report.currency, compact: true))
                        .font(.callout.weight(.medium))
                    if let forecast = report.forecastMonthEnd {
                        Text(verbatim: "→ \(forecast.cost(report.currency, compact: true))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .monospacedDigit()
                .opacity(costs.isLoading(account) ? 0.4 : 1)
            }
            .buttonStyle(.plain)
            .help("Month to date and month-end forecast – click for details")
            .popover(isPresented: $showsDetail, arrowEdge: .bottom) {
                CostDetailView(account: account, report: report)
            }
        } else if costs.isLoading(account) {
            ProgressView().controlSize(.small)
        } else if let error = costs.error(for: account) {
            Image(systemName: "dollarsign.circle")
                .foregroundStyle(.orange)
                .help("Couldn't fetch costs:\n\(error)")
        }
    }
}

struct CostDetailView: View {
    let account: Account
    let report: CostReport
    @Environment(CostStore.self) private var costs
    @Environment(ConsoleLauncher.self) private var launcher

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                AccountBadge(account: account, size: 22)
                Text(account.name).font(.headline)
                Spacer()
            }

            Grid(alignment: .topLeading, horizontalSpacing: 24, verticalSpacing: 6) {
                GridRow {
                    figure("Last month", report.previousMonth)
                    figure("This month", report.monthToDate)
                    if let forecast = report.forecastMonthEnd {
                        VStack(alignment: .leading, spacing: 2) {
                            figure("Forecast", forecast)
                            if report.previousMonth > 0 {
                                let change = forecast / report.previousMonth - 1
                                Text("\(change >= 0 ? "▲" : "▼") \(abs(change).formatted(.percent.precision(.fractionLength(0)))) vs last month")
                                    .font(.caption)
                                    .foregroundStyle(change > 0.1 ? .red : .secondary)
                            }
                        }
                    }
                }
            }

            Chart(report.daily, id: \.day) { day in
                BarMark(x: .value("Day", day.date, unit: .day), y: .value("Cost", day.amount))
                    .foregroundStyle(day.day.hasPrefix(String(report.daily.last?.day.prefix(7) ?? "")) ? account.color.color : Color.secondary.opacity(0.4))
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel { Text((value.as(Double.self) ?? 0).formatted(.currency(code: report.currency).precision(.fractionLength(0)))) }
                }
            }
            .frame(height: 140)

            HStack {
                Text("Updated \(report.fetchedAt.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Billing") { launcher.open(account, at: .billing) }
                Button("Refresh", systemImage: "arrow.clockwise") { costs.refresh([account]) }
                    .disabled(costs.isLoading(account))
            }
            Text("Cost Explorer data (UnblendedCost); AWS updates it a few times a day. Each refresh is 2 requests at USD 0.01 each.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(width: 420)
    }

    private func figure(_ title: LocalizedStringKey, _ amount: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(amount.cost(report.currency)).font(.title3.weight(.semibold)).monospacedDigit()
        }
    }
}

/// Bar at the bottom of the list: totals for the visible accounts.
struct CostTotalsBar: View {
    let accounts: [Account]
    @Environment(CostStore.self) private var costs

    var body: some View {
        if let totals = costs.totals(for: accounts) {
            HStack(spacing: 16) {
                Label("This month: \(totals.monthToDate.cost(totals.currency))", systemImage: "dollarsign.circle")
                Text("Forecast: \(totals.forecast.cost(totals.currency))")
                    .foregroundStyle(.secondary)
                Spacer()
                if !costs.loading.isEmpty {
                    ProgressView().controlSize(.small)
                }
                Button("Refresh Costs", systemImage: "arrow.clockwise") { costs.refresh() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .disabled(!costs.loading.isEmpty)
                    .help("Refresh costs for all accounts (2 requests at USD 0.01 per account)")
            }
            .font(.callout)
            .monospacedDigit()
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }
}
