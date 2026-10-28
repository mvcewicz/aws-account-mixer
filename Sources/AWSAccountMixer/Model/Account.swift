import SwiftUI

/// An AWS account saved in the app. The Secret Access Key is stored separately in the Keychain.
nonisolated struct Account: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name = ""
    var group = ""
    var color = AccountColor.blue
    /// 12-digit account ID or account alias (an alias only works for the sign-in page).
    var accountId = ""
    /// Empty = the default region from Settings.
    var region = ""
    var method = LoginMethod.accessKeys
    var accessKeyId = ""
    var userName = ""
    var roleName = ""
    var isFavorite = false
    var notes = ""
    /// What a single click opens – the console home page or a specific service.
    var landingService = ConsoleService.home
    var lastOpenedAt: Date?

    var formattedAccountId: String {
        guard accountId.count == 12, accountId.allSatisfy(\.isNumber) else { return accountId }
        let digits = Array(accountId)
        return [digits[0..<4], digits[4..<8], digits[8..<12]].map { String($0) }.joined(separator: "-")
    }

    /// The account's own region or, when not set, the default from Settings (empty = last used in the console).
    func effectiveRegion(default defaultRegion: String) -> String {
        region.isEmpty ? defaultRegion : region
    }

    func subtitle(defaultRegion: String) -> String {
        let identity = method == .switchRole ? roleName : userName
        return [formattedAccountId, identity, effectiveRegion(default: defaultRegion)].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var initials: String {
        let words = name.split(whereSeparator: { " -_./".contains($0) })
        let letters = words.count > 1 ? words.prefix(2).compactMap(\.first) : Array(name.prefix(2))
        return String(letters).uppercased()
    }

    func matches(_ query: String) -> Bool {
        query.isEmpty || [name, group, accountId, userName, roleName, notes].contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

nonisolated extension Account {
    /// Missing fields fall back to defaults, so older accounts.json files still load after new fields are added.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) throws -> T {
            try container.decodeIfPresent(T.self, forKey: key) ?? fallback
        }
        let defaults = Account()
        self.init(
            id: try value(.id, defaults.id),
            name: try value(.name, defaults.name),
            group: try value(.group, defaults.group),
            color: try value(.color, defaults.color),
            accountId: try value(.accountId, defaults.accountId),
            region: try value(.region, defaults.region),
            method: try value(.method, defaults.method),
            accessKeyId: try value(.accessKeyId, defaults.accessKeyId),
            userName: try value(.userName, defaults.userName),
            roleName: try value(.roleName, defaults.roleName),
            isFavorite: try value(.isFavorite, defaults.isFavorite),
            notes: try value(.notes, defaults.notes),
            landingService: try value(.landingService, defaults.landingService),
            lastOpenedAt: try container.decodeIfPresent(Date.self, forKey: .lastOpenedAt)
        )
    }
}

nonisolated enum LoginMethod: String, Codable, CaseIterable, Identifiable, Sendable {
    /// IAM access keys → STS GetFederationToken → one-time console sign-in link. No password.
    case accessKeys
    /// The account's IAM sign-in page; the browser or the Passwords app fills in the password.
    case signInPage
    /// Switch role within a session that is already signed in in the browser.
    case switchRole

    var id: Self { self }

    var title: String {
        switch self {
        case .accessKeys: String(localized: "Access keys")
        case .signInPage: String(localized: "Sign-in page")
        case .switchRole: String(localized: "Switch role")
        }
    }

    var systemImage: String {
        switch self {
        case .accessKeys: "key.fill"
        case .signInPage: "person.badge.key.fill"
        case .switchRole: "arrow.left.arrow.right"
        }
    }
}

nonisolated enum AccountColor: String, Codable, CaseIterable, Identifiable, Sendable {
    case red, orange, yellow, green, teal, blue, indigo, purple, pink, gray

    var id: Self { self }

    var color: Color { Color(nsColor: nsColor) }

    var nsColor: NSColor {
        switch self {
        case .red: .systemRed
        case .orange: .systemOrange
        case .yellow: .systemYellow
        case .green: .systemGreen
        case .teal: .systemTeal
        case .blue: .systemBlue
        case .indigo: .systemIndigo
        case .purple: .systemPurple
        case .pink: .systemPink
        case .gray: .systemGray
        }
    }

    /// White initials are unreadable on yellow.
    var prefersDarkText: Bool { self == .yellow }

    /// Colored dot for menus – a non-template image, so the menu doesn't turn it gray.
    var dot: NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
            .applying(.init(paletteColors: [nsColor]))
        return NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) ?? NSImage()
    }

    /// The switchrole page accepts only five colors – the rest map to the closest one.
    var switchRoleHex: String {
        switch self {
        case .red, .pink: "F2B0A9"
        case .orange: "FBBF93"
        case .yellow: "FAD791"
        case .green, .teal: "B7CA9D"
        case .blue, .indigo, .purple, .gray: "99BCE3"
        }
    }

    static func suggested(for name: String) -> AccountColor {
        let name = name.lowercased()
        if name.contains("prod") { return .red }
        if name.contains("stag") || name.contains("release") { return .orange }
        if name.contains("dev") || name.contains("test") { return .green }
        return .blue
    }
}
