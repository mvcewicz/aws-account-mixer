import SwiftUI

struct AccountEditorView: View {
    @Environment(AccountStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Preferences.defaultRegion) private var defaultRegion = ""

    private let original: Account
    private let isNew: Bool
    @State private var account: Account
    @State private var secret = ""
    @State private var hasStoredSecret = false
    @State private var verification = Verification.idle
    @State private var isSaving = false

    enum Verification {
        case idle, checking, success(CallerIdentity), failure(String)
    }

    init(target: EditorTarget) {
        original = target.account
        isNew = target.isNew
        _account = State(initialValue: target.account)
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $account.name, prompt: Text("e.g. Shop – production"))
                groupField
                colorField
                Picker("Region", selection: $account.region) {
                    Text(defaultRegion.isEmpty ? String(localized: "Default (last used)") : String(localized: "Default (\(defaultRegion))")).tag("")
                    Divider()
                    if !account.region.isEmpty, !AWSRegion.all.contains(where: { $0.code == account.region }) {
                        Text(account.region).tag(account.region)
                    }
                    ForEach(AWSRegion.all) { region in
                        Text(region.label).tag(region.code)
                    }
                }
                Picker("Click opens", selection: $account.landingService) {
                    ForEach(ConsoleService.allCases) { service in
                        Text(service.title).tag(service)
                    }
                }
                Toggle("Favorite", isOn: $account.isFavorite)
            }

            Section("Notes") {
                TextField("Notes", text: $account.notes, prompt: Text("e.g. what the account is for, who has access…"), axis: .vertical)
                    .lineLimit(2...5)
                    .labelsHidden()
            }

            Section {
                Picker("Method", selection: $account.method) {
                    ForEach(LoginMethod.allCases) { method in
                        Text(method.title).tag(method)
                    }
                }
                .pickerStyle(.segmented)

                switch account.method {
                case .accessKeys: accessKeyFields
                case .signInPage: signInPageFields
                case .switchRole: switchRoleFields
                }
            } header: {
                Text("Sign-in")
            } footer: {
                Text(methodFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .navigationTitle(isNew ? String(localized: "New Account") : String(localized: "Edit Account"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isNew ? String(localized: "Add") : String(localized: "Save")) {
                    Task { await save() }
                }
                .disabled(!canSave || isSaving)
            }
        }
        .onAppear {
            hasStoredSecret = !isNew && store.hasSecret(for: original)
        }
    }

    // MARK: - Fields

    private var groupField: some View {
        LabeledContent("Group") {
            HStack(spacing: 4) {
                TextField("Group", text: $account.group, prompt: Text("optional"))
                    .labelsHidden()
                if !store.groupNames.isEmpty {
                    Menu {
                        ForEach(store.groupNames, id: \.self) { group in
                            Button(group) { account.group = group }
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
            }
        }
    }

    private var colorField: some View {
        LabeledContent("Color") {
            HStack(spacing: 6) {
                ForEach(AccountColor.allCases) { color in
                    Button {
                        account.color = color
                    } label: {
                        Circle()
                            .fill(color.color)
                            .frame(width: 18, height: 18)
                            .overlay {
                                if account.color == color {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(color.prefersDarkText ? .black : .white)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(color.rawValue)
                }
            }
        }
    }

    @ViewBuilder
    private var accessKeyFields: some View {
        TextField("Access Key ID", text: $account.accessKeyId, prompt: Text("AKIA…"))
            .fontDesign(.monospaced)
            .onChange(of: account.accessKeyId) { verification = .idle }
        SecureField(
            "Secret Access Key",
            text: $secret,
            prompt: Text(hasStoredSecret ? String(localized: "saved in the Keychain") : String(localized: "required"))
        )
        .onChange(of: secret) { verification = .idle }

        LabeledContent("Account") {
            switch verification {
            case .idle:
                Button("Check Key") { Task { await verify() } }
                    .disabled(!hasUsableKeys)
            case .checking:
                ProgressView().controlSize(.small)
            case let .success(identity):
                Label(identity.arn, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            case let .failure(message):
                Label(message, systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                    .lineLimit(4)
            }
        }
    }

    @ViewBuilder
    private var signInPageFields: some View {
        TextField("Account ID or alias", text: $account.accountId, prompt: Text(verbatim: "123456789012"))
        TextField("IAM user", text: $account.userName, prompt: Text("optional, for display only"))
    }

    @ViewBuilder
    private var switchRoleFields: some View {
        TextField("Account ID", text: $account.accountId, prompt: Text(verbatim: "123456789012"))
        TextField("Role name", text: $account.roleName, prompt: Text("e.g. OrganizationAccountAccessRole"))
    }

    private var methodFooter: String {
        switch account.method {
        case .accessKeys:
            String(localized: "The key is exchanged for a one-time console link (sts:GetFederationToken) – no password. The secret is stored in the Keychain.")
        case .signInPage:
            String(localized: "Opens this account's IAM sign-in page. Your browser or the Passwords app fills in the password.")
        case .switchRole:
            String(localized: "Switches role within a session you're already signed in to in the browser.")
        }
    }

    // MARK: - Logic

    /// Keys to check: the entered secret or – if the Access Key ID hasn't changed – the one from the Keychain.
    private var currentCredentials: AWSCredentials? {
        let keyId = account.accessKeyId.trimmed
        let secret = secret.trimmed.isEmpty && keyId == original.accessKeyId && hasStoredSecret
            ? Keychain.secret(for: original.id)
            : secret.trimmed
        guard !keyId.isEmpty, let secret, !secret.isEmpty else { return nil }
        return AWSCredentials(accessKeyId: keyId, secretAccessKey: secret)
    }

    private var hasUsableKeys: Bool {
        let keyId = account.accessKeyId.trimmed
        return !keyId.isEmpty && (!secret.trimmed.isEmpty || (hasStoredSecret && keyId == original.accessKeyId))
    }

    private var canSave: Bool {
        guard !account.name.trimmed.isEmpty else { return false }
        switch account.method {
        case .accessKeys:
            return hasUsableKeys
        case .signInPage:
            return !account.accountId.trimmed.isEmpty
        case .switchRole:
            return !account.accountId.trimmed.isEmpty && !account.roleName.trimmed.isEmpty
        }
    }

    /// GetCallerIdentity fills in the account ID and IAM user name.
    @discardableResult
    private func verify() async -> Bool {
        guard let credentials = currentCredentials else { return false }
        verification = .checking
        do {
            let identity = try await STSClient(credentials: credentials).callerIdentity()
            account.accountId = identity.account
            account.userName = identity.userName
            verification = .success(identity)
            return true
        } catch {
            verification = .failure(error.localizedDescription)
            return false
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        account.name = account.name.trimmed
        account.group = account.group.trimmed
        account.accessKeyId = account.accessKeyId.trimmed
        account.accountId = account.accountId.normalizedAccountId
        account.roleName = account.roleName.trimmed
        account.notes = account.notes.trimmed

        if account.method == .accessKeys {
            let keysChanged = !secret.trimmed.isEmpty || account.accessKeyId != original.accessKeyId
            if case .success = verification {} else if keysChanged || account.accountId.isEmpty {
                guard await verify() else { return }
            }
        }

        do {
            try store.save(account, secret: account.method == .accessKeys ? secret.trimmed : nil)
            dismiss()
        } catch {
            verification = .failure(error.localizedDescription)
        }
    }
}
