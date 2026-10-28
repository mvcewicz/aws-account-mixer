import SwiftUI

/// The menu bar menu: account → console, from anywhere in the system.
struct MenuBarMenu: View {
    @Environment(AccountStore.self) private var store
    @Environment(ConsoleLauncher.self) private var launcher
    @Environment(CostStore.self) private var costs
    @Environment(QuickSwitcher.self) private var quickSwitcher
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let totals = costs.totals(for: store.accounts) {
            Text("This month: \(totals.monthToDate.cost(totals.currency)) · forecast \(totals.forecast.cost(totals.currency))")
            Divider()
        }

        if store.accounts.isEmpty {
            Text("No accounts")
        }

        let favorites = store.favorites
        if !favorites.isEmpty {
            Section("Favorites") {
                ForEach(favorites) { accountButton($0) }
            }
        }

        let recent = store.recent(limit: 3).filter { !$0.isFavorite }
        if !recent.isEmpty {
            Section("Recently Opened") {
                ForEach(recent) { accountButton($0) }
            }
        }

        ForEach(store.sections()) { section in
            if section.title.isEmpty {
                if favorites.isEmpty && recent.isEmpty && store.groupNames.isEmpty {
                    ForEach(section.accounts) { accountButton($0) }
                } else {
                    Section("No Group") {
                        ForEach(section.accounts) { accountButton($0) }
                    }
                }
            } else {
                Menu(section.title) {
                    ForEach(section.accounts) { accountButton($0) }
                }
            }
        }

        Divider()

        Button("Quick Switcher…") { quickSwitcher.show() }
        Button("Show Account List") {
            openWindow(id: AWSAccountMixerApp.mainWindowID)
            NSApp.activate()
        }
        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",")

        Divider()

        Button("Quit") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func accountButton(_ account: Account) -> some View {
        Button {
            launcher.open(account)
        } label: {
            Label {
                if let report = costs.report(for: account) {
                    Text(verbatim: "\(account.name)  ·  \(report.monthToDate.cost(report.currency, compact: true))")
                } else {
                    Text(account.name)
                }
            } icon: {
                Image(nsImage: account.color.dot)
            }
        }
    }
}
