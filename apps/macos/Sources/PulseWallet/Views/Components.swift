import SwiftUI

/// Reusable Liquid-Glass card surface.
struct GlassCard<Content: View>: View {
    var padding: CGFloat = Metric.cardPadding
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: Metric.corner))
    }
}

/// Section heading used above card groups.
struct SectionHeader: View {
    let title: String
    var systemImage: String? = nil
    var body: some View {
        HStack(spacing: 8) {
            if let systemImage { Image(systemName: systemImage).foregroundStyle(Brand.accent) }
            Text(title).font(.title3.weight(.semibold))
            Spacer()
        }
    }
}

/// A labelled resource meter (CPU / NET / RAM).
struct ResourceBar: View {
    let label: String
    let fraction: Double
    var tint: Color = Brand.accent
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.caption.weight(.semibold))
                Spacer()
                Text(detail ?? "\(Int((fraction * 100).rounded()))%")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            ProgressView(value: fraction).tint(tint)
        }
    }
}

/// A themed text-field chrome: plain field inside a rounded, theme-aware
/// container with an animated accent focus ring. Replaces `.roundedBorder`
/// (whose stock grey bezel ignores the theme and looks wrong on dark palettes).
/// Use via `.pulseField()` so every form field looks consistent.
struct PulseFieldChrome: ViewModifier {
    var mono: Bool = false
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(mono ? .callout.monospaced() : .callout)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(focused ? Brand.accent : .primary.opacity(0.12),
                                  lineWidth: focused ? 1.6 : 1))
            .focused($focused)
            .animation(.easeOut(duration: 0.12), value: focused)
    }
}

extension View {
    /// Apply the themed field chrome (see `PulseFieldChrome`). `mono: true` for
    /// addresses, keys, and other monospace input.
    func pulseField(mono: Bool = false) -> some View { modifier(PulseFieldChrome(mono: mono)) }
}

/// Renders one decoded action — transfers get a friendly summary; everything
/// else shows account·name + the raw data so nothing is hidden. Shared by
/// decode-before-sign (dapp) and decode-before-approve (multisig).
struct ActionCard: View {
    let action: DecodedTx.Action

    var body: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: icon).foregroundStyle(Brand.accent)
                    Text("\(action.account) · \(action.name)")
                        .font(.callout.weight(.semibold).monospaced())
                    Spacer()
                }
                if let t = action.transfer {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(t.quantity).font(.title3.weight(.bold))
                            Spacer()
                        }
                        Text("\(t.from)  →  \(t.to)").font(.caption.monospaced()).foregroundStyle(.secondary)
                        if !t.memo.isEmpty {
                            Text("memo: \(t.memo)").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("data: \(dataPreview)").font(.caption2.monospaced())
                        .foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
                }
                if !action.authorization.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(action.authorization.indices, id: \.self) { i in
                            let a = action.authorization[i]
                            Text("\(a.actor)@\(a.permission)")
                                .font(.caption2.monospaced())
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(.secondary.opacity(0.15), in: .capsule)
                        }
                    }
                }
            }
        }
    }

    private var icon: String {
        if action.transfer != nil { return "arrow.left.arrow.right" }
        switch action.name {
        case "updateauth", "deleteauth", "linkauth", "unlinkauth": return "key.fill"
        case "delegatebw", "undelegatebw", "refund": return "bolt.fill"
        case "buyram", "buyrambytes", "sellram": return "memorychip"
        default: return "doc.text"
        }
    }
    private var dataPreview: String {
        action.dataHex.isEmpty ? "(none)" : "0x" + action.dataHex
    }
}

/// Primary action — uses the macOS Tahoe prominent glass button style.
struct PrimaryButton: View {
    let title: String
    var systemImage: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.glassProminent)
        .tint(Brand.primary)
        .controlSize(.large)
    }
}
