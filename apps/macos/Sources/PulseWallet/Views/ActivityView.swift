import SwiftUI

struct ActivityView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(model.activity) { item in
                    ActivityRow(item: item)
                }
            }
            .padding(20)
        }
        .scrollContentBackground(.hidden)
    }
}

struct ActivityRow: View {
    let item: ActivityItem

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
                    Text(item.memo.isEmpty ? item.txid : item.memo)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(item.asset).font(.callout.monospacedDigit())
                    Text(item.time, style: .relative)
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
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
