import SwiftUI

/// A single thing the wallet noticed about the account's setup, with a one-tap fix.
/// This is the engine behind "the wallet guides you based on your existing setup".
struct HealthIssue: Identifiable {
    enum Severity { case critical, warn, info, ok
        var tint: Color {
            switch self {
            case .critical: Brand.danger
            case .warn:     Brand.warn
            case .info:     Brand.accent
            case .ok:       Brand.success
            }
        }
        var icon: String {
            switch self {
            case .critical: "exclamationmark.octagon.fill"
            case .warn:     "exclamationmark.triangle.fill"
            case .info:     "info.circle.fill"
            case .ok:       "checkmark.seal.fill"
            }
        }
    }
    /// What tapping the fix should do — kept abstract so the banner owns navigation.
    enum Fix { case importKey, openKeys }

    let id: String
    let severity: Severity
    let title: String
    let detail: String
    let fixLabel: String?
    let fix: Fix?
}

/// Pure evaluation of an account's key setup → a prioritized list of issues.
/// No side effects, easy to reason about and (later) test.
func evaluateAccountHealth(account: AccountInfo?,
                           accountName: String,
                           keys: [WalletKey],
                           unreadable: Set<String>) -> [HealthIssue] {
    guard let account else { return [] }
    let held = Set(keys.map(\.pubKey))
    let ownerKeys = account.permissions.first { $0.permName == "owner" }?.requiredAuth.keys.map(\.key) ?? []
    let activeKeys = account.permissions.first { $0.permName == "active" }?.requiredAuth.keys.map(\.key) ?? []
    let controlsActive = activeKeys.contains(where: held.contains)
    let controlsOwner = ownerKeys.contains(where: held.contains)

    var issues: [HealthIssue] = []

    // 1) Can't sign at all → critical.
    if !controlsActive && !controlsOwner {
        issues.append(.init(id: "watch-only", severity: .critical,
            title: "Watch-only — you can't sign",
            detail: "This wallet holds no key that controls \(accountName). Import one of its keys to send and sign.",
            fixLabel: "Import key", fix: .importKey))
    }

    // 2) Key material missing from the Keychain → warn (orphaned by an old build).
    if !unreadable.isEmpty {
        issues.append(.init(id: "unreadable", severity: .warn,
            title: "A key needs re-import",
            detail: "\(unreadable.count) key(s) lost their private material in the Keychain. Re-import them to keep signing.",
            fixLabel: "Open Keys", fix: .openKeys))
    }

    // 3) Owner key sitting in a hot wallet → warn (recommend cold storage).
    if controlsOwner {
        issues.append(.init(id: "owner-hot", severity: .warn,
            title: "Owner key is in this hot wallet",
            detail: "The owner key is your master recovery key. For larger balances, keep it on a YubiKey or paper backup and sign day-to-day with @active.",
            fixLabel: "Open Keys", fix: .openKeys))
    }

    // 4) A held key not linked to the account → info (offer to link).
    let linkedPubs = Set(account.permissions.flatMap { $0.requiredAuth.keys.map(\.key) })
    let unlinked = keys.filter { !linkedPubs.contains($0.pubKey) }
    if !unlinked.isEmpty {
        issues.append(.init(id: "unlinked", severity: .info,
            title: "\(unlinked.count) key not linked to \(accountName)",
            detail: "You hold key(s) this account doesn't use yet. Link one to add it to a permission, or ignore if it's for another account.",
            fixLabel: "Open Keys", fix: .openKeys))
    }

    // 5) All good → a single reassuring line.
    if issues.isEmpty && controlsActive {
        issues.append(.init(id: "healthy", severity: .ok,
            title: "Account setup looks healthy",
            detail: controlsOwner
                ? "You can sign with a controlling key. Consider moving @owner to cold storage for extra safety."
                : "You sign with @active and your @owner key is held elsewhere as recovery.",
            fixLabel: nil, fix: nil))
    }
    return issues
}

/// Top-of-wallet status strip. Shows the most important setup issues with one-tap fixes.
struct SetupHealthBanner: View {
    @Environment(AppModel.self) private var model
    @Environment(KeyStore.self) private var store
    /// Show at most this many rows (highest-priority first).
    var maxIssues = 2
    /// Hide the all-clear ("healthy") row — useful on dense screens.
    var hideWhenHealthy = false

    private var issues: [HealthIssue] {
        evaluateAccountHealth(account: model.account, accountName: model.accountName,
                              keys: store.keys, unreadable: store.unreadableKeyIDs)
    }

    var body: some View {
        let shown = issues.prefix(maxIssues)
        if !shown.isEmpty, !(hideWhenHealthy && shown.allSatisfy { $0.severity == .ok }) {
            GlassCard(padding: 14) {
                VStack(spacing: 10) {
                    ForEach(Array(shown)) { issue in
                        HStack(spacing: 12) {
                            Image(systemName: issue.severity.icon).foregroundStyle(issue.severity.tint)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(issue.title).font(.callout.weight(.medium))
                                Text(issue.detail).font(.caption).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            if let label = issue.fixLabel, let fix = issue.fix {
                                Button(label) { apply(fix) }.buttonStyle(.glass)
                            }
                        }
                    }
                }
            }
        }
    }

    private func apply(_ fix: HealthIssue.Fix) {
        switch fix {
        case .importKey: model.section = .keys; model.requestImportKey = true
        case .openKeys:  model.section = .keys
        }
    }
}
