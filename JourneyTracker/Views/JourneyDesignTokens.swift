//
//  JourneyDesignTokens.swift
//  JourneyTracker
//
//  Thin, non-negotiable indirection so views never spell a hex value or a
//  literal `Color.red`. Every color a journey view draws resolves through a
//  design-token NAME here or through `journey.theme`'s token fields. The names
//  match the Asset Catalog colorsets (namespaced folders in Assets.xcassets),
//  which is the single source of the actual hues (light + Deepdark).
//

import SwiftUI

/// Stable design-token identifiers. Their hues live in the Asset Catalog, not
/// here — this enum only names them so a typo is a compile error, not a blank
/// color at runtime.
enum DesignToken {
    static let parchment = "bg/parchment"
    static let ink = "ink"
    static let card = "surface/card"
    static let accentPrimary = "accent/primary"
    static let accentSecondary = "accent/secondary"
    static let reward = "accent/reward"
    static let alert = "accent/alert"
    static let charCloak = "char/cloak"
    static let charSkin = "char/skin"
}

extension Color {
    /// Resolves a design-token name (or a `journey.theme` token) to its
    /// Asset Catalog colorset. Centralizes the one place a token string becomes
    /// a `Color`, so no view constructs `Color(_:)` from a raw string itself.
    init(token: String) {
        self.init(token, bundle: .main)
    }

    /// The Design System §04 facet recipe, expressed as LIGHTNESS deltas of the
    /// base color rather than translucent white/black scrims — so a re-themed
    /// base carries through both facets instead of being washed toward
    /// monochrome. The derivation lives here (the token indirection layer) so no
    /// view spells a facet color inline.
    ///
    /// §04: highlight = base +10% L (clipped top-left), shadow = base −12% L
    /// (clipped bottom-right). We resolve the base to HSB and shift brightness,
    /// clamped to [0, 1]; no literal hex is introduced.
    static func facetHighlight(of base: Color) -> Color { base.adjustingBrightness(by: 0.10) }
    static func facetShadow(of base: Color) -> Color { base.adjustingBrightness(by: -0.12) }

    /// Returns a copy with brightness shifted by `delta` on the 0...1 HSB scale
    /// (standing in for the recipe's percentage-of-lightness), preserving hue,
    /// saturation, and alpha. Resolved against the current trait environment so
    /// it tracks light / Deepdark.
    private func adjustingBrightness(by delta: CGFloat) -> Color {
        #if canImport(UIKit)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        let ui = UIColor(self)
        guard ui.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return self
        }
        let shifted = min(max(brightness + delta, 0), 1)
        return Color(hue: hue, saturation: saturation, brightness: shifted, opacity: alpha)
        #else
        return self
        #endif
    }
}
