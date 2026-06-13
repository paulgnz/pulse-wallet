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
