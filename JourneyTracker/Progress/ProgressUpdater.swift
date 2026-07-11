//
//  ProgressUpdater.swift
//  JourneyTracker
//
//  Pure delta application into SwiftData. Knows nothing about HealthKit — it
//  is handed a freshly-measured cumulative distance and applies the shared
//  delta anchor to every active journey. This is the one place the "get the
//  delta right" rule from the App Concept doc lives.
//
//  nonisolated so it can run on whatever ModelContext it is given. In practice
//  every call is funneled through the single ModelContext owned by ProgressStore
//  (an actor), so two apply() calls can never interleave read-anchor→write-anchor.
//

import Foundation
import SwiftData

enum ProgressUpdater {

    /// Fetch the single shared delta anchor, if it exists.
    nonisolated static func fetchAnchor(in context: ModelContext) -> ProgressUpdate? {
        var descriptor = FetchDescriptor<ProgressUpdate>()
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    /// Every active instance. The status filter is applied IN MEMORY rather
    /// than in a #Predicate: SwiftData can't reliably predicate on an enum
    /// raw-value property, so we fetch all instances and filter. `.active` is
    /// the only status that accrues, so paused/completed are excluded here.
    nonisolated static func activeJourneys(in context: ModelContext) -> [UserJourney] {
        let all = (try? context.fetch(FetchDescriptor<UserJourney>())) ?? []
        return all.filter { $0.status == .active }
    }

    /// Apply a newly-measured cumulative distance (meters, from the anchor's
    /// start date to "now") to every active journey via the shared delta.
    ///
    /// Callers must pass a successful *numeric* reading only — never an error
    /// reading — because this always refreshes `lastUpdated`/`sourceDevice`.
    ///
    /// - Returns: the delta actually applied, in meters (>= 0). Returns 0 when
    ///   there is no anchor to work from.
    /// - Throws: rethrows any `ModelContext.save()` failure so the caller can
    ///   surface it instead of silently reporting success.
    @discardableResult
    nonisolated static func apply(
        newCumulative: Double,
        sourceDevice: SourceDevice,
        at date: Date = Date(),
        in context: ModelContext
    ) throws -> Double {
        guard let anchor = fetchAnchor(in: context) else { return 0 }

        let delta = max(0, newCumulative - anchor.lastProcessedDistance)

        // Monotonic anchor (Jake's ruling — see the delta-computation paragraph
        // in JourneyTracker_App_Concept.md): advance `lastProcessedDistance` and
        // credit journeys ONLY when the cumulative total genuinely grew. A
        // lower-or-equal reading (a transient dip, or revoked read access
        // surfacing as a silent zero with no error) yields delta 0 with the
        // anchor held — so the next real reading can never re-credit everything
        // walked since anchorStartDate. Under-crediting is bounded and
        // recoverable; a downward re-anchor's double-credit is neither.
        if newCumulative > anchor.lastProcessedDistance {
            // ONE delta, applied identically to EVERY active instance.
            for journey in activeJourneys(in: context) {
                // Capture the pre-delta accumulated so the half-open crossing
                // interval (old, new] can be evaluated after the increment/clamp.
                let old = journey.distanceAccumulated
                journey.distanceAccumulated += delta

                // Auto-complete at 100%. An instance with no template can't have
                // a total to reach, so use +infinity to skip auto-completion for
                // it (it simply keeps accruing until it gains a template). A
                // non-positive total (missing/zero content) must NOT auto-flip
                // to completed at zero distance, so require total > 0.
                let total = journey.template?.totalDistance ?? .infinity
                if total > 0 && journey.distanceAccumulated >= total {
                    journey.distanceAccumulated = total
                    journey.status = .completed
                    // Ruling 5: completedAt is the canonical finish date, set
                    // here at auto-complete (covers zero-waypoint completions
                    // that have no final-waypoint crossing to read).
                    journey.completedAt = date
                }

                // Ruling 2 & 4: record a WaypointCrossing for every waypoint in
                // the half-open interval (old, new] with distanceFromStart > 0
                // (origin waypoints are never crossings). `new` includes any
                // completion clamp above. Idempotency-guarded so the same
                // waypoint is never double-recorded across deltas.
                recordCrossings(
                    for: journey,
                    old: old,
                    new: journey.distanceAccumulated,
                    date: date,
                    in: context
                )
            }
            anchor.lastProcessedDistance = newCumulative
        }

        // Liveness: refresh on any successful numeric reading, even at delta 0.
        anchor.lastUpdated = date
        anchor.sourceDevice = sourceDevice

        try context.save()
        return delta
    }

    /// Inserts a `WaypointCrossing` for each of `journey`'s waypoints crossed in
    /// the half-open interval `(old, new]` with `distanceFromStart > 0` (Ruling 2
    /// & 4). The low end is excluded so a waypoint sitting exactly at `old` (the
    /// previous delta already recorded it) is never double-counted; the high end
    /// is included so landing exactly on a waypoint records it. An idempotency
    /// guard also skips any `waypointID` already recorded for this instance —
    /// belt-and-braces against a re-applied delta.
    ///
    /// The crossing SNAPSHOTS the waypoint's identity (Ruling 1); it holds no
    /// live Waypoint relationship. `crossedAt` is the reading's `date` — several
    /// waypoints crossed by one delta legitimately share it.
    nonisolated private static func recordCrossings(
        for journey: UserJourney,
        old: Double,
        new: Double,
        date: Date,
        in context: ModelContext
    ) {
        guard let waypoints = journey.template?.waypoints, !waypoints.isEmpty else { return }
        let alreadyRecorded = Set((journey.crossings ?? []).map { $0.waypointID })

        for waypoint in waypoints where waypoint.distanceFromStart > 0 {
            let d = waypoint.distanceFromStart
            guard old < d, d <= new else { continue }
            guard !alreadyRecorded.contains(waypoint.id) else { continue }

            let crossing = WaypointCrossing(
                crossedAt: date,
                waypointID: waypoint.id,
                order: waypoint.order,
                name: waypoint.name,
                distanceFromStart: waypoint.distanceFromStart,
                journey: journey
            )
            context.insert(crossing)
        }
    }
}
