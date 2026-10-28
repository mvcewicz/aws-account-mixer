import Foundation

nonisolated struct DailyCost: Codable, Hashable, Sendable {
    /// `yyyy-MM-dd` (UTC), as returned by Cost Explorer.
    var day: String
    var amount: Double

    var date: Date { (try? Date(day, strategy: .iso8601.year().month().day())) ?? .distantPast }
}

/// Minimal AWS Cost Explorer client (JSON 1.1 protocol). Every call costs USD 0.01.
nonisolated struct CostExplorerClient: Sendable {
    var credentials: AWSCredentials

    private static let endpoint = URL(string: "https://ce.us-east-1.amazonaws.com/")!

    /// Daily costs (UnblendedCost) of the account in [start, end).
    func dailyCosts(accountId: String, start: String, end: String) async throws -> (currency: String, days: [DailyCost]) {
        struct Response: Decodable {
            struct Result: Decodable {
                struct Period: Decodable { var start: String }
                struct Metric: Decodable { var amount: String; var unit: String }
                var timePeriod: Period
                var total: [String: Metric]
            }
            var resultsByTime: [Result]
            var nextPageToken: String?
        }

        var currency = "USD"
        var days: [DailyCost] = []
        var pageToken: String?
        repeat {
            var body: [String: Any] = [
                "TimePeriod": ["Start": start, "End": end],
                "Granularity": "DAILY",
                "Metrics": ["UnblendedCost"],
                "Filter": Self.accountFilter(accountId),
            ]
            body["NextPageToken"] = pageToken
            let response: Response = try await call("GetCostAndUsage", body)
            for result in response.resultsByTime {
                // We ask for one metric; dictionary keys also go through the key strategy, so don't look it up by name.
                let metric = result.total.values.first
                currency = metric?.unit ?? currency
                days.append(DailyCost(day: result.timePeriod.start, amount: Double(metric?.amount ?? "") ?? 0))
            }
            pageToken = response.nextPageToken
        } while pageToken != nil
        return (currency, days)
    }

    /// Forecast for [start, end); start can't be earlier than today.
    /// For the current month AWS returns the whole month's total (including costs already incurred).
    func forecast(accountId: String, start: String, end: String) async throws -> Double {
        struct Response: Decodable {
            struct Total: Decodable { var amount: String }
            var total: Total
        }
        let response: Response = try await call("GetCostForecast", [
            "TimePeriod": ["Start": start, "End": end],
            "Metric": "UNBLENDED_COST",
            "Granularity": "MONTHLY",
            "Filter": Self.accountFilter(accountId),
        ])
        return Double(response.total.amount) ?? 0
    }

    /// Without the filter an organization's management account would return costs of all accounts – count only this one.
    private static func accountFilter(_ accountId: String) -> [String: Any] {
        ["Dimensions": ["Key": "LINKED_ACCOUNT", "Values": [accountId]]]
    }

    private func call<Response: Decodable>(_ operation: String, _ body: [String: Any]) async throws -> Response {
        let data = try JSONSerialization.data(withJSONObject: body)
        let headers = [
            "Content-Type": "application/x-amz-json-1.1",
            "X-Amz-Target": "AWSInsightsIndexService.\(operation)",
        ]
        let signature = SigV4.authorizationHeaders(
            method: "POST", url: Self.endpoint, headers: headers, body: data,
            credentials: credentials, region: "us-east-1", service: "ce"
        )

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.httpBody = data
        for (name, value) in headers.merging(signature, uniquingKeysWith: { $1 }) {
            request.setValue(value, forHTTPHeaderField: name)
        }

        let (responseData, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let error = try? JSONDecoder().decode(ErrorBody.self, from: responseData)
            let code = error?.type?.split(separator: "#").last.map(String.init) ?? "HTTP \(status)"
            throw AWSError.service(code: code, message: error?.message ?? "")
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .custom { path in
            // Cost Explorer uses PascalCase – lowercase the first letter.
            let key = path.last!.stringValue
            return LowercasedKey(stringValue: key.prefix(1).lowercased() + key.dropFirst())
        }
        return try decoder.decode(Response.self, from: responseData)
    }
}

private nonisolated struct ErrorBody: Decodable {
    var type: String?
    var message: String?
    enum CodingKeys: String, CodingKey { case type = "__type", message = "Message" }
}

private nonisolated struct LowercasedKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}
