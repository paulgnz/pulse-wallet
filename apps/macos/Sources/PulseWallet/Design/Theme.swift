import SwiftUI

/// Brand palette, shared with pulsevm.dev (navy / electric blue).
enum Brand {
    static let navy      = Color(hex: 0x0B1437)   // deep background navy
    static let ink       = Color(hex: 0x14224F)   // card navy
    static let primary   = Color(hex: 0x2348C8)   // brand blue
    static let accent    = Color(hex: 0x4F7CFF)   // electric accent
    static let glow      = Color(hex: 0x8B95FF)   // ledger violet
    static let success   = Color(hex: 0x3DD68C)
    static let warn      = Color(hex: 0xF5A524)
    static let danger    = Color(hex: 0xFF5A5A)

    /// Signature gradient used on hero balance + brand marks.
    static var brandGradient: LinearGradient {
        LinearGradient(colors: [accent, glow], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue:  Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

/// Adaptive app background — navy in dark, soft blue-white in light.
struct BrandBackground: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Group {
            if scheme == .dark {
                LinearGradient(colors: [Brand.navy, Color(hex: 0x131D3F)],
                               startPoint: .top, endPoint: .bottom)
            } else {
                LinearGradient(colors: [Color(hex: 0xF4F6FE), Color(hex: 0xE7ECFC)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .ignoresSafeArea()
    }
}

/// Layout constants — generous spacing per macOS Tahoe guidance.
enum Metric {
    static let corner: CGFloat = 16
    static let cardPadding: CGFloat = 20
    static let gutter: CGFloat = 16
}
