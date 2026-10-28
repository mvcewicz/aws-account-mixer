import Foundation
import Testing
@testable import AWSAccountMixer

/// Real AWS calls with the keys in ~/.aws. Disabled by default:
/// `AWS_MIXER_LIVE=1 swift test --filter LiveSTSTests`
@Suite(.enabled(if: ProcessInfo.processInfo.environment["AWS_MIXER_LIVE"] == "1"))
struct LiveSTSTests {
    /// For every key: GetCallerIdentity + GetFederationToken. Prints only the account ID, user and result – no secrets.
    @Test func everyKeyCanFederate() async throws {
        let profiles = CredentialsFile.scan()
        try #require(!profiles.isEmpty)
        for profile in profiles {
            let sts = STSClient(credentials: profile.credentials)
            do {
                let identity = try await sts.callerIdentity()
                let session = try await sts.federationToken(name: "aws-account-mixer-test", durationSeconds: 900)
                print("OK   \(profile.suggestedName) \(identity.account) \(identity.userName) session=\(session.sessionToken != nil)")
            } catch {
                print("FAIL \(profile.suggestedName): \(error.localizedDescription.replacingOccurrences(of: "\n", with: " "))")
            }
        }
    }

    @Test func producesConsoleLoginURL() async throws {
        let profile = try #require(CredentialsFile.scan().first)
        let session = try await STSClient(credentials: profile.credentials)
            .federationToken(name: "aws-account-mixer-test", durationSeconds: 900)
        let url = try await ConsoleSignIn.federatedURL(credentials: session, destination: ConsoleService.home.url(region: "eu-central-1"))
        #expect(url.host() == "signin.aws.amazon.com")
        #expect(url.query()?.contains("SigninToken=") == true)
    }
}

/// Cost Explorer with the first key – 2 requests = USD 0.02. `AWS_MIXER_LIVE_COSTS=1 swift test --filter LiveCostTests`
@Suite(.enabled(if: ProcessInfo.processInfo.environment["AWS_MIXER_LIVE_COSTS"] == "1"))
struct LiveCostTests {
    @Test func fetchesCostsAndForecast() async throws {
        let profile = try #require(CredentialsFile.scan().first)
        let identity = try await STSClient(credentials: profile.credentials).callerIdentity()
        let client = CostExplorerClient(credentials: profile.credentials)
        let days = BillingDays(now: .now)
        let costs = try await client.dailyCosts(accountId: identity.account, start: days.previousMonthStart, end: days.tomorrow)
        let total = costs.days.reduce(0) { $0 + $1.amount }
        print("COSTS \(identity.account) days=\(costs.days.count) first=\(costs.days.first?.day ?? "-") last=\(costs.days.last?.day ?? "-") total=\(total) \(costs.currency)")
        do {
            let forecast = try await client.forecast(accountId: identity.account, start: days.today, end: days.nextMonthStart)
            print("FORECAST remaining=\(forecast)")
        } catch {
            print("FORECAST error: \(error.localizedDescription)")
        }
        #expect(costs.days.count >= 28)
    }
}
