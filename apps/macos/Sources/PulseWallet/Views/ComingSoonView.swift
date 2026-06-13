import SwiftUI

/// Reusable "coming soon" placeholder for sections we'll wire up later.
struct ComingSoonView: View {
    let icon: String
    let title: String
    let blurb: String
    var bullets: [String] = []

    var body: some View {
        ScrollView {
            VStack(spacing: Metric.gutter) {
                GlassCard {
                    VStack(spacing: 14) {
                        ZStack {
                            Circle().fill(Brand.brandGradient).frame(width: 64, height: 64)
                                .shadow(color: Brand.accent.opacity(0.4), radius: 16)
                            Image(systemName: icon).font(.system(size: 28, weight: .bold)).foregroundStyle(.white)
                        }
                        Text(title).font(.title2.weight(.semibold))
                        Text("Coming soon")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Brand.warn.opacity(0.18), in: .capsule)
                            .foregroundStyle(Brand.warn)
                        Text(blurb)
                            .font(.callout).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 420)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                if !bullets.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(bullets, id: \.self) { b in
                                Label(b, systemImage: "checkmark.circle")
                                    .font(.callout).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .scrollContentBackground(.hidden)
    }
}
