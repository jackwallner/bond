import SwiftUI

/// Runtime-switchable accent so beta builds can compare palette directions
/// without shipping a new build per color. Backed by `UserDefaults`; read
/// from `Color.bondAccent` and mutated from the Settings theme picker.
@Observable
@MainActor
final class BondTheme {
    static let shared = BondTheme()

    /// Light/dark override. `.system` defers to the device setting; the other
    /// two pin the app regardless of system appearance. Maps to SwiftUI's
    /// `preferredColorScheme`, which in turn drives every `Color(light:dark:)`.
    enum Appearance: String, CaseIterable, Identifiable {
        case system
        case light
        case dark

        var id: String { rawValue }

        var title: String {
            switch self {
            case .system: String(localized: "System")
            case .light:  String(localized: "Light")
            case .dark:   String(localized: "Dark")
            }
        }

        /// `nil` lets SwiftUI fall through to the system setting.
        var colorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .light:  .light
            case .dark:   .dark
            }
        }
    }

    enum Accent: String, CaseIterable, Identifiable {
        case terracotta
        case pink

        var id: String { rawValue }

        var title: String {
            switch self {
            case .terracotta: String(localized: "Terracotta")
            case .pink:       String(localized: "Pink")
            }
        }

        /// Solid accent - a richer terracotta-rose so flat fills, tints, and
        /// SF Symbols read as one warm, saturated hue (less drab than the old
        /// muted brown-terracotta).
        var color: Color {
            switch self {
            case .terracotta:
                Color(
                    light: Color(red: 0.745, green: 0.314, blue: 0.282),  // #BE5048
                    dark:  Color(red: 0.918, green: 0.553, blue: 0.471)
                )
            case .pink:
                .pink
            }
        }

        /// Top-lit two-tone accent gradient (warm terracotta → rose), echoing
        /// the two interlocked rings in the app icon. Richer and more
        /// dimensional than the old single-hue terracotta ramp; backs primary
        /// buttons and avatars.
        var gradient: LinearGradient {
            let stops: [Color]
            switch self {
            case .terracotta:
                // Both stops hold 4.5:1 against the white label on top of them
                // (the old #E0845A start was 2.8:1, 2.2:1 in dark mode).
                stops = [
                    Color(red: 0.737, green: 0.337, blue: 0.176),   // #BC562D terracotta
                    Color(red: 0.620, green: 0.210, blue: 0.320)    // #9E3552 rose
                ]
            case .pink:
                stops = [Color.pink.opacity(0.85), Color.pink]
            }
            return LinearGradient(colors: stops, startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private let accentKey = "theme.accent"
    private let appearanceKey = "theme.appearance"

    var accent: Accent {
        didSet { UserDefaults.standard.set(accent.rawValue, forKey: accentKey) }
    }

    var appearance: Appearance {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: appearanceKey) }
    }

    private init() {
        accent = UserDefaults.standard.string(forKey: accentKey)
            .flatMap(Accent.init(rawValue:)) ?? .terracotta
        appearance = UserDefaults.standard.string(forKey: appearanceKey)
            .flatMap(Appearance.init(rawValue:)) ?? .system
    }
}
