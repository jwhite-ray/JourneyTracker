//
//  JourneyTemplate.swift
//  JourneyTracker
//
//  The catalog entry (KAN-10). Immutable seeded content — the route a user can
//  choose to walk. Carries NO progress and NO lifecycle: `name`, `type`,
//  `totalDistance` (meters), the four flat theme fields, `isPremium`,
//  `isFeatured`, and the owned `waypoints`. One template is shared by every
//  UserJourney instance that runs it.
//
//  Templates are re-derivable seed content (see SeedData + the App Concept
//  doc's tables); they are always ensured idempotently by name.
//
//  CloudKit-compatible: inline default on every stored property, optional
//  relationships, no @Attribute(.unique). Enums stored via their raw String.
//

import Foundation
import SwiftData

@Model
final class JourneyTemplate {
    var id: UUID = UUID()
    var name: String = ""

    /// Stored as JourneyType's raw String under the hood, with a default.
    var type: JourneyType = JourneyType.fantasy

    /// Total route length, in METERS.
    var totalDistance: Double = 0

    /// Catalog attributes. `isFeatured` is a dormant field (cheap to add now,
    /// drives a "featured" shelf later); `isPremium` gates purchase (KAN-11).
    var isPremium: Bool = false
    var isFeatured: Bool = false

    // MARK: - Theme (flat, CloudKit-safe fields)
    //
    // Same shape the shipped Journey carried (see "Theme vs. design tokens").
    // Colors are stored as design-token NAMES, never literal color values.

    /// Asset name for the map background. Empty = view degrades to a plain surface.
    var backgroundImageName: String = ""
    /// Asset name for the character/marker.
    var markerImageName: String = ""
    /// Design-token NAME for this template's accent.
    var accentColorToken: String = "accent/primary"
    /// Design-token NAME for the route/path stroke.
    var pathColorToken: String = "ink"

    /// Owned content: delete the waypoints with their template.
    @Relationship(deleteRule: .cascade, inverse: \Waypoint.template)
    var waypoints: [Waypoint]?

    /// Optional inverse to the user's runs of this template. Optional to stay
    /// CloudKit-compatible; instances outlive nothing here (deleting a template
    /// is not a user flow).
    @Relationship(inverse: \UserJourney.template)
    var instances: [UserJourney]?

    init(
        id: UUID = UUID(),
        name: String = "",
        type: JourneyType = .fantasy,
        totalDistance: Double = 0,
        isPremium: Bool = false,
        isFeatured: Bool = false,
        backgroundImageName: String = "",
        markerImageName: String = "",
        accentColorToken: String = "accent/primary",
        pathColorToken: String = "ink"
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.totalDistance = totalDistance
        self.isPremium = isPremium
        self.isFeatured = isFeatured
        self.backgroundImageName = backgroundImageName
        self.markerImageName = markerImageName
        self.accentColorToken = accentColorToken
        self.pathColorToken = pathColorToken
    }

    /// Assembles the flat theme fields into a lightweight value type for views.
    var theme: JourneyTheme {
        JourneyTheme(
            backgroundImageName: backgroundImageName,
            markerImageName: markerImageName,
            accentColorToken: accentColorToken,
            pathColorToken: pathColorToken
        )
    }
}
