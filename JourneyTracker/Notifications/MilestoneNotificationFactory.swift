//
//  MilestoneNotificationFactory.swift
//  JourneyTracker
//
//  The pure, testable rule that turns "what a journey did in this delta" into AT
//  MOST ONE milestone notification (KAN-33 Rulings 2 & 6). Factored out of
//  ProgressUpdater so the delta actor stays focused: it takes only Sendable
//  snapshots (UUIDs, ints, resolved strings, JourneyStats) plus the
//  completion flag, resolves copy through NotificationContentProvider, and hands
//  back a fully-formed MilestoneNotificationRequest — no models, no I/O, no await.
//
//  The collapse rule (Ruling 2), per journey per `apply`:
//   • completed this delta            → ONE `journeyComplete` (suppress every
//                                        waypoint banner, including the terminal
//                                        waypoint's own crossing);
//   • else ≥1 non-origin waypoint     → ONE `waypointReached` for the FURTHEST
//     crossed this delta                 (highest distanceFromStart);
//   • else                            → nothing.
//  Intermediate crossings are still recorded as data by the caller — they simply
//  don't each notify.
//
//  `nonisolated` (opting out of the project's MainActor default isolation) so it
//  runs on the ProgressStore actor's context during `apply`.
//

import Foundation

nonisolated enum MilestoneNotificationFactory {

    /// A Sendable snapshot of one crossed waypoint — the caller reads these off
    /// the live `Waypoint` models (valid on the actor's context) before crossing
    /// the enqueue boundary.
    struct CrossedWaypoint: Sendable {
        let id: UUID
        let order: Int
        let name: String
        let distanceFromStart: Double
    }

    /// Builds the single request this journey/delta should fire, or `nil` when the
    /// collapse rule fires nothing OR the journey has no sheet/content (graceful
    /// no-op). `templateID` is required — a run with no template has no copy and
    /// no deep-link target.
    static func request(
        journeyName: String,
        userJourneyID: UUID,
        templateID: UUID?,
        didCompleteThisDelta: Bool,
        crossedThisDelta: [CrossedWaypoint],
        stats: JourneyStats,
        distanceAccumulated: Double,
        totalDistance: Double
    ) -> MilestoneNotificationRequest? {
        guard let templateID else { return nil }

        // The furthest crossed waypoint drives both branches: it is the terminal
        // waypoint on a completion, and the one waypoint banner otherwise.
        let furthest = crossedThisDelta.max { $0.distanceFromStart < $1.distanceFromStart }

        func context(waypointName: String?) -> NotificationContentProvider.FillContext {
            NotificationContentProvider.FillContext(
                journeyName: journeyName,
                waypointName: waypointName,
                nextWaypointName: stats.nextWaypoint?.name,
                milesWalkedMeters: distanceAccumulated,
                milesToNextMeters: stats.nextWaypoint?.metersUntil,
                milesRemainingMeters: max(0, totalDistance - distanceAccumulated),
                totalMilesMeters: totalDistance
            )
        }

        if didCompleteThisDelta {
            guard let content = NotificationContentProvider.resolvedContent(
                journeyName: journeyName,
                hook: .journeyComplete,
                waypointOrder: nil,
                context: context(waypointName: furthest?.name)
            ) else { return nil }
            return MilestoneNotificationRequest(
                milestone: .journeyComplete,
                userJourneyID: userJourneyID,
                templateID: templateID,
                title: content.title,
                body: content.body
            )
        }

        guard let furthest else { return nil } // no non-origin crossing this delta
        guard let content = NotificationContentProvider.resolvedContent(
            journeyName: journeyName,
            hook: .waypointReached,
            waypointOrder: furthest.order,
            context: context(waypointName: furthest.name)
        ) else { return nil }
        return MilestoneNotificationRequest(
            milestone: .waypointReached(waypointID: furthest.id),
            userJourneyID: userJourneyID,
            templateID: templateID,
            title: content.title,
            body: content.body
        )
    }
}
