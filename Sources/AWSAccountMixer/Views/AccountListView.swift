import SwiftUI

struct AccountListView: View {
    let filter: AccountFilter

    @Environment(AccountStore.self) private var store
    @Environment(ConsoleLauncher.self) private var launcher
    @Environment(CostStore.self) private var costs
    @Environment(AppState.self) private var appState

    @State private var search = ""
    @State private var selection: Set<Account.ID> = []
    @State private var pendingDeletion: [Account] = []
    @State private var renaming: Account?
    @State private var renameText = ""
    @State private var groupingIDs: Set<Account.ID>?
    @State private var newGroupName = ""

    var body: some View {
        @Bindable var appState = appState
        let sections = store.sections(for: filter, matching: search)

        content(sections)
            .frame(minWidth: 520, minHeight: 320)
            .navigationTitle(filter.title)
            .navigationSubtitle(accountCountText(sections))
            .searchable(text: $search, placement: .toolbar, prompt: "Search accounts")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Import from ~/.aws", systemImage: "square.and.arrow.down") {
                        appState.isImporting = true
                    }
                    .help("Import keys from ~/.aws/credentials")

                    Button("Add Account", systemImage: "plus") {
                        appState.newAccount()
                    }
                    .help("Add an account manually")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                CostTotalsBar(accounts: sections.flatMap(\.accounts))
            }
            .overlay(alignment: .bottom) { toast }
            .animation(.default, value: launcher.toast)
            .task(id: store.accounts.map(\.accountId)) {
                costs.refreshIfNeeded()
            }
            .sheet(item: $appState.editor) { target in
                AccountEditorView(target: target)
            }
            .sheet(isPresented: $appState.isImporting) {
                ImportView()
            }
            .confirmationDialog(
                deletionTitle,
                isPresented: Binding(get: { !pendingDeletion.isEmpty }, set: { if !$0 { pendingDeletion = [] } }),
                presenting: pendingDeletion
            ) { accounts in
                Button("Delete", role: .destructive) {
                    store.delete(Set(accounts.map(\.id)))
                }
            } message: { _ in
                Text("Access keys will also be removed from the Keychain.")
            }
            .alert(
                "Rename Account",
                isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
            ) {
                TextField("Name", text: $renameText)
                Button("Rename") {
                    if let renaming, !renameText.trimmed.isEmpty {
                        store.update([renaming.id]) { $0.name = renameText.trimmed }
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert(
                "New Group",
                isPresented: Binding(get: { groupingIDs != nil }, set: { if !$0 { groupingIDs = nil } })
            ) {
                TextField("Group name", text: $newGroupName)
                Button("Create") {
                    if let groupingIDs, !newGroupName.trimmed.isEmpty {
                        store.move(groupingIDs, toGroup: newGroupName)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The selected accounts will move to the new group.")
            }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(_ sections: [AccountSection]) -> some View {
        if store.accounts.isEmpty {
            ContentUnavailableView {
                Label("No Accounts", systemImage: "key.icloud")
            } description: {
                Text("Import keys from ~/.aws/credentials or add an account manually.")
            } actions: {
                Button("Import from ~/.aws") { appState.isImporting = true }
                    .buttonStyle(.borderedProminent)
                Button("Add Manually") { appState.newAccount() }
            }
        } else if sections.isEmpty {
            emptyState
        } else {
            List(selection: $selection) {
                ForEach(sections) { section in
                    Section {
                        ForEach(section.accounts) { account in
                            AccountRow(account: account, showsGroup: filter != .all && !isGroupFilter)
                                .tag(account.id)
                                .draggable(AccountDrag.payload(for: account, selection: selection))
                        }
                    } header: {
                        if filter == .all, !section.title.isEmpty || sections.count > 1 {
                            Text(section.title.isEmpty ? String(localized: "No group") : section.title)
                        }
                    }
                }
            }
            .contextMenu(forSelectionType: Account.ID.self) { ids in
                contextMenu(for: ids)
            } primaryAction: { ids in
                accounts(ids).forEach { launcher.open($0) }
            }
            .onDeleteCommand {
                pendingDeletion = accounts(selection)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !search.isEmpty {
            ContentUnavailableView.search(text: search)
        } else {
            switch filter {
            case .favorites:
                ContentUnavailableView("No Favorites", systemImage: "star",
                                       description: Text("Star an account – favorites also appear at the top of the menu bar menu."))
            case .recent:
                ContentUnavailableView("Nothing Opened Yet", systemImage: "clock")
            default:
                ContentUnavailableView("Empty Group", systemImage: "folder")
            }
        }
    }

    @ViewBuilder
    private var toast: some View {
        if let message = launcher.toast {
            Label(message, systemImage: "checkmark.circle.fill")
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .shadow(radius: 4, y: 2)
                .padding(.bottom, 52)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: message) {
                    try? await Task.sleep(for: .seconds(2.5))
                    launcher.toast = nil
                }
        }
    }

    // MARK: - Context menu

    @ViewBuilder
    private func contextMenu(for ids: Set<Account.ID>) -> some View {
        let accounts = accounts(ids)
        if accounts.count == 1, let account = accounts.first {
            Button(account.landingService == .home ? String(localized: "Open Console") : String(localized: "Open \(account.landingService.title)")) {
                launcher.open(account)
            }
            Menu("Open In…") { ServiceButtons(account: account) }
            Divider()
            Button("Rename…") {
                renameText = account.name
                renaming = account
            }
            Button("Edit…") { appState.edit(account) }
        }

        if !accounts.isEmpty {
            let allFavorite = accounts.allSatisfy(\.isFavorite)
            Button(allFavorite ? String(localized: "Remove from Favorites") : String(localized: "Add to Favorites")) {
                store.update(ids) { $0.isFavorite = !allFavorite }
            }
            Menu("Move to Group") {
                ForEach(store.groupNames, id: \.self) { group in
                    Button(group) { store.move(ids, toGroup: group) }
                }
                if !store.groupNames.isEmpty {
                    Divider()
                }
                Button("New Group…") {
                    newGroupName = ""
                    groupingIDs = ids
                }
                Button("No Group") { store.move(ids, toGroup: "") }
            }
            Menu("Set Region") {
                Button("Default from Settings") { store.update(ids) { $0.region = "" } }
                Divider()
                ForEach(AWSRegion.all) { region in
                    Button(region.label) { store.update(ids) { $0.region = region.code } }
                }
            }
        }

        if accounts.count == 1, let account = accounts.first {
            Divider()
            if !account.accountId.isEmpty {
                Button("Copy Account ID") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(account.accountId, forType: .string)
                    launcher.toast = String(localized: "Account ID copied")
                }
            }
            Button("Copy Sign-in Link") { launcher.copyLoginLink(account) }
            if account.method == .accessKeys {
                Button("Copy Temporary Terminal Credentials") { launcher.copyTerminalCredentials(account) }
            }
        }

        if CostStore.isEnabled, accounts.contains(where: { $0.method == .accessKeys }) {
            Button("Refresh Costs") { costs.refresh(accounts) }
        }

        if !accounts.isEmpty {
            Divider()
            Button("Delete…", role: .destructive) { pendingDeletion = accounts }
        }
    }

    // MARK: - Helpers

    private var isGroupFilter: Bool {
        if case .group = filter { return true }
        return false
    }

    private func accountCountText(_ sections: [AccountSection]) -> String {
        let count = sections.reduce(0) { $0 + $1.accounts.count }
        return String(localized: "\(count) accounts")
    }

    private var deletionTitle: String {
        if pendingDeletion.count == 1, let account = pendingDeletion.first {
            return String(localized: "Delete the account “\(account.name)”?")
        }
        return String(localized: "Delete the selected accounts (\(pendingDeletion.count))?")
    }

    private func accounts(_ ids: Set<Account.ID>) -> [Account] {
        store.accounts.filter { ids.contains($0.id) }
    }
}

/// "Open In…" items – straight to the chosen service instead of the account's landing service.
struct ServiceButtons: View {
    let account: Account
    @Environment(ConsoleLauncher.self) private var launcher

    var body: some View {
        ForEach(ConsoleService.allCases) { service in
            Button(service.title) { launcher.open(account, at: service) }
        }
    }
}
