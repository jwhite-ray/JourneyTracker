//
//  Waypoint.swift
//  JourneyTracker
//
//  A named point along a journey. Positions and distances are DATA, seeded
//  from the App Concept doc's waypoint table — never Swift literals in views.
//
//  CloudKit-compatible: every stored property has an inline default, the
//  relationship back to Journey is optional, and there are no unique
//  constraints.
//

import Foundation
import SwiftData

@Model
final class Waypoint {
    var id: UUID = UUID()
    var order: Int = 0

    /// Image-relative position (0...1) for fantasy maps, or lat/long later.
    var positionX: Double = 0
    var positionY: Double = 0

    /// Cumulative distance from the journey's start, in METERS.
    var distanceFromStart: Double = 0

    var name: String = ""
    /// Kept for future milestone notifications; unused today.
    var descriptionText: String = ""

    /// Optional inverse relationship — optional to stay CloudKit-compatible.
    var journey: Journey?

    init(
        id: UUID = UUID(),
        order: Int = 0,
        positionX: Double = 0,
        positionY: Double = 0,
        distanceFromStart: Double = 0,
        name: String = "",
        descriptionText: String = ""
    ) {
        self.id = id
        self.order = order
        self.positionX = positionX
        self.positionY = positionY
        self.distanceFromStart = distanceFromStart
        self.name = name
        self.descriptionText = descriptionText
    }
}
