import Foundation
import Observation

/// Sheet state shared by views and menu commands.
@Observable
final class AppState {
    var editor: EditorTarget?
    var isImporting = false

    func newAccount() {
        editor = EditorTarget(account: Account(), isNew: true)
    }

    func edit(_ account: Account) {
        editor = EditorTarget(account: account, isNew: false)
    }
}

struct EditorTarget: Identifiable {
    let id = UUID()
    var account: Account
    var isNew: Bool
}
