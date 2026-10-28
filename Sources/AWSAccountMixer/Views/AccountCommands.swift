import SwiftUI

/// The "Accounts" menu with ⌘1…⌘9 for the first nine accounts, plus add/import commands.
struct AccountCommands: Commands {
    let store: AccountStore
    let launcher: ConsoleLauncher
    let costs: CostStore
    let appState: AppState
    let quickSwitcher: QuickSwitcher

    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Account…") {
                openWindow(id: AWSAccountMixerApp.mainWindowID)
                appState.newAccount()
            }
            .keyboardShortcut("n")

            Button("Import from ~/.aws…") {
                openWindow(id: AWSAccountMixerApp.mainWindowID)
                appState.isImporting = true
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
        }

        CommandMenu("Accounts") {
            Button("Quick Switcher…") { quickSwitcher.show() }
                .keyboardShortcut("k")
            Button("Refresh Costs") { costs.refresh() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Divider()

            let accounts = store.orderedAccounts
            if accounts.isEmpty {
                Text("No accounts")
            }
            ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                if index < 9 {
                    Button(account.name) { launcher.open(account) }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
                } else {
                    Button(account.name) { launcher.open(account) }
                }
            }
        }
    }
}
