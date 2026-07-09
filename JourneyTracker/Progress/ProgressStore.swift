//
//  ProgressStore.swift
//  JourneyTracker
//
//  The single serialized write path for journey progress. All delta
//  application — foreground refresh AND the background HealthKit observer —
//  is funneled through this actor, which owns exactly one ModelContext.
//
//  This closes the cross-context double-credit race: with two contexts
//  (main + a fresh background context) nothing serialized the
//  read-anchor→write-anchor sequence, so an observer that read the anchor at
//  900 and then awaited its query could apply +100 on top of a +100 the
//  foreground path had already committed, crediting +200 for 100 m walked.
//  An actor guarantees those two apply() calls can never interleave.
//
//  Implemented as @ModelActor so its ModelContext is created lazily ON the
//  actor's own executor and only ever touched there — avoiding the
//  "ModelContext instantiated on the main queue but used off it" unbinding
//  warning that a manually-constructed context produced.
//

import Foundation
import SwiftData

/// WARNING: every write to `Journey` and `ProgressUpdate` models must go through
/// this actor's context. A future feature that mutates them from another
/// context (e.g. a journey-creation UI, or toggling `isActive` on `mainContext`)
/// would reintroduce the cross-context staleness/double-credit bug this actor
/// exists to prevent. Route such writes through here too.
@ModelActor
actor ProgressStore {

    /// The shared anchor's fixed start date, or nil if not yet seeded. Used by
    /// the caller to size the cumulative-sum query window.
    func anchorStartDate() -> Date? {
        ProgressUpdater.fetchAnchor(in: modelContext)?.anchorStartDate
    }

    /// Apply a freshly-measured cumulative distance. Serialized by actor
    /// isolation; rethrows save failures to the caller.
    @discardableResult
    func apply(newCumulative: Double, sourceDevice: SourceDevice, at date: Date) throws -> Double {
        try ProgressUpdater.apply(
            newCumulative: newCumulative,
            sourceDevice: sourceDevice,
            at: date,
            in: modelContext
        )
    }
}
