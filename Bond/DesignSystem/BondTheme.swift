import SwiftUI

/// Runtime-switchable accent so beta builds can compare palette directions
/// without shipping a new build per color. Backed by `UserDefaults`; read
/// from `Color.bondAccent` and mutated from the Settings theme picker.
@Observable
@MainActor
final class BondTheme {
    static let shared = BondTheme()

    enum Accent: String, CaseIterable, Identifiable {
        case sage
        case terracotta
        case pink

        var id: String { rawValue }

        var title: String {
            switch self {
            case .sage:       "Sage"
            case .terracotta: "Terracotta"
            case .pink:       "Pink"
            }
        }

        var color: Color {
            switch self {
            case .sage:
                Color(
                    light: Color(red: 0.36, green: 0.54, blue: 0.43),
                    dark:  Color(red: 0.50, green: 0.69, blue: 0.57)
                )
            case .terracotta:
                Color(
                    light: Color(red: 0.71, green: 0.34, blue: 0.25),
                    dark:  Color(red: 0.85, green: 0.44, blue: 0.34)
                )
            case .pink:
                .pink
            }
        }
    }

    private let defaultsKey = "theme.accent"

    var accent: Accent {
        didSet { UserDefaults.standard.set(accent.rawValue, forKey: defaultsKey) }
    }

    private init() {
        accent = UserDefaults.standard.string(forKey: defaultsKey)
            .flatMap(Accent.init(rawValue:)) ?? .sage
    }
}
