import SwiftUI

struct ReceiveView: View {
    @Environment(AppModel.self) private var model
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(spacing: Metric.gutter) {
                GlassCard {
                    VStack(spacing: 18) {
                        SectionHeader(title: "Receive", systemImage: "qrcode")

                        // Named accounts are the address — no hex to copy/paste.
                        VStack(spacing: 6) {
                            Text("Your account")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(model.selectedAccount?.name ?? "—")
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .foregroundStyle(Brand.brandGradient)
                            Text("@\(model.selectedAccount?.permission ?? "active")")
                                .font(.callout.monospaced()).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)

                        Button {
                            copyName()
                        } label: {
                            Label(copied ? "Copied" : "Copy account name",
                                  systemImage: copied ? "checkmark" : "doc.on.doc")
                                .frame(maxWidth: .infinity).padding(.vertical, 4)
                        }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Public key", systemImage: "key.horizontal")
                            .font(.subheadline.weight(.medium))
                        Text(model.selectedAccount?.pubKey ?? "—")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(20)
        }
        .scrollContentBackground(.hidden)
    }

    private func copyName() {
        guard let name = model.selectedAccount?.name else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(name, forType: .string)
        withAnimation { copied = true }
    }
}
