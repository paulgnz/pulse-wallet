import SwiftUI

/// Full-window lock overlay; unlocks via Touch ID (LocalAuthentication).
struct LockScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            VStack(spacing: 24) {
                ZStack {
                    Circle().fill(Brand.brandGradient).frame(width: 84, height: 84)
                        .shadow(color: Brand.accent.opacity(0.5), radius: 20)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white)
                }
                Text("Pulse Wallet is locked").font(.title2.weight(.semibold))
                Button {
                    model.unlock()   // hook to LAContext.evaluatePolicy in app code
                } label: {
                    Label("Unlock with Touch ID", systemImage: "touchid")
                        .padding(.horizontal, 8).padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent)
                .tint(Brand.primary)
                .controlSize(.large)
            }
            .padding(40)
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
        }
    }
}
