import SwiftUI

struct AccountRow: View {
    let account: Account
    /// Flat views (favorites, recent) also show the account's group.
    var showsGroup = false

    @Environment(AccountStore.self) private var store
    @Environment(ConsoleLauncher.self) private var launcher
    @AppStorage(Preferences.defaultRegion) private var defaultRegion = ""
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            AccountBadge(account: account)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(account.name)
                        .font(.headline)
                        .lineLimit(1)
                    if showsGroup, !account.group.isEmpty {
                        Text(account.group)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                }
                let subtitle = account.subtitle(defaultRegion: defaultRegion)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if !account.notes.isEmpty {
                    Text(account.notes)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .help(account.notes)
                }
            }

            Spacer(minLength: 8)

            CostSummary(account: account)

            Button {
                store.update([account.id]) { $0.isFavorite.toggle() }
            } label: {
                Image(systemName: account.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(account.isFavorite ? .yellow : .secondary)
            }
            .buttonStyle(.borderless)
            .opacity(account.isFavorite || isHovering ? 1 : 0)
            .help(account.isFavorite ? String(localized: "Remove from Favorites") : String(localized: "Add to Favorites"))

            Image(systemName: account.method.systemImage)
                .foregroundStyle(.tertiary)
                .frame(width: 18)
                .help(account.method.title)

            ZStack {
                if launcher.isOpening(account) {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(width: 16)

            Menu {
                ServiceButtons(account: account)
            } label: {
                Label(account.landingService == .home ? String(localized: "Console") : account.landingService.title, systemImage: "arrow.up.forward")
            } primaryAction: {
                launcher.open(account)
            }
            .fixedSize()
            .disabled(launcher.isOpening(account))
            .help("Open the account with one click (arrow: choose a service)")
        }
        .padding(.vertical, 4)
        .onHover { isHovering = $0 }
    }
}

/// Colored square with initials – to tell prod from dev at a glance.
struct AccountBadge: View {
    let account: Account
    var size: CGFloat = 32

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
            .fill(account.color.color.gradient)
            .frame(width: size, height: size)
            .overlay {
                Text(account.initials)
                    .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                    .foregroundStyle(account.color.prefersDarkText ? .black.opacity(0.75) : .white)
            }
    }
}
