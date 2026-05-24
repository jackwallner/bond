import SwiftUI

/// Runtime-switchable accent so beta builds can compare palette directions
/// without shipping a new build per color. Backed by `UserDefaults`; read
/// from `Color.bondAccent` and mutated from the Settings theme picker.
@Observable
@MainActor
final class BondTheme {
    static let shared = BondTheme()

    enum Accent: String, CaseIterable, Identifiable {
        case terracotta
        case pink

        var id: String { rawValue }

        var title: String {
            switch self {
            case .terracotta: "Terracotta"
            case .pink:       "Pink"
            }
        }

        /// Solid accent — uses the gradient's deep end so flat fills, tints,
        /// and SF Symbols read as one consistent terracotta.
        var color: Color {
            switch self {
            case .terracotta:
                Color(
                    light: Color(red: 0.722, green: 0.333, blue: 0.188),  // #B85530
                    dark:  Color(red: 0.882, green: 0.475, blue: 0.345)
                )
            case .pink:
                .pink
            }
        }

        /// Top-lit two-tone accent gradient (light end → deep end), echoing the
        /// soft 3D icon. Backs primary buttons and avatars in Direction A.
        var gradient: LinearGradient {
            let stops: [Color]
            switch self {
            case .terracotta:
                stops = [
                    Color(light: Color(red: 0.859, green: 0.439, blue: 0.282),   // #DB7048
                          dark:  Color(red: 0.945, green: 0.557, blue: 0.420)),
                    Color(light: Color(red: 0.722, green: 0.333, blue: 0.188),   // #B85530
                          dark:  Color(red: 0.808, green: 0.408, blue: 0.282))
                ]
            case .pink:
                stops = [Color.pink.opacity(0.85), Color.pink]
            }
            return LinearGradient(colors: stops, startPoint: .top, endPoint: .bottom)
        }
    }

    private let defaultsKey = "theme.accent"

    var accent: Accent {
        didSet { UserDefaults.standard.set(accent.rawValue, forKey: defaultsKey) }
    }

    private init() {
        accent = UserDefaults.standard.string(forKey: defaultsKey)
            .flatMap(Accent.init(rawValue:)) ?? .terracotta
    }
}
