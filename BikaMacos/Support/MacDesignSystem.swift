import SwiftUI

enum MacUI {
    static let accentPink = Color(red: 237 / 255, green: 110 / 255, blue: 160 / 255)
    static let cornerRadius: CGFloat = 8

    static func appBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark
        ? Color(red: 26 / 255, green: 26 / 255, blue: 46 / 255)
        : Color(red: 245 / 255, green: 245 / 255, blue: 245 / 255)
    }

    static func surface(for scheme: ColorScheme) -> Color {
        scheme == .dark
        ? Color(red: 42 / 255, green: 42 / 255, blue: 62 / 255)
        : Color.white
    }

    static func subtleSurface(for scheme: ColorScheme) -> Color {
        scheme == .dark
        ? Color.white.opacity(0.055)
        : Color.black.opacity(0.035)
    }

    static func hairline(for scheme: ColorScheme) -> Color {
        scheme == .dark
        ? Color.white.opacity(0.10)
        : Color.black.opacity(0.08)
    }

    static func accentWash(for scheme: ColorScheme) -> Color {
        accentPink.opacity(scheme == .dark ? 0.18 : 0.13)
    }

    static func secondaryText(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.64) : Color.secondary
    }
}

extension View {
    func macSurface(_ scheme: ColorScheme) -> some View {
        background(MacUI.surface(for: scheme), in: RoundedRectangle(cornerRadius: MacUI.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: MacUI.cornerRadius)
                    .stroke(MacUI.hairline(for: scheme))
            }
    }
}
