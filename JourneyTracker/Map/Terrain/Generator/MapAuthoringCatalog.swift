//
//  MapAuthoringCatalog.swift
//  JourneyTracker
//
//  The lookup from a JourneyTemplate to its faceted MapAuthoring (KAN-21). This is
//  the BUNDLED-CONTENT SEAM: today it is a tiny in-code map keyed by template NAME,
//  with the one authored pilot ("Road to The Windrise Peaks" → WindrisePeaksMap).
//  When journeys start shipping as JSON (App Concept doc: "Map authoring data …
//  travels as part of the bundled journey definition (JSON)"), this is the single
//  place that swaps to loading a bundled MapAuthoring by the template's stable id —
//  callers keep asking `authoring(for:)` and never change.
//
//  A journey WITHOUT an entry here has no faceted map and renders the KAN-7
//  pin-and-route fallback (Around the World). The
//  lookup returns the same frozen `MapAuthoring` value on every call —
//  the map is a pure function of (regions, seed), identical for every user.
//

import Foundation

enum MapAuthoringCatalog {

    /// Keyed by template name for now (the seam). `WindrisePeaksMap.make()` is
    /// evaluated once and cached in this static, so repeated lookups are free and
    /// the frozen authoring input is shared by every screen that renders it.
    private static let authoringByTemplateName: [String: MapAuthoring] = [
        "Road to The Windrise Peaks": WindrisePeaksMap.make(),
        "First Journey": FirstJourneyMap.make()
    ]

    /// The faceted authoring for a template, or `nil` when the journey has none
    /// (→ the pin-and-route fallback surface).
    static func authoring(for template: JourneyTemplate?) -> MapAuthoring? {
        guard let name = template?.name else { return nil }
        return authoringByTemplateName[name]
    }

    /// Whether a template has a faceted map (drives the journey view's branch).
    static func hasAuthoring(_ template: JourneyTemplate?) -> Bool {
        authoring(for: template) != nil
    }
}
