//
//  JourneyTheme.swift
//  JourneyTracker
//
//  A lightweight, per-journey visual theme. NOT a SwiftData @Model — it is a
//  plain value type assembled on demand from Journey's flat, CloudKit-safe
//  String fields (see the App Concept doc, "Theme vs. design tokens").
//
//  Colors are carried as design-token NAMES ("accent/primary", "ink"), never
//  literal Color values — a Color is not CloudKit-persistable and hardcoding
//  one would violate the design-token rule. Views resolve the names:
//      Image(journey.theme.backgroundImageName)
//      Color(journey.theme.accentColorToken)
//

import Foundation

struct JourneyTheme {
    /// Asset name for the journey's map background, e.g. "ember_spire_bg".
    let backgroundImageName: String
    /// Asset name for the journey's character/marker, e.g. "marker_wren".
    let markerImageName: String
    /// Design-token NAME for the journey's accent, e.g. "accent/primary".
    let accentColorToken: String
    /// Design-token NAME for the route/path stroke, e.g. "ink".
    let pathColorToken: String
}
