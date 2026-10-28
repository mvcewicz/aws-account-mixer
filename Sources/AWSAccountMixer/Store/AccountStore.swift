import Foundation
import Observation

struct AccountSection: Identifiable {
    var title: String
    var accounts: [Account]
    var id: String { title }
}

/// What the list shows – the sidebar selection.
enum AccountFilter: Hashable {
    case all, favorites, recent
    case group(String)

    var title: String {
        switch self {
        case .all: String(localized: "All accounts")
        case .favorites: String(localized: "Favorites")
        case .recent: String(localized: "Recently opened")
        case let .group(name): name.isEmpty ? String(localized: "No group") : name
        }
    }
}

/// Accounts in `~/Library/Application Support/AWS Account Mixer/accounts.json` + secrets in the Keychain.
@Observable
final class AccountStore {
    private(set) var accounts: [Account] = []
    @ObservationIgnored private let fileURL: URL

    init(fileURL: URL = AccountStore.defaultFileURL) {
        self.fileURL = fileURL
        load()
    }

    /// The `-AccountsFile <path>` launch argument switches to another file (e.g. for testing).
    static var defaultFileURL: URL {
        if let path = UserDefaults.standard.string(forKey: "AccountsFile") {
            return URL(filePath: path)
        }
        return URL.applicationSupportDirectory.appending(path: "AWS Account Mixer/accounts.json")
    }

    // MARK: - Reading

    /// "All" – named groups alphabetically, ungrouped accounts last. Other filters – one section without a header.
    func sections(for filter: AccountFilter = .all, matching query: String = "") -> [AccountSection] {
        let matching = accounts.filter { $0.matches(query) }
        let flat: [Account]
        switch filter {
        case .all:
            let grouped = Dictionary(grouping: matching, by: \.group)
            return grouped.keys
                .sorted { lhs, rhs in
                    lhs.isEmpty != rhs.isEmpty ? rhs.isEmpty : lhs.localizedStandardCompare(rhs) == .orderedAscending
                }
                .map { AccountSection(title: $0, accounts: Self.byName(grouped[$0, default: []])) }
        case .favorites:
            flat = Self.byName(matching.filter(\.isFavorite))
        case .recent:
            flat = recent(from: matching, limit: 10)
        case let .group(name):
            flat = Self.byName(matching.filter { $0.group == name })
        }
        return flat.isEmpty ? [] : [AccountSection(title: "", accounts: flat)]
    }

    /// The order of the "All" list – the ⌘1…⌘9 shortcuts follow it.
    var orderedAccounts: [Account] { sections().flatMap(\.accounts) }

    var favorites: [Account] { Self.byName(accounts.filter(\.isFavorite)) }

    func recent(limit: Int) -> [Account] { recent(from: accounts, limit: limit) }

    var groupNames: [String] {
        Set(accounts.map(\.group)).filter { !$0.isEmpty }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func count(in filter: AccountFilter) -> Int {
        sections(for: filter).reduce(0) { $0 + $1.accounts.count }
    }

    func containsAccessKey(_ accessKeyId: String) -> Bool {
        accounts.contains { $0.accessKeyId == accessKeyId }
    }

    func hasSecret(for account: Account) -> Bool {
        Keychain.secret(for: account.id) != nil
    }

    func credentials(for account: Account) throws -> AWSCredentials {
        guard let secret = Keychain.secret(for: account.id) else { throw AWSError.missingSecret }
        return AWSCredentials(accessKeyId: account.accessKeyId, secretAccessKey: secret)
    }

    // MARK: - Changes

    /// Adds or updates an account. `secret == nil` keeps the stored secret unchanged.
    func save(_ account: Account, secret: String?) throws {
        if account.method == .accessKeys {
            if let secret, !secret.isEmpty {
                try Keychain.setSecret(secret, for: account.id, label: "AWS Account Mixer – \(account.accessKeyId)")
            }
        } else {
            Keychain.deleteSecret(for: account.id)
        }

        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
        } else {
            accounts.append(account)
        }
        try persist()
    }

    /// The same change for many accounts at once (group, favorite, name…).
    func update(_ ids: Set<Account.ID>, _ change: (inout Account) -> Void) {
        for index in accounts.indices where ids.contains(accounts[index].id) {
            change(&accounts[index])
        }
        try? persist()
    }

    func move(_ ids: Set<Account.ID>, toGroup group: String) {
        update(ids) { $0.group = group.trimmed }
    }

    func renameGroup(_ group: String, to newName: String) {
        update(Set(accounts.filter { $0.group == group }.map(\.id))) { $0.group = newName.trimmed }
    }

    /// Removes just the group – its accounts become ungrouped.
    func dissolveGroup(_ group: String) {
        renameGroup(group, to: "")
    }

    func markOpened(_ id: Account.ID) {
        update([id]) { $0.lastOpenedAt = .now }
    }

    func delete(_ ids: Set<Account.ID>) {
        ids.forEach(Keychain.deleteSecret)
        accounts.removeAll { ids.contains($0.id) }
        try? persist()
    }

    // MARK: - Private

    private func recent(from accounts: [Account], limit: Int) -> [Account] {
        Array(
            accounts
                .compactMap { account in account.lastOpenedAt.map { (account, $0) } }
                .sorted { $0.1 > $1.1 }
                .prefix(limit)
                .map(\.0)
        )
    }

    private static func byName(_ accounts: [Account]) -> [Account] {
        accounts.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            accounts = try JSONDecoder().decode([Account].self, from: data)
        } catch {
            // Never overwrite a file we can't read – move it aside instead.
            try? FileManager.default.moveItem(at: fileURL, to: fileURL.appendingPathExtension("broken"))
        }
    }

    private func persist() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(accounts).write(to: fileURL, options: .atomic)
    }
}
