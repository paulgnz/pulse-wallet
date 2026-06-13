import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ActivityView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                HStack {
                    SectionHeader(title: "Activity", systemImage: "clock.arrow.circlepath")
                    if !model.activity.isEmpty {
                        Button { exportCSV() } label: {
                            Label("Export CSV", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.glass)
                    }
                }
                if model.activity.isEmpty {
                    GlassCard(padding: 14) {
                        Text("No activity yet.").font(.callout).foregroundStyle(.secondary)
                    }
                }
                ForEach(model.activity) { item in
                    ActivityRow(item: item)
                }
            }
            .padding(20)
        }
        .scrollContentBackground(.hidden)
    }

    /// Export the activity list as a CSV for audit / accounting.
    private func exportCSV() {
        let header = "kind,counterparty,asset,memo,time,txid\n"
        let iso = ISO8601DateFormatter()
        let rows = model.activity.map { i in
            func esc(_ s: String) -> String { "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\"" }
            return [i.kind.rawValue, i.counterparty, i.asset, i.memo, iso.string(from: i.time), i.txid]
                .map(esc).joined(separator: ",")
        }.joined(separator: "\n")
        let csv = header + rows + "\n"

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "\(model.accountName)-activity.csv"
        if panel.runModal() == .OK, let url = panel.url {
            try? csv.data(using: .utf8)?.write(to: url)
        }
    }
}

struct ActivityRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    let item: ActivityItem

    private var explorerURL: URL? { model.explorerTxURL(item.txid) }

    var body: some View {
        GlassCard(padding: 14) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(tint.opacity(0.18)).frame(width: 38, height: 38)
                    Image(systemName: item.kind.symbol)
                        .foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.kind.rawValue.capitalized + " · " + item.counterparty)
                        .font(.body.weight(.medium))
                    Text(item.memo.isEmpty ? String(item.txid.prefix(12)) + "…" : item.memo)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(item.asset).font(.callout.monospacedDigit())
                    Text(item.time, style: .relative)
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if explorerURL != nil {
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if let u = explorerURL { openURL(u) } }
        .help(explorerURL != nil ? "View transaction in explorer" : "")
    }

    private var tint: Color {
        switch item.kind {
        case .received: return Brand.success
        case .sent:     return Brand.accent
        case .staked:   return Brand.glow
        case .contract: return Brand.warn
        }
    }
}
