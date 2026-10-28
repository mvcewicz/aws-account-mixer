import SwiftUI

@main
struct AWSAccountMixerApp: App {
    static let mainWindowID = "main"

    @State private var store: AccountStore
    @State private var launcher: ConsoleLauncher
    @State private var costs: CostStore
    @State private var quickSwitcher: QuickSwitcher
    @State private var appState = AppState()
    @AppStorage(Preferences.showMenuBarIcon) private var showMenuBarIcon = true

    init() {
        let store = AccountStore()
        let launcher = ConsoleLauncher(store: store)
        let costs = CostStore(accountStore: store)
        _store = State(initialValue: store)
        _launcher = State(initialValue: launcher)
        _costs = State(initialValue: costs)
        _quickSwitcher = State(initialValue: QuickSwitcher(store: store, launcher: launcher))
        costs.startAutoRefresh()
    }

    var body: some Scene {
        Window("AWS Account Mixer", id: Self.mainWindowID) {
            ContentView()
                .environment(store)
                .environment(launcher)
                .environment(costs)
                .environment(appState)
        }
        .defaultSize(width: 860, height: 620)
        .commands {
            AccountCommands(store: store, launcher: launcher, costs: costs, appState: appState, quickSwitcher: quickSwitcher)
        }

        MenuBarExtra("AWS Account Mixer", systemImage: "key.icloud", isInserted: $showMenuBarIcon) {
            MenuBarMenu()
                .environment(store)
                .environment(launcher)
                .environment(costs)
                .environment(quickSwitcher)
        }

        Settings {
            SettingsView()
                .environment(quickSwitcher)
        }
    }
}
