//
//  WaypointCrossing.swift
//  JourneyTracker
//
//  The app's FIRST record of when a run crossed a waypoint (KAN-14). Nothing
//  persisted a crossing time before: the map derives waypoint *state* live from
//  `distanceAccumulated`, but had no history of *when* each was reached.
//
//  A crossing is its own @Model (not a serialized blob on UserJourney), matching
//  the app's relational fetch-and-insert-on-the-actor grain (App Concept doc,
//  KAN-14 Ruling 1). It is written ONLY by `ProgressUpdater` inside the
//  `ProgressStore` actor, at delta-application time.
//
//  It SNAPSHOTS the crossed waypoint's identity (waypointID / order / name /
//  distanceFromStart) rather than holding a live `Waypoint` relationship —
//  waypoints are re-seeded content that can be recreated/cascaded, so a snapshot
//  keeps the historical row self-standing and immune to content churn.
//
//  CloudKit-compatible: inline default on every stored property, optional owning
//  relationship, no @Attribute(.unique). Never records a 0-mile (origin)
//  waypoint (Ruling 4). Forward-only — no historical backfill (Ruling 3).
//

import Foundation
import SwiftData

@Model
final class WaypointCrossing {
    var id: UUID = UUID()

    /// The reading date at which the crossing was OBSERVED (UTC). This is the
    /// delta's `date`, not a fabricated "reached at ship time" marker — several
    /// waypoints crossed by one delta legitimately share the same `crossedAt`.
    var crossedAt: Date = Date()

    // MARK: - Snapshot of the crossed waypoint's identity (not a live relationship)

    var waypointID: UUID = UUID()
    var order: Int = 0
    var name: String = ""
    /// Cumulative distance from the journey's start, in METERS.
    var distanceFromStart: Double = 0

    /// The run this crossing belongs to. Optional to stay CloudKit-compatible;
    /// the owning `UserJourney.crossings` relationship cascades a delete here, so
    /// a KAN-13 wipe or a paused-restart removes an instance's crossings.
    var journey: UserJourney?

    init(
        id: UUID = UUID(),
        crossedAt: Date = Date(),
        waypointID: UUID = UUID(),
        order: Int = 0,
        name: String = "",
        distanceFromStart: Double = 0,
        journey: UserJourney? = nil
    ) {
        self.id = id
        self.crossedAt = crossedAt
        self.waypointID = waypointID
        self.order = order
        self.name = name
        self.distanceFromStart = distanceFromStart
        self.journey = journey
    }
}
