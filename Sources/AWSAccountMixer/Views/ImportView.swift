import SwiftUI

/// Imports keys from `~/.aws/credentials*`; each unique key is checked with GetCallerIdentity.
struct ImportView: View {
    @Environment(AccountStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var candidates: [ImportCandidate] = []
    @State private var hasScanned = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Import from ~/.aws")
                    .font(.title2.bold())
                Text("Keys from the credentials and credentials.* files. A key that appears in several files is listed once, and secrets go to the Keychain.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()

            Divider()

            Group {
                if !hasScanned {
                    ProgressView()
                } else if candidates.isEmpty {
                    ContentUnavailableView(
                        "No Keys Found",
                        systemImage: "key.slash",
                        description: Text("No profile in ~/.aws has both aws_access_key_id and aws_secret_access_key.")
                    )
                } else {
                    List($candidates) { $candidate in
                        ImportRow(candidate: $candidate)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack {
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .lineLimit(2)
                } else {
                    Text("Selected: \(selected.count)")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Import") { importSelected() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selected.isEmpty)
            }
            .padding()
        }
        .frame(width: 620, height: 540)
        .task { await scan() }
    }

    private var selected: [ImportCandidate] {
        candidates.filter { $0.isSelected && !$0.alreadyImported }
    }

    private func scan() async {
        let profiles = CredentialsFile.scan()
        let nameCounts = Dictionary(profiles.map { ($0.suggestedName, 1) }, uniquingKeysWith: +)
        candidates = profiles.map { profile in
            // The same profile (e.g. admin) in different files can be a different account – append the file name.
            var name = profile.suggestedName
            if nameCounts[name, default: 0] > 1, let suffix = profile.sources.first?.fileSuffix {
                name += " (\(suffix))"
            }
            let imported = store.containsAccessKey(profile.accessKeyId)
            return ImportCandidate(profile: profile, name: name, isSelected: !imported, alreadyImported: imported)
        }
        hasScanned = true

        await withTaskGroup(of: (String, ImportCandidate.Identity).self) { group in
            for candidate in candidates {
                let credentials = candidate.profile.credentials
                group.addTask {
                    do {
                        return (credentials.accessKeyId, .verified(try await STSClient(credentials: credentials).callerIdentity()))
                    } catch {
                        return (credentials.accessKeyId, .failed(error.localizedDescription))
                    }
                }
            }
            for await (id, identity) in group {
                guard let index = candidates.firstIndex(where: { $0.id == id }) else { continue }
                candidates[index].identity = identity
                if case .failed = identity {
                    candidates[index].isSelected = false
                }
            }
        }
    }

    private func importSelected() {
        do {
            for candidate in selected {
                let name = candidate.name.trimmed.isEmpty ? candidate.profile.suggestedName : candidate.name.trimmed
                var account = Account(
                    name: name,
                    color: .suggested(for: name),
                    method: .accessKeys,
                    accessKeyId: candidate.profile.accessKeyId
                )
                if case let .verified(identity) = candidate.identity {
                    account.accountId = identity.account
                    account.userName = identity.userName
                }
                try store.save(account, secret: candidate.profile.secretAccessKey)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ImportCandidate: Identifiable {
    nonisolated enum Identity: Sendable {
        case checking
        case verified(CallerIdentity)
        case failed(String)
    }

    var profile: CredentialProfile
    var name: String
    var isSelected: Bool
    var alreadyImported: Bool
    var identity = Identity.checking

    var id: String { profile.id }
}

private struct ImportRow: View {
    @Binding var candidate: ImportCandidate

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("Import", isOn: $candidate.isSelected)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(candidate.alreadyImported)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                TextField("Name", text: $candidate.name)
                    .textFieldStyle(.plain)
                    .font(.headline)
                    .disabled(candidate.alreadyImported)

                identityLine

                Text(sources)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }

            Spacer()

            if candidate.alreadyImported {
                Text("Already added")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
        .opacity(candidate.alreadyImported ? 0.6 : 1)
    }

    @ViewBuilder
    private var identityLine: some View {
        switch candidate.identity {
        case .checking:
            Text("Checking key…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case let .verified(identity):
            let account = Account(accountId: identity.account)
            Text(verbatim: "\(account.formattedAccountId) · \(identity.userName)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case let .failed(message):
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.red)
                .lineLimit(2)
        }
    }

    private var sources: String {
        let files = candidate.profile.sources.map { "\($0.file) [\($0.profile)]" }.joined(separator: ", ")
        return "\(candidate.profile.maskedAccessKeyId) · \(files)"
    }
}
