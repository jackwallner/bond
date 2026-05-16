import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// Cross-platform light/dark color pair. Compiled into every target
// (iOS app, widgets, watch), so it must not depend on UIKit-only API
// beyond what watchOS also provides (UIColor + UITraitCollection exist
// on watchOS).
extension Color {
    init(light: Color, dark: Color) {
        #if canImport(UIKit)
        self.init(UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
        #else
        self = light
        #endif
    }

    /// Deep terracotta — warm but clearly distinct from `.pink` in low light.
    /// Light ≈ #B5573F, Dark ≈ #D87156.
    static let bondTouchTerracotta = Color(
        light: Color(red: 0.71, green: 0.34, blue: 0.25),
        dark:  Color(red: 0.85, green: 0.44, blue: 0.34)
    )
}
