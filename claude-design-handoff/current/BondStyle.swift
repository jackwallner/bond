import SwiftUI

// UI-layer style constants for the iOS app. Names the values already used
// ad hoc across views so call sites stop reaching for arbitrary numbers.

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
    static let chip: CGFloat   = 8
    static let inline: CGFloat = 12
    static let card: CGFloat   = 16
    static let hero: CGFloat   = 20
}

extension Color {
    /// Primary accent. Routed through `BondTheme` so the Settings picker can
    /// flip palettes at runtime. Reading from a View body registers an
    /// `@Observable` dependency on `theme.accent`, so changes re-render any
    /// view that uses this color.
    @MainActor
    static var bondAccent: Color { BondTheme.shared.accent.color }

    static let bondSurface = Color(.systemBackground)
    static let bondSurfaceElevated = Color(.secondarySystemBackground)
    /// Inline content card fill — replaces ad-hoc `Color.gray.opacity(0.08)`.
    static let bondCardFill = Color(.tertiarySystemFill)
    /// Hairline border / divider.
    static let bondHairline = Color(.separator).opacity(0.6)
}
