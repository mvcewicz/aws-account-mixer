import CryptoKit
import Foundation

nonisolated struct AWSCredentials: Hashable, Sendable {
    var accessKeyId: String
    var secretAccessKey: String
    var sessionToken: String?
}

/// AWS Signature Version 4 request signing.
/// https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_sigv-create-signed-request.html
nonisolated enum SigV4 {
    /// Headers to add to the request: `X-Amz-Date`, `Authorization` and, if needed, `X-Amz-Security-Token`.
    /// `headers` are the headers the request already has and that should be signed (`Host` is added automatically).
    static func authorizationHeaders(
        method: String,
        url: URL,
        headers: [String: String],
        body: Data,
        credentials: AWSCredentials,
        region: String,
        service: String,
        date: Date = .now
    ) -> [String: String] {
        let amzDate = timestamp(date)
        let dateStamp = String(amzDate.prefix(8))

        var headersToSign = headers
        headersToSign["Host"] = url.host() ?? ""
        headersToSign["X-Amz-Date"] = amzDate
        headersToSign["X-Amz-Security-Token"] = credentials.sessionToken

        let canonicalHeaders = headersToSign
            .map { (name: $0.key.lowercased(), value: $0.value.trimmed) }
            .sorted { $0.name < $1.name }
        let signedHeaders = canonicalHeaders.map(\.name).joined(separator: ";")

        let canonicalRequest = [
            method,
            canonicalPath(url),
            canonicalQuery(url),
            canonicalHeaders.map { "\($0.name):\($0.value)\n" }.joined(),
            signedHeaders,
            hex(SHA256.hash(data: body)),
        ].joined(separator: "\n")

        let scope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        let stringToSign = [
            "AWS4-HMAC-SHA256",
            amzDate,
            scope,
            hex(SHA256.hash(data: Data(canonicalRequest.utf8))),
        ].joined(separator: "\n")

        var signingKey = SymmetricKey(data: Data("AWS4\(credentials.secretAccessKey)".utf8))
        for component in [dateStamp, region, service, "aws4_request"] {
            signingKey = SymmetricKey(data: HMAC<SHA256>.authenticationCode(for: Data(component.utf8), using: signingKey))
        }
        let signature = hex(HMAC<SHA256>.authenticationCode(for: Data(stringToSign.utf8), using: signingKey))

        var result = [
            "X-Amz-Date": amzDate,
            "Authorization": "AWS4-HMAC-SHA256 Credential=\(credentials.accessKeyId)/\(scope), "
                + "SignedHeaders=\(signedHeaders), Signature=\(signature)",
        ]
        result["X-Amz-Security-Token"] = credentials.sessionToken
        return result
    }

    private static func timestamp(_ date: Date) -> String {
        let utc = Calendar(identifier: .gregorian).dateComponents(in: .gmt, from: date)
        return String(
            format: "%04d%02d%02dT%02d%02d%02dZ",
            utc.year!, utc.month!, utc.day!, utc.hour!, utc.minute!, utc.second!
        )
    }

    private static func canonicalPath(_ url: URL) -> String {
        let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? ""
        return path.isEmpty ? "/" : path
    }

    private static func canonicalQuery(_ url: URL) -> String {
        guard let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery else { return "" }
        return query.split(separator: "&")
            .map { pair -> (String, String) in
                let parts = pair.split(separator: "=", maxSplits: 1)
                return (String(parts[0]), parts.count > 1 ? String(parts[1]) : "")
            }
            .sorted { $0 < $1 }
            .map { "\($0.0)=\($0.1)" }
            .joined(separator: "&")
    }

    private static func hex(_ bytes: some Sequence<UInt8>) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}
