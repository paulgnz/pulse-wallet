import SwiftUI
import AppKit

/// Developer/operator key tools: generate fresh keypairs and inspect/convert keys.
struct ToolsView: View {
    @Environment(KeyStore.self) private var store

    @State private var genCurve: WalletKey.Curve = .r1
    @State private var generated: GeneratedKey?
    @State private var inspectInput = ""
    @State private var inspectRows: [(String, String)] = []
    @State private var importStatus: String?

    var body: some View {
        ScrollView {
            VStack(spacing: Metric.gutter) {
                generateCard
                inspectCard
            }
            .padding(20)
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: Generate keypair
    private var generateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Generate keypair", systemImage: "key.horizontal.fill")
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Curve", selection: $genCurve) {
                        Text("R1 (secp256r1)").tag(WalletKey.Curve.r1)
                        Text("K1 (secp256k1)").tag(WalletKey.Curve.k1)
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        PrimaryButton(title: "Generate", systemImage: "sparkles") {
                            generated = KeyToolkit.generate(genCurve); importStatus = nil
                        }
                        if generated != nil {
                            Button("Clear") { generated = nil }.buttonStyle(.glass)
                        }
                    }
                    if let g = generated {
                        valueRow("Public", g.publicKey)
                        valueRow("Private — back this up", g.privateKey, secret: true)
                        Text("⚠︎ This is a software key shown once. Copy and store it safely; anyone with it can spend.")
                            .font(.caption2).foregroundStyle(Brand.warn)
                        HStack {
                            Button("Import into wallet") { importGenerated(g) }
                                .buttonStyle(.glassProminent).tint(Brand.primary)
                            if let s = importStatus { Text(s).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
        }
    }

    // MARK: Inspect / convert
    private var inspectCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Inspect / format a key", systemImage: "doc.text.magnifyingglass")
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Paste a PVT_R1_/PVT_K1_/WIF/hex private key or a PUB_… key.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        TextField("key…", text: $inspectInput)
                            .textFieldStyle(.roundedBorder).font(.caption.monospaced())
                        Button("Inspect") { inspectRows = KeyToolkit.inspect(inspectInput) }
                            .buttonStyle(.glass)
                    }
                    ForEach(inspectRows, id: \.0) { row in
                        valueRow(row.0, row.1)
                    }
                }
            }
        }
    }

    private func valueRow(_ label: String, _ value: String, secret: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.caption.weight(.medium)).foregroundStyle(secret ? Brand.warn : .secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                } label: { Image(systemName: "doc.on.doc").font(.caption2) }
                .buttonStyle(.plain)
            }
            Text(value).font(.caption.monospaced()).textSelection(.enabled)
                .lineLimit(2).truncationMode(.middle)
        }
        .padding(.vertical, 2)
    }

    private func importGenerated(_ g: GeneratedKey) {
        do {
            try store.importKey(secret: g.privateKey, label: "Generated \(g.curve.rawValue.uppercased())", curve: g.curve)
            importStatus = "Imported ✓"
        } catch {
            importStatus = error.localizedDescription
        }
    }
}
