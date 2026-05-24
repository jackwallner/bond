import SwiftUI

// UI-layer style constants for the iOS app. Names the values already used
// ad hoc across views so call sites stop reaching for arbitrary numbers.
//
// Visual system: "Soft Tactile" (Direction A). Warm cream surfaces, generous
// radii, warm-tinted shadows, and gradient accents so the in-app feel matches
// the soft 3D app-icon language. Type is SF Rounded, applied globally from
// `RootView` via `.fontDesign(.rounded)` (system stand-in for Plus Jakarta
// Sans — swap in the real face by bundling it + `UIAppFonts` if desired).

enum BondSpacing {
    static let xs: CGFloat   = 4
    static let s: CGFloat    = 8
    static let m: CGFloat    = 12
    static let base: CGFloat = 16
    static let l: CGFloat    = 20
    static let xl: CGFloat   = 24
    static let xxl: CGFloat  = 32
    static let xxxl: CGFloat = 48
}

enum BondRadius {
    // Bumped for Soft Tactile: cards read as pillowy physical objects (24–28pt).
    static let chip: CGFloat   = 10
    static let inline: CGFloat = 16
    static let card: CGFloat   = 24
    static let hero: CGFloat   = 28
}

extension Color {
    /// Primary accent. Routed through `BondTheme` so the Settings picker can
    /// flip palettes at runtime. Reading from a View body registers an
    /// `@Observable` dependency on `theme.accent`, so changes re-render any
    /// view that uses this color.
    @MainActor
    static var bondAccent: Color { BondTheme.shared.accent.color }

    /// Two-tone gradient form of the accent — top-lit, like the icon's tubes.
    /// Use as the fill for primary buttons / avatars to echo the 3D quality.
    @MainActor
    static var bondAccentGradient: LinearGradient { BondTheme.shared.accent.gradient }

    // Soft Tactile surface palette. Warm cream base, brighter warm-white cards.
    /// Screen base — cream `#FBE9D2`, lit by sunset rather than flash.
    static let bondSurface = Color(
        light: Color(red: 0.984, green: 0.914, blue: 0.824),
        dark:  Color(red: 0.102, green: 0.082, blue: 0.071)
    )
    /// Raised panels / sheets — warm white `#FFF6E9`.
    static let bondSurfaceElevated = Color(
        light: Color(red: 1.000, green: 0.965, blue: 0.914),
        dark:  Color(red: 0.165, green: 0.137, blue: 0.122)
    )
    /// Inline content card fill — the brightest warm white so cards lift off
    /// the cream base. Replaces ad-hoc `Color.gray.opacity(0.08)`.
    static let bondCardFill = Color(
        light: Color(red: 1.000, green: 0.984, blue: 0.957),
        dark:  Color(red: 0.196, green: 0.165, blue: 0.149)
    )
    /// Hairline border / divider — warm brown, not gray.
    static let bondHairline = Color(
        light: Color(red: 0.71, green: 0.45, blue: 0.30).opacity(0.18),
        dark:  Color(red: 1.00, green: 0.85, blue: 0.70).opacity(0.14)
    )
    /// Warm drop-shadow tint for soft-tactile cards/buttons (sunset brown,
    /// never neutral gray). Opacity baked in for direct use in `.shadow`.
    static let bondShadow = Color(
        light: Color(red: 0.45, green: 0.22, blue: 0.10).opacity(0.18),
        dark:  Color(red: 0.00, green: 0.00, blue: 0.00).opacity(0.45)
    )

    /// Full-screen warm wash (cream → peach) sitting behind app content.
    static var bondBackgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(light: Color(red: 0.984, green: 0.914, blue: 0.824),
                      dark:  Color(red: 0.102, green: 0.082, blue: 0.071)),
                Color(light: Color(red: 0.925, green: 0.729, blue: 0.561),
                      dark:  Color(red: 0.149, green: 0.110, blue: 0.090))
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

extension View {
    /// Soft-tactile elevation: warm halo shadow + hairline so a surface reads
    /// as a physical object you could pick up. Apply to cards/sheets that
    /// already carry a `bondCardFill` background.
    func bondSoftElevation(radius: CGFloat = BondRadius.card) -> some View {
        self
            .shadow(color: .bondShadow, radius: 14, x: 0, y: 8)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.bondHairline, lineWidth: 0.5)
            )
    }
}
