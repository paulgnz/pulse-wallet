import SwiftUI
import AppKit

/// A data-driven, white-labelable theme. Built-ins live below; companies can ship
/// a JSON file with the same fields (see ThemeStore) for their own branding.
struct Theme: Codable, Identifiable, Sendable, Hashable {
    var id: String { name }
    var name: String
    // Core palette (sRGB hex)
    var navy: UInt32        // dark background base
    var ink: UInt32         // dark background second stop / card navy
    var primary: UInt32     // primary brand / prominent buttons
    var accent: UInt32      // accent (links, highlights)
    var glow: UInt32        // gradient partner for accent
    var success: UInt32
    var warn: UInt32
    var danger: UInt32
    // Light-mode background stops
    var bgLightTop: UInt32
    var bgLightBottom: UInt32
    // Optional light-mode overrides for the foreground brand colors. The dark
    // values (above) are tuned for a dark background; on a light background a
    // near-white accent/glow becomes invisible, so themes can supply readable
    // light variants here. Absent → fall back to the dark value.
    var primaryLight: UInt32? = nil
    var accentLight: UInt32? = nil
    var glowLight: UInt32? = nil

    /// The currently active theme (read by `Brand`). Set by ThemeStore.
    nonisolated(unsafe) static var active: Theme = .pulse

    /// Default navy / electric-blue brand.
    static let pulse = Theme(
        name: "Pulse", navy: 0x0B1437, ink: 0x14224F, primary: 0x2348C8, accent: 0x4F7CFF,
        glow: 0x8B95FF, success: 0x3DD68C, warn: 0xF5A524, danger: 0xFF5A5A,
        bgLightTop: 0xF4F6FE, bgLightBottom: 0xE7ECFC,
        primaryLight: 0x2348C8, accentLight: 0x2348C8, glowLight: 0x4F7CFF)

    /// Flashy monochrome — black background, white/silver accents (WebAuth-style).
    /// Light mode flips the foreground to near-black/grey so text stays readable.
    static let mono = Theme(
        name: "Mono", navy: 0x000000, ink: 0x101012, primary: 0xD6D6D6, accent: 0xFFFFFF,
        glow: 0x8E8E8E, success: 0x5BD68C, warn: 0xE0A33A, danger: 0xFF6B6B,
        bgLightTop: 0xFFFFFF, bgLightBottom: 0xEDEDED,
        primaryLight: 0x222222, accentLight: 0x111111, glowLight: 0x6E6E6E)

    static let builtIns: [Theme] = [.pulse, .mono]
}

/// Brand colors — computed from the active theme so a theme switch re-skins the app.
enum Brand {
    static var navy: Color { Color(hex: Theme.active.navy) }
    static var ink: Color { Color(hex: Theme.active.ink) }
    // Foreground brand colors adapt to light/dark so e.g. a white accent (great
    // on Mono's black) flips to near-black on a light background instead of vanishing.
    static var primary: Color { Color(lightHex: Theme.active.primaryLight ?? Theme.active.primary, darkHex: Theme.active.primary) }
    static var accent: Color { Color(lightHex: Theme.active.accentLight ?? Theme.active.accent, darkHex: Theme.active.accent) }
    static var glow: Color { Color(lightHex: Theme.active.glowLight ?? Theme.active.glow, darkHex: Theme.active.glow) }
    static var success: Color { Color(hex: Theme.active.success) }
    static var warn: Color { Color(hex: Theme.active.warn) }
    static var danger: Color { Color(hex: Theme.active.danger) }

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

    /// A color that resolves differently in light vs dark appearance.
    init(lightHex: UInt32, darkHex: UInt32) {
        if lightHex == darkHex { self.init(hex: darkHex); return }
        self.init(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let hex = dark ? darkHex : lightHex
            return NSColor(srgbRed: Double((hex >> 16) & 0xFF) / 255,
                           green:  Double((hex >> 8) & 0xFF) / 255,
                           blue:   Double(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

/// Adaptive app background — theme dark stops in dark mode, light stops in light mode.
struct BrandBackground: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Group {
            if scheme == .dark {
                LinearGradient(colors: [Brand.navy, Brand.ink], startPoint: .top, endPoint: .bottom)
            } else {
                LinearGradient(colors: [Color(hex: Theme.active.bgLightTop), Color(hex: Theme.active.bgLightBottom)],
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
