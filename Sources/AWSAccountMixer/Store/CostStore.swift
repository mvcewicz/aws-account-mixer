import Foundation
import Observation

nonisolated struct CostReport: Codable, Hashable, Sendable {
    var accountId: String
    var currency: String
    var previousMonth: Double
    /// Since the start of the month, including today's partial day.
    var monthToDate: Double
    /// AWS forecast for the whole current month. `nil` when AWS doesn't have enough data to forecast yet.
    var forecastMonthEnd: Double?
    var daily: [DailyCost]
    var fetchedAt: Date
}

/// Cost Explorer costs, cached per AWS account ID in `costs.json` next to the account list.
/// Refreshing an account takes 2 requests at USD 0.01 each, so we refresh rarely.
@Observable
final class CostStore {
    private(set) var reports: [String: CostReport] = [:]
    private(set) var errors: [String: String] = [:]
    private(set) var loading: Set<String> = []
    @ObservationIgnored private let accountStore: AccountStore
    @ObservationIgnored private let fileURL: URL

    init(accountStore: AccountStore) {
        self.accountStore = accountStore
        fileURL = AccountStore.defaultFileURL.deletingLastPathComponent().appending(path: "costs.json")
        if let data = try? Data(contentsOf: fileURL), let saved = try? JSONDecoder().decode([String: CostReport].self, from: data) {
            reports = saved
        }
    }

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Preferences.showCosts) as? Bool ?? true
    }

    /// Only accounts with keys have costs (or another account with the same ID has keys).
    func report(for account: Account) -> CostReport? {
        reports[account.accountId]
    }

    func isLoading(_ account: Account) -> Bool { loading.contains(account.accountId) }

    func error(for account: Account) -> String? { errors[account.accountId] }

    /// Totals over unique account IDs – two keys for the same account count once.
    func totals(for accounts: [Account]) -> (monthToDate: Double, forecast: Double, currency: String)? {
        let unique = Set(accounts.map(\.accountId)).compactMap { reports[$0] }
        guard !unique.isEmpty else { return nil }
        return (
            unique.reduce(0) { $0 + $1.monthToDate },
            unique.reduce(0) { $0 + ($1.forecastMonthEnd ?? $1.monthToDate) },
            unique.first!.currency
        )
    }

    /// Checks every hour whether any account needs a refresh – for when the app runs for days.
    func startAutoRefresh() {
        Task {
            while true {
                refreshIfNeeded()
                try? await Task.sleep(for: .seconds(3600))
            }
        }
    }

    /// Refreshes accounts whose data is older than the configured interval (0 = manually only).
    func refreshIfNeeded() {
        let hours = UserDefaults.standard.object(forKey: Preferences.costRefreshHours) as? Int ?? Preferences.defaultCostRefreshHours
        guard Self.isEnabled, hours > 0 else { return }
        let stale = billableAccounts().filter { account in
            guard let report = reports[account.accountId] else { return errors[account.accountId] == nil }
            return Date.now.timeIntervalSince(report.fetchedAt) > Double(hours) * 3600
        }
        refresh(stale)
    }

    /// `accounts == nil` – all accounts with keys.
    func refresh(_ accounts: [Account]? = nil) {
        guard Self.isEnabled else { return }
        let ids = Set((accounts ?? billableAccounts()).map(\.accountId))
        for account in billableAccounts() where ids.contains(account.accountId) && !loading.contains(account.accountId) {
            loading.insert(account.accountId)
            Task {
                do {
                    reports[account.accountId] = try await fetch(account)
                    errors[account.accountId] = nil
                    persist()
                } catch {
                    errors[account.accountId] = error.localizedDescription
                }
                loading.remove(account.accountId)
            }
        }
    }

    /// One account with keys per AWS account ID.
    private func billableAccounts() -> [Account] {
        var seen = Set<String>()
        return accountStore.accounts.filter { account in
            account.method == .accessKeys && !account.accountId.isEmpty && seen.insert(account.accountId).inserted
        }
    }

    private func fetch(_ account: Account) async throws -> CostReport {
        let client = CostExplorerClient(credentials: try accountStore.credentials(for: account))
        let days = BillingDays(now: .now)

        let costs = try await client.dailyCosts(accountId: account.accountId, start: days.previousMonthStart, end: days.tomorrow)
        let previousMonth = costs.days.filter { $0.day.hasPrefix(days.previousMonthPrefix) }.reduce(0) { $0 + $1.amount }
        let monthToDate = costs.days.filter { $0.day.hasPrefix(days.currentMonthPrefix) }.reduce(0) { $0 + $1.amount }

        // With MONTHLY granularity AWS returns the whole month (costs through yesterday + the rest)
        // even though the period starts today – so don't add month-to-date costs a second time.
        let monthEnd = try? await client.forecast(accountId: account.accountId, start: days.today, end: days.nextMonthStart)

        return CostReport(
            accountId: account.accountId,
            currency: costs.currency,
            previousMonth: previousMonth,
            monthToDate: monthToDate,
            forecastMonthEnd: monthEnd,
            daily: costs.days,
            fetchedAt: .now
        )
    }

    private func persist() {
        try? JSONEncoder().encode(reports).write(to: fileURL, options: .atomic)
    }
}

/// Month boundaries in UTC – the time zone Cost Explorer counts days in.
nonisolated struct BillingDays {
    var today: String
    var tomorrow: String
    var previousMonthStart: String
    var nextMonthStart: String
    var currentMonthPrefix: String
    var previousMonthPrefix: String

    init(now: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let day = calendar.startOfDay(for: now)
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: day))!
        let previousMonth = calendar.date(byAdding: .month, value: -1, to: monthStart)!

        func format(_ date: Date) -> String {
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
        }

        today = format(day)
        tomorrow = format(calendar.date(byAdding: .day, value: 1, to: day)!)
        previousMonthStart = format(previousMonth)
        nextMonthStart = format(calendar.date(byAdding: .month, value: 1, to: monthStart)!)
        currentMonthPrefix = String(format(monthStart).prefix(7))
        previousMonthPrefix = String(previousMonthStart.prefix(7))
    }
}
