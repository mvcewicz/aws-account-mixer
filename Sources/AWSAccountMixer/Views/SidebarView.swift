import SwiftUI

struct SidebarView: View {
    @Binding var selection: AccountFilter?
    @Environment(AccountStore.self) private var store

    @State private var renamingGroup: String?
    @State private var newGroupName = ""

    var body: some View {
        List(selection: $selection) {
            Section {
                row(.all, systemImage: "tray.full")
                row(.favorites, systemImage: "star")
                row(.recent, systemImage: "clock")
            }

            if !store.groupNames.isEmpty {
                Section("Groups") {
                    ForEach(store.groupNames, id: \.self) { group in
                        row(.group(group), systemImage: "folder")
                            .dropDestination(for: String.self) { items, _ in
                                move(items, to: group)
                            }
                            .contextMenu {
                                Button("Rename…") {
                                    newGroupName = group
                                    renamingGroup = group
                                }
                                Button("Delete Group (Keep Accounts)") {
                                    store.dissolveGroup(group)
                                }
                            }
                    }
                    if store.count(in: .group("")) > 0 {
                        row(.group(""), systemImage: "tray")
                            .dropDestination(for: String.self) { items, _ in
                                move(items, to: "")
                            }
                    }
                }
            }
        }
        .alert(
            "Rename Group",
            isPresented: Binding(get: { renamingGroup != nil }, set: { if !$0 { renamingGroup = nil } })
        ) {
            TextField("Group name", text: $newGroupName)
            Button("Rename") { renameGroup() }
            Button("Cancel", role: .cancel) {}
        }
        .onChange(of: store.groupNames) {
            // The group is gone (all its accounts were moved) – go back to "All accounts".
            if case let .group(group) = selection, !group.isEmpty, !store.groupNames.contains(group) {
                selection = .all
            }
        }
    }

    private func row(_ filter: AccountFilter, systemImage: String) -> some View {
        Label(filter.title, systemImage: systemImage)
            .badge(store.count(in: filter))
            .tag(filter)
    }

    private func move(_ items: [String], to group: String) -> Bool {
        let ids = AccountDrag.ids(from: items)
        guard !ids.isEmpty else { return false }
        store.move(ids, toGroup: group)
        return true
    }

    private func renameGroup() {
        guard let group = renamingGroup, !newGroupName.trimmed.isEmpty else { return }
        store.renameGroup(group, to: newGroupName)
        if selection == .group(group) {
            selection = .group(newGroupName.trimmed)
        }
    }
}
