import AppKit
import Observation
import SwiftUI

/// Spotlight-style panel: global shortcut → type a few letters → Return opens the console.
@Observable
final class QuickSwitcher {
    /// The shortcut is taken by another app – Settings shows a warning.
    private(set) var hotKeyFailed = false

    @ObservationIgnored private let store: AccountStore
    @ObservationIgnored private let launcher: ConsoleLauncher
    @ObservationIgnored private let hotKey = GlobalHotKey()
    @ObservationIgnored private var registeredPreset: HotKeyPreset?
    @ObservationIgnored private var panel: NSPanel?

    init(store: AccountStore, launcher: ConsoleLauncher) {
        self.store = store
        self.launcher = launcher
        applyHotKeyPreference()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyHotKeyPreference() }
        }
    }

    func toggle() {
        if panel?.isVisible == true {
            close()
        } else {
            show()
        }
    }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        // A fresh view every time – empty search field and the selection at the top.
        panel.contentView = NSHostingView(
            rootView: QuickSwitcherView(close: { [weak self] in self?.close() })
                .environment(store)
                .environment(launcher)
        )
        if let screen = NSScreen.main?.visibleFrame {
            panel.setFrameTopLeftPoint(NSPoint(x: screen.midX - panel.frame.width / 2, y: screen.maxY - screen.height * 0.18))
        }
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
    }

    private func applyHotKeyPreference() {
        let preset = UserDefaults.standard.string(forKey: Preferences.quickSwitcherHotKey).flatMap(HotKeyPreset.init) ?? .default
        guard preset != registeredPreset else { return }
        registeredPreset = preset
        hotKeyFailed = !hotKey.register(preset) { [weak self] in self?.toggle() }
    }

    private func makePanel() -> NSPanel {
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 400),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        // Clicking outside hides the panel, like Spotlight.
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        return panel
    }
}

/// A panel that takes keyboard input without activating the app.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

struct QuickSwitcherView: View {
    let close: () -> Void

    @Environment(AccountStore.self) private var store
    @Environment(ConsoleLauncher.self) private var launcher
    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        let results = results
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "key.icloud")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                TextField("Open AWS account…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22))
                    .focused($isSearchFocused)
                    .onSubmit { open(results) }
                    .onKeyPress(.downArrow) {
                        highlighted = min(highlighted + 1, max(results.count - 1, 0))
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        highlighted = max(highlighted - 1, 0)
                        return .handled
                    }
                    .onExitCommand { close() }
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            if results.isEmpty {
                Text("No accounts match “\(query)”")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, account in
                                QuickSwitcherRow(account: account, isHighlighted: index == highlighted)
                                    .id(index)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        highlighted = index
                                        open(results)
                                    }
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: highlighted) {
                        proxy.scrollTo(highlighted)
                    }
                }
            }

            Divider()
            HStack(spacing: 14) {
                Text("↩ open")
                Text("↑↓ select")
                Text("esc close")
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
        }
        .frame(width: 580, height: 400)
        .onAppear { isSearchFocused = true }
        .onChange(of: query) { highlighted = 0 }
    }

    /// Without a query: favorites and recently opened on top. With a query: names starting with it come first.
    private var results: [Account] {
        var seen = Set<Account.ID>()
        guard !query.isEmpty else {
            return (store.favorites + store.recent(limit: 5) + store.orderedAccounts).filter { seen.insert($0.id).inserted }
        }
        let query = query.lowercased()
        return store.accounts
            .filter { $0.matches(query) }
            .sorted { lhs, rhs in
                let lhsPrefix = lhs.name.lowercased().hasPrefix(query), rhsPrefix = rhs.name.lowercased().hasPrefix(query)
                if lhsPrefix != rhsPrefix { return lhsPrefix }
                return (lhs.lastOpenedAt ?? .distantPast) > (rhs.lastOpenedAt ?? .distantPast)
            }
    }

    private func open(_ results: [Account]) {
        guard results.indices.contains(highlighted) else { return }
        launcher.open(results[highlighted])
        close()
    }
}

private struct QuickSwitcherRow: View {
    let account: Account
    let isHighlighted: Bool
    @AppStorage(Preferences.defaultRegion) private var defaultRegion = ""

    var body: some View {
        HStack(spacing: 12) {
            AccountBadge(account: account, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(account.name).font(.headline)
                    if account.isFavorite {
                        Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow)
                    }
                }
                Text([account.group, account.subtitle(defaultRegion: defaultRegion)].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if isHighlighted {
                Text(verbatim: "\(account.landingService == .home ? String(localized: "Console") : account.landingService.title) ↩")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isHighlighted ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 8))
    }
}
