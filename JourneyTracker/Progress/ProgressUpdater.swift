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

    /// Every active, non-completed journey.
    nonisolated static func activeJourneys(in context: ModelContext) -> [Journey] {
        let descriptor = FetchDescriptor<Journey>(
            predicate: #Predicate { $0.isActive && !$0.isCompleted }
        )
        return (try? context.fetch(descriptor)) ?? []
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
            // ONE delta, applied identically to EVERY active journey.
            for journey in activeJourneys(in: context) {
                journey.distanceAccumulated += delta
                if journey.distanceAccumulated >= journey.totalDistance {
                    journey.distanceAccumulated = journey.totalDistance
                    journey.isCompleted = true
                }
            }
            anchor.lastProcessedDistance = newCumulative
        }

        // Liveness: refresh on any successful numeric reading, even at delta 0.
        anchor.lastUpdated = date
        anchor.sourceDevice = sourceDevice

        try context.save()
        return delta
    }
}
