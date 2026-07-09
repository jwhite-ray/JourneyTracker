//
//  Journey.swift
//  JourneyTracker
//
//  One route the user is walking. Multiple journeys can be active at once;
//  each tracks its own cumulative distance from its own startDate. Progress
//  is driven by HealthKit distanceWalkingRunning via the shared delta anchor
//  (see ProgressUpdate / ProgressUpdater) — never steps.
//
//  CloudKit-compatible: inline default on every stored property, optional
//  relationship, no @Attribute(.unique). The `type` enum is stored via its
//  raw String with a default.
//

import Foundation
import SwiftData

@Model
final class Journey {
    var id: UUID = UUID()
    var name: String = ""

    /// Stored as JourneyType's raw String under the hood, with a default.
    var type: JourneyType = JourneyType.fantasy

    /// Total route length, in METERS.
    var totalDistance: Double = 0
    /// Distance walked toward this journey since `startDate`, in METERS.
    var distanceAccumulated: Double = 0

    /// Fixed reference point for this journey, stored in UTC (Date is absolute).
    var startDate: Date = Date()

    var isActive: Bool = true
    var isCompleted: Bool = false
    var isPremium: Bool = false

    /// Optional relationship (delete waypoints with their journey).
    @Relationship(deleteRule: .cascade, inverse: \Waypoint.journey)
    var waypoints: [Waypoint]?

    init(
        id: UUID = UUID(),
        name: String = "",
        type: JourneyType = .fantasy,
        totalDistance: Double = 0,
        distanceAccumulated: Double = 0,
        startDate: Date = Date(),
        isActive: Bool = true,
        isCompleted: Bool = false,
        isPremium: Bool = false
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.totalDistance = totalDistance
        self.distanceAccumulated = distanceAccumulated
        self.startDate = startDate
        self.isActive = isActive
        self.isCompleted = isCompleted
        self.isPremium = isPremium
    }

    /// Progress fraction, capped at 1.0. Both operands are meters.
    var progress: Double {
        guard totalDistance > 0 else { return 0 }
        return min(1.0, distanceAccumulated / totalDistance)
    }
}
