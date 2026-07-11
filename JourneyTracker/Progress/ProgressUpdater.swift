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
