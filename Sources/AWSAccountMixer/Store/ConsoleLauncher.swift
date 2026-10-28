import AppKit
import Observation

/// Opens the AWS console for an account – one click from the list to the dashboard.
@Observable
final class ConsoleLauncher {
    private(set) var inProgress: Set<Account.ID> = []
    /// Short message after silent actions (copying) – the list shows it at the bottom of the window.
    var toast: String?
    @ObservationIgnored private let store: AccountStore

    init(store: AccountStore) {
        self.store = store
    }

    func isOpening(_ account: Account) -> Bool {
        inProgress.contains(account.id)
    }

    /// `service == nil` – the account's landing service.
    func open(_ account: Account, at service: ConsoleService? = nil) {
        run(account) { [store] in
            let url = try await self.loginURL(for: account, at: service ?? account.landingService)
            try await Browser.open(url)
            store.markOpened(account.id)
        }
    }

    /// The federation link is single-use and valid for 15 minutes – handy e.g. for another browser profile.
    func copyLoginLink(_ account: Account) {
        run(account) {
            let url = try await self.loginURL(for: account, at: account.landingService)
            self.copy(url.absoluteString, toast: String(localized: "Sign-in link copied (valid for 15 min)"))
        }
    }

    /// `export AWS_…` with temporary credentials (GetSessionToken) – to paste into a terminal.
    func copyTerminalCredentials(_ account: Account) {
        run(account) { [store] in
            let sts = STSClient(credentials: try store.credentials(for: account))
            let session = try await sts.sessionToken(durationSeconds: self.sessionSeconds(for: account))
            var lines = [
                "export AWS_ACCESS_KEY_ID=\(session.accessKeyId)",
                "export AWS_SECRET_ACCESS_KEY=\(session.secretAccessKey)",
                "export AWS_SESSION_TOKEN=\(session.sessionToken ?? "")",
            ]
            let region = account.effectiveRegion(default: self.defaultRegion)
            if !region.isEmpty {
                lines.append("export AWS_REGION=\(region)")
            }
            self.copy(lines.joined(separator: "\n"), toast: String(localized: "Temporary terminal credentials copied"))
        }
    }

    func loginURL(for account: Account, at service: ConsoleService) async throws -> URL {
        let destination = service.url(region: account.effectiveRegion(default: defaultRegion))
        switch account.method {
        case .accessKeys:
            let sts = STSClient(credentials: try store.credentials(for: account))
            let session = try await sts.federationToken(
                name: ConsoleSignIn.federatedUserName(account.userName),
                durationSeconds: sessionSeconds(for: account)
            )
            return try await ConsoleSignIn.federatedURL(credentials: session, destination: destination)
        case .signInPage:
            guard !account.accountId.isEmpty else {
                throw AWSError.incompleteAccount(String(localized: "Enter the account ID or alias."))
            }
            return ConsoleSignIn.signInPageURL(accountId: account.accountId)
        case .switchRole:
            guard !account.accountId.isEmpty, !account.roleName.isEmpty else {
                throw AWSError.incompleteAccount(String(localized: "Enter the account ID and role name."))
            }
            return ConsoleSignIn.switchRoleURL(
                accountId: account.accountId, roleName: account.roleName,
                displayName: account.name, color: account.color, destination: destination
            )
        }
    }

    private var defaultRegion: String {
        UserDefaults.standard.string(forKey: Preferences.defaultRegion) ?? ""
    }

    /// Session length from Settings; for root keys AWS allows at most one hour.
    private func sessionSeconds(for account: Account) -> Int {
        let hours = UserDefaults.standard.object(forKey: Preferences.sessionHours) as? Int ?? Preferences.defaultSessionHours
        return min(hours * 3600, account.userName == "root" ? 3600 : 36 * 3600)
    }

    private func copy(_ text: String, toast: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        self.toast = toast
    }

    private func run(_ account: Account, action: @escaping () async throws -> Void) {
        guard inProgress.insert(account.id).inserted else { return }
        Task {
            do {
                try await action()
                inProgress.remove(account.id)
            } catch {
                inProgress.remove(account.id)
                present(error, for: account)
            }
        }
    }

    private func present(_ error: Error, for account: Account) {
        NSApp.activate()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Couldn't open the console for “\(account.name)”")
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}

enum Browser {
    /// Apps that can open an https link.
    static var installed: [URL] {
        NSWorkspace.shared.urlsForApplications(toOpen: URL(string: "https://console.aws.amazon.com")!)
    }

    static func open(_ url: URL) async throws {
        let path = UserDefaults.standard.string(forKey: Preferences.browserPath) ?? ""
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else {
            NSWorkspace.shared.open(url)
            return
        }
        _ = try await NSWorkspace.shared.open([url], withApplicationAt: URL(filePath: path), configuration: NSWorkspace.OpenConfiguration())
    }
}
