import Foundation

nonisolated struct CallerIdentity: Hashable, Sendable {
    var account: String
    var arn: String

    /// `arn:aws:iam::123456789012:user/ops/jan` → `jan`.
    var userName: String {
        arn.hasSuffix(":root") ? "root" : String(arn.split(separator: "/").last ?? "")
    }
}

nonisolated enum AWSError: LocalizedError {
    case service(code: String, message: String)
    case unexpectedResponse(String)
    case missingSecret
    case incompleteAccount(String)

    var errorDescription: String? {
        switch self {
        case let .service(code, message):
            let hint: String? = switch code {
            case "InvalidClientTokenId": String(localized: "The access key is invalid or has been deactivated.")
            case "SignatureDoesNotMatch": String(localized: "The Secret Access Key doesn't match the Access Key ID.")
            case "AccessDenied": String(localized: "The IAM user isn't allowed to perform this operation. Signing in with keys requires sts:GetFederationToken.")
            default: nil
            }
            return [hint, message.isEmpty ? code : "\(code): \(message)"].compactMap(\.self).joined(separator: "\n\n")
        case let .unexpectedResponse(details):
            return String(localized: "Unexpected AWS response: \(details)")
        case .missingSecret:
            return String(localized: "The Secret Access Key is missing from the Keychain. Edit the account and enter it again.")
        case let .incompleteAccount(details):
            return details
        }
    }
}

/// Minimal AWS STS client (Query API) – only what console sign-in needs.
nonisolated struct STSClient: Sendable {
    var credentials: AWSCredentials
    var region = "us-east-1"

    private var endpoint: URL { URL(string: "https://sts.\(region).amazonaws.com/")! }

    func callerIdentity() async throws -> CallerIdentity {
        let fields = try await call("GetCallerIdentity")
        guard let account = fields["Account"], let arn = fields["Arn"] else {
            throw AWSError.unexpectedResponse("GetCallerIdentity without Account/Arn")
        }
        return CallerIdentity(account: account, arn: arn)
    }

    /// Temporary credentials for the console. The AdministratorAccess session policy doesn't widen anything:
    /// the session gets the intersection with the IAM user's policies, i.e. exactly the user's permissions.
    func federationToken(name: String, durationSeconds: Int) async throws -> AWSCredentials {
        let fields = try await call("GetFederationToken", [
            ("Name", name),
            ("DurationSeconds", String(durationSeconds)),
            ("PolicyArns.member.1.arn", "arn:aws:iam::aws:policy/AdministratorAccess"),
        ])
        guard let keyId = fields["AccessKeyId"], let secret = fields["SecretAccessKey"], let token = fields["SessionToken"] else {
            throw AWSError.unexpectedResponse("GetFederationToken without session credentials")
        }
        return AWSCredentials(accessKeyId: keyId, secretAccessKey: secret, sessionToken: token)
    }

    /// Temporary credentials for the CLI/SDKs – the user's full permissions except the IAM API (which requires MFA).
    func sessionToken(durationSeconds: Int) async throws -> AWSCredentials {
        let fields = try await call("GetSessionToken", [("DurationSeconds", String(durationSeconds))])
        guard let keyId = fields["AccessKeyId"], let secret = fields["SecretAccessKey"], let token = fields["SessionToken"] else {
            throw AWSError.unexpectedResponse("GetSessionToken without session credentials")
        }
        return AWSCredentials(accessKeyId: keyId, secretAccessKey: secret, sessionToken: token)
    }

    private func call(_ action: String, _ parameters: [(String, String)] = []) async throws -> [String: String] {
        let body = Data(percentEncodedQuery([("Action", action), ("Version", "2011-06-15")] + parameters).utf8)
        let headers = ["Content-Type": "application/x-www-form-urlencoded; charset=utf-8"]
        let signature = SigV4.authorizationHeaders(
            method: "POST", url: endpoint, headers: headers, body: body,
            credentials: credentials, region: region, service: "sts"
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = body
        for (name, value) in headers.merging(signature, uniquingKeysWith: { $1 }) {
            request.setValue(value, forHTTPHeaderField: name)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let fields = XMLFields.parse(data)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw AWSError.service(code: fields["Code"] ?? "HTTP \(status)", message: fields["Message"] ?? "")
        }
        return fields
    }
}

/// Flattens an XML response into an "element name → text" dictionary (the first occurrence wins).
/// STS responses have unique leaf names, so that is all we need.
private nonisolated final class XMLFields: NSObject, XMLParserDelegate {
    private var fields: [String: String] = [:]
    private var text = ""

    static func parse(_ data: Data) -> [String: String] {
        let collector = XMLFields()
        let parser = XMLParser(data: data)
        parser.delegate = collector
        parser.parse()
        return collector.fields
    }

    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
        qualifiedName: String?, attributes: [String: String] = [:]
    ) {
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        let value = text.trimmed
        if !value.isEmpty, fields[elementName] == nil {
            fields[elementName] = value
        }
        text = ""
    }
}
