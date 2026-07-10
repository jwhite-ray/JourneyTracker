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
    static let reward = "accent/reward"
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
}
