import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @AppStorage(Preferences.browserPath) private var browserPath = ""
    @AppStorage(Preferences.sessionHours) private var sessionHours = Preferences.defaultSessionHours
    @AppStorage(Preferences.showMenuBarIcon) private var showMenuBarIcon = true
    @AppStorage(Preferences.defaultRegion) private var defaultRegion = ""
    @AppStorage(Preferences.quickSwitcherHotKey) private var hotKey = HotKeyPreset.default.rawValue
    @AppStorage(Preferences.showCosts) private var showCosts = true
    @AppStorage(Preferences.costRefreshHours) private var costRefreshHours = Preferences.defaultCostRefreshHours

    @Environment(QuickSwitcher.self) private var quickSwitcher
    @State private var loginItemStatus = SMAppService.mainApp.status
    @State private var loginItemError: String?

    private let browsers = Browser.installed

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: launchAtLogin)
                if loginItemStatus == .requiresApproval {
                    LabeledContent("macOS needs your approval for launch at login") {
                        Button("Open System Settings") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
                if let loginItemError {
                    Label(loginItemError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                Toggle("Show in menu bar", isOn: $showMenuBarIcon)
            }

            Section {
                Picker("Open in", selection: $browserPath) {
                    Text("Default browser").tag("")
                    Divider()
                    ForEach(browsers, id: \.path) { url in
                        Label {
                            Text(FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""))
                        } icon: {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        }
                        .tag(url.path)
                    }
                }

                Picker("Default region", selection: $defaultRegion) {
                    Text("Last used in the console").tag("")
                    Divider()
                    ForEach(AWSRegion.all) { region in
                        Text(region.label).tag(region.code)
                    }
                }

                Picker("Session length", selection: $sessionHours) {
                    ForEach([1, 4, 8, 12, 24, 36], id: \.self) { hours in
                        Text("\(hours) h").tag(hours)
                    }
                }
            } header: {
                Text("Sign-in")
            } footer: {
                Text("The default region applies to accounts without their own region (editor or context menu → “Set Region”). Session length applies to signing in with keys (AWS allows 1 h for root keys). To keep several accounts open at once, turn on multi-session support in the AWS console (account menu → “Turn on multi-session support”).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Quick switcher", selection: $hotKey) {
                    ForEach(HotKeyPreset.allCases) { preset in
                        Text(preset.title).tag(preset.rawValue)
                    }
                }
                if quickSwitcherFailed {
                    Label("Another app already uses this shortcut – pick a different one.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Shortcuts")
            } footer: {
                Text("The shortcut works from any app: type a few letters of an account name and press Return.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Show costs and forecast", isOn: $showCosts)
                Picker("Refresh automatically", selection: $costRefreshHours) {
                    Text("Once a day").tag(24)
                    Text("Every 12 h").tag(12)
                    Text("Manually only").tag(0)
                }
                .disabled(!showCosts)
            } header: {
                Text("Costs")
            } footer: {
                Text("Data from AWS Cost Explorer (requires ce:GetCostAndUsage and ce:GetCostForecast). Each request costs USD 0.01 and refreshing an account takes 2 requests; accounts with the same ID are queried once.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Launch at login via SMAppService – the app shows up in System Settings → General → Login Items.
    private var launchAtLogin: Binding<Bool> {
        Binding {
            loginItemStatus == .enabled
        } set: { enabled in
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                loginItemError = nil
            } catch {
                loginItemError = String(localized: "Couldn't change launch at login: \(error.localizedDescription)")
            }
            loginItemStatus = SMAppService.mainApp.status
        }
    }

    private var quickSwitcherFailed: Bool {
        quickSwitcher.hotKeyFailed && hotKey != HotKeyPreset.off.rawValue
    }
}
