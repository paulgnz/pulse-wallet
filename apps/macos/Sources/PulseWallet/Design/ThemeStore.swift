import Foundation
import Observation

/// Manages the active theme and the list of available themes (built-in + any
/// white-label JSON files dropped in Application Support/PulseVM/themes/).
/// A company ships a `theme.json` with the `Theme` fields to brand their build.
@MainActor
@Observable
final class ThemeStore {
    private(set) var available: [Theme]
    var current: Theme {
        didSet {
            Theme.active = current
            UserDefaults.standard.set(current.name, forKey: "wallet.theme")
        }
    }

    private static let dir: URL? = {
        guard let base = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                      appropriateFor: nil, create: true) else { return nil }
        let d = base.appendingPathComponent("PulseVM/themes", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    init() {
        var themes = Theme.builtIns
        themes.append(contentsOf: ThemeStore.loadCustom())
        available = themes
        let saved = UserDefaults.standard.string(forKey: "wallet.theme")
        current = themes.first { $0.name == saved } ?? .pulse
        Theme.active = current
    }

    func select(_ name: String) {
        if let t = available.first(where: { $0.name == name }) { current = t }
    }

    /// Load any *.json theme files (white-label drop-in).
    private static func loadCustom() -> [Theme] {
        guard let dir, let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return [] }
        return files.filter { $0.pathExtension == "json" }.compactMap { url in
            (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Theme.self, from: $0) }
        }
    }

    /// Import a white-label theme from a JSON file and switch to it.
    func importTheme(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let theme = try JSONDecoder().decode(Theme.self, from: data)
        if let dir = ThemeStore.dir {
            try? data.write(to: dir.appendingPathComponent(theme.name).appendingPathExtension("json"))
        }
        available.removeAll { $0.name == theme.name }
        available.append(theme)
        current = theme
    }
}
