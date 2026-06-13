import SwiftUI

// UI-layer style constants for the iOS app. Names the values already used
// ad hoc across views so call sites stop reaching for arbitrary numbers.
//
// Visual system: "Soft Tactile" (Direction A). Warm cream surfaces, generous
// radii, warm-tinted shadows, and gradient accents so the in-app feel matches
// the soft 3D app-icon language. Type is SF Rounded, applied globally from
// `RootView` via `.fontDesign(.rounded)` (system stand-in for Plus Jakarta
// Sans - swap in the real face by bundling it + `UIAppFonts` if desired).

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

    /// Two-tone gradient form of the accent - top-lit, like the icon's tubes.
    /// Use as the fill for primary buttons / avatars to echo the 3D quality.
    @MainActor
    static var bondAccentGradient: LinearGradient { BondTheme.shared.accent.gradient }

    /// Secondary accent - dusty plum. A cool foil to the warm terracotta so
    /// the palette reads dimensional instead of monochrome. Use sparingly for
    /// secondary emphasis, alternate tints, and accents that shouldn't compete
    /// with the primary action color.
    static let bondSecondary = Color(
        light: Color(red: 0.549, green: 0.353, blue: 0.451),  // #8C5A73
        dark:  Color(red: 0.780, green: 0.604, blue: 0.690)
    )
    /// Tertiary warm accent - soft gold. For highlights, streaks, and small
    /// celebratory moments where terracotta would feel heavy.
    static let bondGold = Color(
        light: Color(red: 0.784, green: 0.580, blue: 0.235),  // #C8943C
        dark:  Color(red: 0.902, green: 0.753, blue: 0.455)
    )

    // Warm surface palette. Deeper cream base + brighter warm-white cards, so
    // raised surfaces lift off the background with more contrast than before.
    /// Screen base - warm cream `#F8E2C6`, lit by sunset rather than flash.
    static let bondSurface = Color(
        light: Color(red: 0.973, green: 0.886, blue: 0.776),
        dark:  Color(red: 0.106, green: 0.082, blue: 0.075)
    )
    /// Raised panels / sheets - warm white `#FFF1DE`.
    static let bondSurfaceElevated = Color(
        light: Color(red: 1.000, green: 0.945, blue: 0.871),
        dark:  Color(red: 0.176, green: 0.141, blue: 0.129)
    )
    /// Inline content card fill - the brightest warm white so cards lift off
    /// the cream base. Replaces ad-hoc `Color.gray.opacity(0.08)`.
    static let bondCardFill = Color(
        light: Color(red: 1.000, green: 0.976, blue: 0.945),
        dark:  Color(red: 0.208, green: 0.173, blue: 0.157)
    )
    /// Hairline border / divider - warm brown, not gray.
    static let bondHairline = Color(
        light: Color(red: 0.71, green: 0.45, blue: 0.30).opacity(0.18),
        dark:  Color(red: 1.00, green: 0.85, blue: 0.70).opacity(0.14)
    )
    /// Warm drop-shadow tint for soft-tactile cards/buttons (sunset brown,
    /// never neutral gray). Opacity baked in for direct use in `.shadow`.
    static let bondShadow = Color(
        light: Color(red: 0.45, green: 0.22, blue: 0.10).opacity(0.12),
        dark:  Color(red: 0.00, green: 0.00, blue: 0.00).opacity(0.45)
    )

    /// Muted warm text for section headers and quiet labels. System
    /// `.secondary` is a cool gray that reads dirty against the cream wash
    /// in light mode; this keeps the same hierarchy in a warm brown.
    static let bondMuted = Color(
        light: Color(red: 0.478, green: 0.357, blue: 0.282),  // #7A5B48
        dark:  Color(red: 0.788, green: 0.702, blue: 0.643)
    )

    /// Full-screen warm wash (cream → peach) sitting behind app content.
    /// The light bottom stop stays close to the base cream: a deeper peach
    /// down there fights the warm-white list rows and washes out accent
    /// buttons that sit near the bottom of the screen.
    static var bondBackgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(light: Color(red: 0.973, green: 0.886, blue: 0.776),
                      dark:  Color(red: 0.106, green: 0.082, blue: 0.075)),
                Color(light: Color(red: 0.949, green: 0.812, blue: 0.682),
                      dark:  Color(red: 0.157, green: 0.114, blue: 0.094))
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

    /// Warm surface treatment for `List`/`Form` screens. System grouped lists
    /// paint an opaque gray `systemGroupedBackground` over the whole screen,
    /// which hides the app's cream→peach wash and makes those tabs look like
    /// a different app than the ScrollView-based ones. Hiding the scroll
    /// background and re-applying the wash (sheets don't inherit RootView's
    /// background) keeps every screen on the same warm surface.
    func bondWarmList() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Color.bondBackgroundGradient.ignoresSafeArea())
    }

    /// Row background for grouped rows on the warm wash: the brightest warm
    /// white instead of the system's cold `secondarySystemGroupedBackground`.
    func bondWarmRow() -> some View {
        listRowBackground(Color.bondCardFill)
    }
}

/// Consistent grouped-section header: small, bold, warm-secondary - one voice
/// for every section label so headers organize rather than compete.
struct BondSectionHeader: View {
    let title: String
    var tint: Color = .bondMuted

    var body: some View {
        Text(title)
            .font(.bond(.footnote, weight: .semibold))
            .foregroundStyle(tint)
            .textCase(nil)
    }
}
