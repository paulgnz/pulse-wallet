import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var requireBiometricsEachTx = true
    @State private var autoLock = true

    var body: some View {
        ScrollView {
            VStack(spacing: Metric.gutter) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: "Network", systemImage: "network")
                        labelled("Chain", model.chainName)
                        Divider()
                        labelled("RPC endpoint", model.endpoint, mono: true)
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: "Security", systemImage: "lock.shield")
                        Toggle("Require Touch ID for every transaction", isOn: $requireBiometricsEachTx)
                        Divider()
                        Toggle("Auto-lock when idle", isOn: $autoLock)
                        Divider()
                        HStack {
                            Label("Signing key", systemImage: "touchid")
                            Spacer()
                            Text(model.selectedAccount?.isHardwareBacked == true
                                 ? "Secure Enclave (hardware)" : "Software key")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "About", systemImage: "info.circle")
                        Text("Pulse Wallet — a native macOS wallet for PulseVM.")
                            .font(.callout)
                        Text("Keys are generated and held in the Secure Enclave; signatures are produced on-device with Touch ID and never leave the chip.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(20)
        }
        .scrollContentBackground(.hidden)
        .frame(minWidth: 480, minHeight: 520)
    }

    private func labelled(_ k: String, _ v: String, mono: Bool = false) -> some View {
        HStack {
            Text(k).foregroundStyle(.secondary)
            Spacer()
            Text(v).font(mono ? .callout.monospaced() : .callout)
        }
    }
}
