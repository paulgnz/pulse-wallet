import Foundation
import LocalAuthentication

enum Biometrics {
    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    /// Prompt Touch ID (falling back to device password if needed). Returns true
    /// on success. Used to gate destructive/sensitive actions like key deletion.
    static func authenticate(reason: String) async -> Bool {
        let ctx = LAContext()
        var error: NSError?
        let policy: LAPolicy = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
            ? .deviceOwnerAuthenticationWithBiometrics
            : .deviceOwnerAuthentication
        return await withCheckedContinuation { cont in
            ctx.evaluatePolicy(policy, localizedReason: reason) { ok, _ in
                cont.resume(returning: ok)
            }
        }
    }
}
