import SwiftUI

// Plus Jakarta Sans — the app's brand typeface. The static weights live in
// `Resources/Fonts/` and are registered via `UIAppFonts` in Info.plist.
//
// Use `Font.bond(_:weight:)` in place of the system text styles (`.headline`,
// `.caption`, …). It renders in Plus Jakarta Sans while still scaling with
// Dynamic Type through `relativeTo:`, and maps SwiftUI weights onto the four
// bundled faces. SF Symbol glyphs keep using `.system(size:)` — a text face
// doesn't apply to them.

enum BondFontFamily {
    /// Maps a SwiftUI weight onto one of the four bundled faces. We only ship
    /// Regular/Medium/SemiBold/Bold, so heavier weights fold into Bold and
    /// lighter ones into Regular rather than letting the system synthesize.
    static func postScriptName(for weight: Font.Weight) -> String {
        switch weight {
        case .black, .heavy, .bold: "PlusJakartaSans-Bold"
        case .semibold:             "PlusJakartaSans-SemiBold"
        case .medium:               "PlusJakartaSans-Medium"
        default:                    "PlusJakartaSans-Regular"
        }
    }

    /// iOS default point size for each text style at the Large content size.
    /// `relativeTo:` scales from here for other Dynamic Type sizes.
    static func size(for style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle:  34
        case .title:       28
        case .title2:      22
        case .title3:      20
        case .headline:    17
        case .body:        17
        case .callout:     16
        case .subheadline: 15
        case .footnote:    13
        case .caption:     12
        case .caption2:    11
        @unknown default:  17
        }
    }

    /// System default weight per text style — headline is semibold, the rest
    /// regular — so an un-weighted `.bond(.headline)` matches the platform.
    static func defaultWeight(for style: Font.TextStyle) -> Font.Weight {
        style == .headline ? .semibold : .regular
    }
}

extension Font {
    /// Brand font for a semantic text style, scaling with Dynamic Type.
    /// Pass `weight:` to override the style's default (e.g. a bold title).
    static func bond(_ style: Font.TextStyle, weight: Font.Weight? = nil) -> Font {
        let resolved = weight ?? BondFontFamily.defaultWeight(for: style)
        return .custom(
            BondFontFamily.postScriptName(for: resolved),
            size: BondFontFamily.size(for: style),
            relativeTo: style
        )
    }
}
