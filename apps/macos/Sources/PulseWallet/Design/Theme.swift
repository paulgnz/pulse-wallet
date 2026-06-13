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

    /// PulseVM house brand — navy / electric blue.
    static let pulse = Theme(
        name: "Pulse", navy: 0x0B1437, ink: 0x14224F, primary: 0x2348C8, accent: 0x4F7CFF,
        glow: 0x8B95FF, success: 0x3DD68C, warn: 0xF5A524, danger: 0xFF5A5A,
        bgLightTop: 0xF4F6FE, bgLightBottom: 0xE7ECFC,
        primaryLight: 0x2348C8, accentLight: 0x2348C8, glowLight: 0x4F7CFF)

    /// Flashy monochrome — black background, white/silver accents (WebAuth-style).
    /// Light mode flips the foreground to near-black/grey so text stays readable.
    static let mono = Theme(
        name: "Mono", navy: 0x0A0A0B, ink: 0x161618, primary: 0xD6D6D6, accent: 0xF5F5F7,
        glow: 0x8E8E93, success: 0x5BD68C, warn: 0xE0A33A, danger: 0xFF6B6B,
        bgLightTop: 0xFFFFFF, bgLightBottom: 0xECECEC,
        primaryLight: 0x1C1C1E, accentLight: 0x1C1C1E, glowLight: 0x6E6E73)

    /// Nord — the arctic, north-bluish palette (nordtheme.com).
    static let nord = Theme(
        name: "Nord", navy: 0x2E3440, ink: 0x3B4252, primary: 0x88C0D0, accent: 0x88C0D0,
        glow: 0x81A1C1, success: 0xA3BE8C, warn: 0xEBCB8B, danger: 0xBF616A,
        bgLightTop: 0xECEFF4, bgLightBottom: 0xE5E9F0,
        primaryLight: 0x5E81AC, accentLight: 0x5E81AC, glowLight: 0x81A1C1)

    /// Dracula — the famous dark theme (draculatheme.com).
    static let dracula = Theme(
        name: "Dracula", navy: 0x282A36, ink: 0x343746, primary: 0xBD93F9, accent: 0xBD93F9,
        glow: 0x8BE9FD, success: 0x50FA7B, warn: 0xF1FA8C, danger: 0xFF5555,
        bgLightTop: 0xF8F8F2, bgLightBottom: 0xECECE6,
        primaryLight: 0x6A4CB8, accentLight: 0x6A4CB8, glowLight: 0x3F91A8)

    /// Tokyo Night — the popular editor theme.
    static let tokyoNight = Theme(
        name: "Tokyo Night", navy: 0x1A1B26, ink: 0x24283B, primary: 0x7AA2F7, accent: 0x7AA2F7,
        glow: 0xBB9AF7, success: 0x9ECE6A, warn: 0xE0AF68, danger: 0xF7768E,
        bgLightTop: 0xE1E2E7, bgLightBottom: 0xD5D6DB,
        primaryLight: 0x3D59A1, accentLight: 0x3D59A1, glowLight: 0x7AA2F7)

    /// Solarized — Ethan Schoonover's precision palette (dark).
    static let solarized = Theme(
        name: "Solarized", navy: 0x002B36, ink: 0x073642, primary: 0x268BD2, accent: 0x268BD2,
        glow: 0x2AA198, success: 0x859900, warn: 0xB58900, danger: 0xDC322F,
        bgLightTop: 0xFDF6E3, bgLightBottom: 0xEEE8D5,
        primaryLight: 0x268BD2, accentLight: 0x1A6FA8, glowLight: 0x2AA198)

    static let builtIns: [Theme] = [.pulse, .mono, .nord, .dracula, .tokyoNight, .solarized]
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
