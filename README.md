# AWS Account Mixer

A native macOS app (SwiftUI) that keeps all your AWS accounts in one list. One click opens the AWS console already signed in to the account you picked.

The UI is in English, with a Polish translation that is used automatically when macOS is set to Polish.

## Features

- **One click to the console.** An IAM access key is exchanged for a one-time sign-in link (STS `GetFederationToken` → console federation), so no password is needed. Accounts can also use the IAM sign-in page (password filled in by your browser or the Passwords app) or switch role.
- **Import from `~/.aws`.** Reads `credentials` and every `credentials.*` file. A key that appears in several files is listed once, and every key is checked with `GetCallerIdentity` (account ID, user).
- **Groups.** A sidebar with groups. Move accounts by dragging them or from the context menu ("Move to Group"). Groups can be renamed or deleted.
- **Favorites and recently opened.** Star an account. Favorites and recent accounts appear at the top of the menu bar menu and the quick switcher.
- **Renaming.** Context menu → "Rename…" or the editor.
- **Landing service.** Choose what a click opens for each account (e.g. straight to ECS or CloudWatch). The arrow next to the button picks a different service just once.
- **Default region.** Settings → "Default region" applies to accounts without their own region. "Set Region" in the context menu changes the region of many accounts at once.
- **Costs and forecast.** Every account shows its month-to-date cost and the month-end forecast (Cost Explorer). Clicking it shows last month, the month-over-month change and a daily chart. The bottom bar totals the visible accounts.
- **Quick switcher.** The global shortcut **⌃⌥A** (configurable in Settings) opens a Spotlight-style panel: type a few letters and press Return.
- **Menu bar.** All accounts at hand from any app.
- **Launch at login.** Settings (⌘,) → "Launch at login".
- **Terminal credentials.** "Copy Temporary Terminal Credentials" copies `export AWS_…` lines with temporary credentials (`GetSessionToken`), not your long-term keys.
- **Notes** and account colors. Prod is red by default.
- Shortcuts: **⌘1…⌘9** open the first accounts, **⌘K** quick switcher, **⌘N** new account, **⇧⌘I** import, **⇧⌘R** refresh costs.

## Building

Requires Xcode 26 (Swift 6.2) and macOS 14+.

```bash
./scripts/build-app.sh            # → build/AWS Account Mixer.app
./scripts/build-app.sh --install  # also copies it to /Applications
```

The script signs the app with your "Apple Development" certificate if it finds one, so the Keychain doesn't ask for access after every rebuild. To use a different certificate: `CODESIGN_IDENTITY="…" ./scripts/build-app.sh`.

To use your own bundle identifier: `BUNDLE_ID=com.example.aws-account-mixer ./scripts/build-app.sh`. Settings and the Keychain location of secrets depend on the identifier, so after changing it you need to import your keys again.

It's a plain SwiftPM package, so you can also open it in Xcode (`open Package.swift`).

## IAM permissions

| Feature | Permission |
| --- | --- |
| Signing in with keys | `sts:GetFederationToken` |
| Terminal credentials | `sts:GetSessionToken` (no extra permissions) |
| Costs | `ce:GetCostAndUsage`, `ce:GetCostForecast` |

The console session has exactly the IAM user's permissions. The `AdministratorAccess` session policy is intersected with the user's own policies, so it doesn't widen anything. Limitations:

- policies that require MFA (`aws:MultiFactorAuthPresent`) won't pass in such a session;
- AWS allows at most 1 h for root keys (the app handles this automatically).

## Cost Explorer pricing

Every Cost Explorer API request costs **USD 0.01**. Refreshing one account takes 2 requests (daily costs + forecast), and accounts with the same AWS account ID are queried once. By default costs refresh once a day and otherwise only manually; you can change or turn this off in Settings. Costs are counted for a single account (`LINKED_ACCOUNT` filter), so an organization's management account doesn't show the whole organization's total.

## Where data lives

- account list: `~/Library/Application Support/AWS Account Mixer/accounts.json` (no secrets);
- cost cache: `costs.json` in the same folder;
- Secret Access Keys: the login Keychain, with the app's bundle identifier (`CFBundleIdentifier`) as the service.

Deleting an account in the app also removes its secret from the Keychain.

## Several accounts at once

Signing in to another account in the same browser replaces the previous session. To keep several accounts open at the same time, turn on multi-session support in the AWS console: account menu → "Turn on multi-session support" (up to 5 sessions). You can also use "Copy Sign-in Link" and paste the link into another browser profile.

## Localization

UI strings are written in English in the code; the Polish translation lives in `Resources/pl.lproj` (`Localizable.strings` plus `Localizable.stringsdict` for plurals). After changing UI text, run:

```bash
./scripts/check-localizations.sh
```

It extracts the keys from the compiler and reports strings that are missing a translation or no longer used.

## Tests

```bash
swift test                                              # unit tests (SigV4 against the AWS test vector, credentials parser)
AWS_MIXER_LIVE=1 swift test --filter LiveSTSTests        # real STS calls with the keys in ~/.aws (free)
AWS_MIXER_LIVE_COSTS=1 swift test --filter LiveCostTests # Cost Explorer on one account (USD 0.02)
```

## License

MIT – see [LICENSE](LICENSE).
