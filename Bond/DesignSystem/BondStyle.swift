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
    /// Primary accent. Use instead of raw `Color.pink` so there is one knob.
    static let bondAccent = Color.pink

    static let bondSurface = Color(.systemBackground)
    static let bondSurfaceElevated = Color(.secondarySystemBackground)
    /// Inline content card fill — replaces ad-hoc `Color.gray.opacity(0.08)`.
    static let bondCardFill = Color(.tertiarySystemFill)
    /// Hairline border / divider.
    static let bondHairline = Color(.separator).opacity(0.6)
}
