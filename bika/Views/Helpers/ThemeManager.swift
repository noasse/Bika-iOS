import SwiftUI

enum ThemeMode: String, CaseIterable {
    case system
    case light
    case dark

    var displayName: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }
}

@Observable
final class ThemeManager {
    static let shared = ThemeManager()

    var themeMode: ThemeMode {
        didSet { UserDefaults.standard.set(themeMode.rawValue, forKey: "themeMode") }
    }

    var colorScheme: ColorScheme? {
        switch themeMode {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: "themeMode") ?? "dark"
        themeMode = ThemeMode(rawValue: saved) ?? .dark
    }
}

// MARK: - Semantic Colors

extension Color {
    static let accentPink = Color(red: 237/255, green: 110/255, blue: 160/255) // #ed6ea0

    static func mainBg(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 26/255, green: 26/255, blue: 46/255) : Color(red: 245/255, green: 245/255, blue: 245/255)
    }

    static func cardBg(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 42/255, green: 42/255, blue: 62/255) : .white
    }

    static func secondaryText(for scheme: ColorScheme) -> Color {
        scheme == .dark ? .gray : .secondary
    }
}
