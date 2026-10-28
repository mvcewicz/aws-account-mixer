import Foundation

/// AWS console links for each sign-in method.
nonisolated enum ConsoleSignIn {
    private static let federationEndpoint = URL(string: "https://signin.aws.amazon.com/federation")!

    /// Exchanges temporary credentials for a one-time sign-in link (valid for 15 minutes).
    /// https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_enable-console-custom-url.html
    static func federatedURL(credentials: AWSCredentials, destination: URL) async throws -> URL {
        struct Session: Encodable {
            var sessionId: String
            var sessionKey: String
            var sessionToken: String
        }
        struct TokenResponse: Decodable {
            var signinToken: String
            enum CodingKeys: String, CodingKey { case signinToken = "SigninToken" }
        }

        let session = try JSONEncoder().encode(Session(
            sessionId: credentials.accessKeyId,
            sessionKey: credentials.secretAccessKey,
            sessionToken: credentials.sessionToken ?? ""
        ))
        let tokenURL = url(federationEndpoint, query: [
            ("Action", "getSigninToken"),
            ("Session", String(decoding: session, as: UTF8.self)),
        ])
        let (data, response) = try await URLSession.shared.data(from: tokenURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let token = try? JSONDecoder().decode(TokenResponse.self, from: data)
        else {
            throw AWSError.unexpectedResponse(String(localized: "the sign-in endpoint rejected the federation credentials"))
        }

        return url(federationEndpoint, query: [
            ("Action", "login"),
            ("Issuer", "aws-account-mixer"),
            ("Destination", destination.absoluteString),
            ("SigninToken", token.signinToken),
        ])
    }

    static func signInPageURL(accountId: String) -> URL {
        URL(string: "https://\(accountId.rfc3986Encoded).signin.aws.amazon.com/console")!
    }

    static func switchRoleURL(accountId: String, roleName: String, displayName: String, color: AccountColor, destination: URL) -> URL {
        url(URL(string: "https://signin.aws.amazon.com/switchrole")!, query: [
            ("account", accountId),
            ("roleName", roleName),
            ("displayName", String(displayName.prefix(64))),
            ("color", color.switchRoleHex),
            ("redirect_uri", destination.absoluteString),
        ])
    }

    /// Federated session name shown in the console – AWS accepts 2–32 characters `[\w+=,.@-]`.
    static func federatedUserName(_ preferred: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+=,.@_-")
        let name = String(String.UnicodeScalarView(preferred.unicodeScalars.filter(allowed.contains).prefix(32)))
        return name.count >= 2 ? name : "aws-account-mixer"
    }

    private static func url(_ base: URL, query: [(String, String)]) -> URL {
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        components.percentEncodedQuery = percentEncodedQuery(query)
        return components.url!
    }
}
