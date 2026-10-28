import Foundation

/// A key found in `~/.aws/credentials*` files. The same key in several files is one profile with several sources.
nonisolated struct CredentialProfile: Identifiable, Hashable, Sendable {
    struct Source: Hashable, Sendable {
        var file: String
        var profile: String

        /// `credentials.staging` → `staging`.
        var fileSuffix: String? {
            file.hasPrefix("credentials.") ? String(file.dropFirst("credentials.".count)) : nil
        }
    }

    var accessKeyId: String
    var secretAccessKey: String
    var sources: [Source]

    var id: String { accessKeyId }

    var credentials: AWSCredentials {
        AWSCredentials(accessKeyId: accessKeyId, secretAccessKey: secretAccessKey)
    }

    /// The most descriptive name: the profile name or, for a plain `[default]`, the file suffix.
    var suggestedName: String {
        if let named = sources.first(where: { $0.profile != "default" }) { return named.profile }
        if let suffix = sources.compactMap(\.fileSuffix).first(where: { $0 != "backup" }) { return suffix }
        return "default"
    }

    var maskedAccessKeyId: String {
        accessKeyId.count > 8 ? "\(accessKeyId.prefix(4))••••\(accessKeyId.suffix(4))" : accessKeyId
    }
}

nonisolated enum CredentialsFile {
    static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".aws")
    }

    /// Unique (by Access Key ID) keys from `credentials` and `credentials.*`. Temporary credentials (with a session token) are skipped.
    static func scan(directory: URL = defaultDirectory) -> [CredentialProfile] {
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .filter { $0 == "credentials" || $0.hasPrefix("credentials.") }
            .sorted { ($0 == "credentials" ? 0 : 1, $0) < ($1 == "credentials" ? 0 : 1, $1) }

        var profiles: [CredentialProfile] = []
        for file in files {
            guard let text = try? String(contentsOf: directory.appending(path: file), encoding: .utf8) else { continue }
            for section in parse(text) {
                guard let keyId = section.values["aws_access_key_id"],
                      let secret = section.values["aws_secret_access_key"],
                      section.values["aws_session_token"] == nil
                else { continue }
                let source = CredentialProfile.Source(file: file, profile: section.name)
                if let index = profiles.firstIndex(where: { $0.accessKeyId == keyId }) {
                    profiles[index].sources.append(source)
                } else {
                    profiles.append(CredentialProfile(accessKeyId: keyId, secretAccessKey: secret, sources: [source]))
                }
            }
        }
        return profiles
    }

    /// Minimal INI parser for AWS CLI files.
    static func parse(_ text: String) -> [(name: String, values: [String: String])] {
        var sections: [(name: String, values: [String: String])] = []
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = String(rawLine).trimmed
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") { continue }
            if line.hasPrefix("["), line.hasSuffix("]") {
                sections.append((name: String(line.dropFirst().dropLast()).trimmed, values: [:]))
            } else if let equals = line.firstIndex(of: "="), !sections.isEmpty {
                let key = String(line[..<equals]).trimmed.lowercased()
                sections[sections.count - 1].values[key] = String(line[line.index(after: equals)...]).trimmed
            }
        }
        return sections
    }
}
