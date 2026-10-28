/// UserDefaults keys shared by @AppStorage and code outside views.
nonisolated enum Preferences {
    /// Path to the browser app; empty = the system default browser.
    static let browserPath = "browserPath"
    static let sessionHours = "sessionHours"
    static let showMenuBarIcon = "showMenuBarIcon"
    /// Region for accounts without their own region; empty = whatever the console used last.
    static let defaultRegion = "defaultRegion"
    static let showCosts = "showCosts"
    /// How often to refresh costs, in hours; 0 = manually only.
    static let costRefreshHours = "costRefreshHours"
    static let quickSwitcherHotKey = "quickSwitcherHotKey"

    static let defaultSessionHours = 12
    static let defaultCostRefreshHours = 24
}
