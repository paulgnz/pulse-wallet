import Foundation

/// A user-facing error with a short title, actionable detail, and severity.
/// Severity drives color: `.warning` (amber, e.g. chain paused) vs `.error` (red).
struct WalletError: LocalizedError, Identifiable {
    enum Severity { case warning, error }
    let id = UUID()
    let title: String
    let detail: String
    let severity: Severity

    var errorDescription: String? { detail.isEmpty ? title : "\(title) — \(detail)" }

    static func warning(_ title: String, _ detail: String = "") -> WalletError {
        WalletError(title: title, detail: detail, severity: .warning)
    }
    static func error(_ title: String, _ detail: String = "") -> WalletError {
        WalletError(title: title, detail: detail, severity: .error)
    }
}

/// Maps raw chain / network errors into human guidance. Pass `paused: true`
/// when the chain head hasn't advanced recently so connection failures read as
/// "signed, pending resume" instead of a scary error.
enum FriendlyError {
    static func explain(_ error: Error, paused: Bool, headBlock: Int? = nil) -> WalletError {
        if let w = error as? WalletError { return w }

        let raw = (error.localizedDescription).lowercased()
        let urlErr = error as? URLError
        let connectionFailure = urlErr != nil
            || raw.contains("timed out") || raw.contains("could not connect")
            || raw.contains("network connection") || raw.contains("offline")
            || raw.contains("http 5")

        // Chain halted: the tx is signed & valid, it just can't be confirmed yet.
        if paused && connectionFailure {
            let at = headBlock.map { " (paused at block \($0))" } ?? ""
            return .warning("Signed — waiting for the chain",
                "The network is currently paused\(at). Your transaction is signed and valid; it will broadcast once validators resume. Nothing was lost.")
        }

        // Known chain / validation messages.
        if raw.contains("is_canonical") || raw.contains("not canonical") {
            return .error("Signature wasn't canonical", "Please try signing again.")
        }
        if raw.contains("does not have signatures") || raw.contains("unsatisfied_authorization")
            || raw.contains("missing authority") || raw.contains("irrelevant signature") {
            return .error("Wrong signing key",
                "Your active key doesn't control this account/permission. Set the right key as active in Keys, or pick a different permission in the account switcher.")
        }
        if raw.contains("expired") {
            return .warning("Transaction expired",
                "It wasn't accepted in time" + (paused ? " (the chain is paused)." : ".") + " Try again.")
        }
        if raw.contains("overdrawn") || raw.contains("insufficient") || raw.contains("no balance") {
            return .error("Insufficient balance", "This account doesn't have enough to cover the transfer.")
        }
        if raw.contains("must stake a positive") {
            return .error("Amount required", "Enter a positive amount to stake.")
        }
        if raw.contains("duplicate") {
            return .warning("Already submitted", "This exact transaction was already sent.")
        }
        if raw.contains("pulse assert") || raw.contains("assertion") || raw.contains("eosio_assert") {
            return .error("Contract rejected the action", cleanAssert(error.localizedDescription))
        }
        if raw.contains("ram") && raw.contains("insufficient") {
            return .error("Not enough RAM", "This account needs more RAM. Buy RAM under Wallet → Resources.")
        }
        if raw.contains("invalid endpoint") {
            return .error("Bad network endpoint", "Fix this network's RPC URL in Settings → Networks.")
        }
        if connectionFailure {
            return .error("Can't reach the network",
                "Check your connection or the endpoint in Settings → Networks.")
        }

        // Fallback — show the raw message but framed.
        return .error("Transaction failed", error.localizedDescription)
    }

    /// Strip the boilerplate around a contract assert so only the message shows.
    private static func cleanAssert(_ s: String) -> String {
        if let r = s.range(of: "assertion failure with message: ") {
            return String(s[r.upperBound...])
        }
        return s
    }
}
