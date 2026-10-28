import SwiftUI

struct ContentView: View {
    @State private var filter: AccountFilter? = .all

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $filter)
                .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 280)
        } detail: {
            AccountListView(filter: filter ?? .all)
        }
    }
}

/// Accounts dragged from the list – selected UUIDs separated by commas.
enum AccountDrag {
    static func payload(for account: Account, selection: Set<Account.ID>) -> String {
        let ids = selection.contains(account.id) ? selection : [account.id]
        return ids.map(\.uuidString).joined(separator: ",")
    }

    static func ids(from items: [String]) -> Set<Account.ID> {
        Set(items.flatMap { $0.split(separator: ",") }.compactMap { UUID(uuidString: String($0)) })
    }
}
