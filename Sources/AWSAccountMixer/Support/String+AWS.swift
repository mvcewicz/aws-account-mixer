import Foundation

nonisolated extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    /// RFC 3986 encoding required by AWS – only unreserved characters stay as they are.
    /// (`URLQueryItem` would leave e.g. `+` alone, which the server reads as a space.)
    var rfc3986Encoded: String {
        addingPercentEncoding(withAllowedCharacters: .rfc3986Unreserved) ?? self
    }

    /// "1234-5678-9012" → "123456789012"; account aliases stay unchanged.
    var normalizedAccountId: String {
        let compact = trimmed.filter { $0 != "-" && $0 != " " }
        return compact.count == 12 && compact.allSatisfy { $0.isASCII && $0.isNumber } ? compact : trimmed
    }
}

nonisolated extension CharacterSet {
    static let rfc3986Unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~"
    )
}

nonisolated func percentEncodedQuery(_ parameters: [(String, String)]) -> String {
    parameters.map { "\($0.0.rfc3986Encoded)=\($0.1.rfc3986Encoded)" }.joined(separator: "&")
}
