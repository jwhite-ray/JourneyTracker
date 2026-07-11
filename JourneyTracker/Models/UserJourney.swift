//
//  UserJourney.swift
//  JourneyTracker
//
//  One user's run of a JourneyTemplate (KAN-10) — replaces the shipped combined
//  `Journey` model. This is the ONLY place per-user, irreplaceable data lives:
//  `startDate` (UTC), `distanceAccumulated` (meters), and a lifecycle `status`.
//  Everything else (name, totalDistance, theme, waypoints) is content and is
//  read through the `template`.
//
//  Progress is driven by HealthKit distanceWalkingRunning via the shared delta
//  anchor (see ProgressUpdate / ProgressUpdater) — never steps. Only an
//  `.active` instance accrues distance.
//
//  CloudKit-compatible: inline default on every stored property, optional
//  relationship, no @Attribute(.unique). `status` is stored via its raw String
//  with a default, exactly like JourneyType.
//

import Foundation
import SwiftData

@Model
final class UserJourney {
    var id: UUID = UUID()

    /// Fixed reference point for this run, stored in UTC (Date is absolute).
    var startDate: Date = Date()

    /// Distance walked toward this run since `startDate`, in METERS.
    var distanceAccumulated: Double = 0

    /// Lifecycle state. Stored as JourneyStatus' raw String, with a default.
    /// Replaces the old `isActive`/`isCompleted` booleans.
    var status: JourneyStatus = JourneyStatus.active

    /// The catalog entry this run walks. Optional to stay CloudKit-compatible.
    var template: JourneyTemplate?

    init(
        id: UUID = UUID(),
        startDate: Date = Date(),
        distanceAccumulated: Double = 0,
        status: JourneyStatus = .active,
        template: JourneyTemplate? = nil
    ) {
        self.id = id
        self.startDate = startDate
        self.distanceAccumulated = distanceAccumulated
        self.status = status
        self.template = template
    }

    // MARK: - Content proxies (read through the template)

    var name: String { template?.name ?? "" }
    var totalDistance: Double { template?.totalDistance ?? 0 }
    var theme: JourneyTheme {
        template?.theme ?? JourneyTheme(
            backgroundImageName: "",
            markerImageName: "",
            accentColorToken: "accent/primary",
            pathColorToken: "ink"
        )
    }

    /// Progress fraction, capped at 1.0. Both operands are meters.
    var progress: Double {
        guard totalDistance > 0 else { return 0 }
        return min(1.0, distanceAccumulated / totalDistance)
    }

    /// Convenience mirror of `status == .completed` for read-only callers
    /// (e.g. the map's marker/waypoint state) that only care about completion.
    var isCompleted: Bool { status == .completed }
}
