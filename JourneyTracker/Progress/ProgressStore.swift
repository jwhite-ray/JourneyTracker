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

/// WARNING: every write to `UserJourney`, `JourneyTemplate`, and `ProgressUpdate`
/// must go through this actor's single context. That covers HealthKit delta
/// application AND every KAN-10 lifecycle mutation (pause / resume / restart).
/// A future feature that mutates these from another context (e.g. a
/// journey-creation UI, or flipping `status` on `mainContext`) would reintroduce
/// the cross-context staleness/double-credit race this actor exists to prevent,
/// and could let an in-flight delta and a restart interleave. Route such writes
/// through here too — and share the ONE `ProgressStore.shared` instance, since a
/// second ProgressStore would own a second context and defeat the serialization.
///
/// DOCUMENTED EXCEPTION: `SeedData` writes on the container's `mainContext` at
/// launch (catalog templates + the anchor + the one-time migration-restore of
/// instances). That is safe because it runs BEFORE HealthKit authorization and
/// the observer are started (see `HealthKitManager.start()`, which calls
/// `SeedData.seedIfNeeded` first and only then requests auth / installs the
/// observer), so no delta can be in flight while seeding runs. The restore
/// creates historical instances at their migrated distance; it never mutates a
/// live delta. All POST-launch instance/status writes must still go through
/// this actor.
@ModelActor
actor ProgressStore {

    /// The single shared store. HealthKit delta application and all lifecycle
    /// mutations funnel through this ONE instance so they serialize on one
    /// context.
    static let shared = ProgressStore(modelContainer: SharedModelContainer.shared)

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

    // MARK: - Lifecycle mutations (KAN-10)
    //
    // Every one of these takes a Sendable PersistentIdentifier (not a model —
    // models aren't Sendable across the actor boundary) and resolves it on this
    // actor's own context. They serialize with delta application, so a restart
    // can never interleave with an in-flight HealthKit delta.

    enum LifecycleError: Error {
        /// Another instance of the same template is already active, so making
        /// this one active would break the one-active-per-template invariant.
        case activeInstanceExists
        /// The identifier didn't resolve to a UserJourney on this context.
        case instanceNotFound
        /// The instance wasn't in the state this transition requires (e.g. a
        /// resume asked of an already-active instance). Guards against acting on
        /// a stale UI that raced another mutation.
        case wrongState
    }

    /// Pauses an active instance. A frozen instance never accrues. Only valid
    /// from `.active`.
    func pause(_ id: PersistentIdentifier) throws {
        guard let journey = modelContext.model(for: id) as? UserJourney else {
            throw LifecycleError.instanceNotFound
        }
        guard journey.status == .active else { throw LifecycleError.wrongState }
        journey.status = .paused
        try modelContext.save()
    }

    /// Resumes a paused instance back to active. Only valid from `.paused`, and
    /// enforces the one-active-per-template invariant first (the UI shouldn't
    /// offer this when another instance is active, but the invariant lives here
    /// regardless).
    func resume(_ id: PersistentIdentifier) throws {
        guard let journey = modelContext.model(for: id) as? UserJourney else {
            throw LifecycleError.instanceNotFound
        }
        guard journey.status == .paused else { throw LifecycleError.wrongState }
        try ensureNoActiveInstance(for: journey.template, excluding: journey)
        journey.status = .active
        try modelContext.save()
    }

    /// Restarts a COMPLETED instance: preserves it as history and creates a
    /// fresh active instance of the same template from zero. No confirmation is
    /// needed at the call site — nothing is discarded. Only valid from
    /// `.completed` (verified before excluding `old` from the one-active check,
    /// so a mislabeled active instance can't slip the invariant).
    func restartCompleted(_ id: PersistentIdentifier) throws {
        guard let old = modelContext.model(for: id) as? UserJourney else {
            throw LifecycleError.instanceNotFound
        }
        guard old.status == .completed else { throw LifecycleError.wrongState }
        let template = old.template
        try ensureNoActiveInstance(for: template, excluding: old)
        // Preserve `old` untouched; create a fresh run.
        let fresh = UserJourney(
            startDate: Date(),
            distanceAccumulated: 0,
            status: .active,
            template: template
        )
        modelContext.insert(fresh)
        try modelContext.save()
    }

    /// Restarts a PAUSED instance: DELETES it (abandoned partial runs aren't
    /// history) and creates a fresh active instance of the same template from
    /// zero. Only valid from `.paused`. The destructive confirmation is the
    /// caller's responsibility.
    func restartPaused(_ id: PersistentIdentifier) throws {
        guard let old = modelContext.model(for: id) as? UserJourney else {
            throw LifecycleError.instanceNotFound
        }
        guard old.status == .paused else { throw LifecycleError.wrongState }
        let template = old.template
        try ensureNoActiveInstance(for: template, excluding: old)
        modelContext.delete(old)
        let fresh = UserJourney(
            startDate: Date(),
            distanceAccumulated: 0,
            status: .active,
            template: template
        )
        modelContext.insert(fresh)
        try modelContext.save()
    }

    /// Throws if any OTHER instance of `template` is already `.active`. The
    /// enum-on-property filter is done in memory (SwiftData can't reliably
    /// predicate on an enum raw value).
    private func ensureNoActiveInstance(for template: JourneyTemplate?, excluding: UserJourney) throws {
        guard let template else { return }
        let all = (try? modelContext.fetch(FetchDescriptor<UserJourney>())) ?? []
        let conflict = all.contains {
            $0.persistentModelID != excluding.persistentModelID
                && $0.status == .active
                && $0.template?.persistentModelID == template.persistentModelID
        }
        if conflict { throw LifecycleError.activeInstanceExists }
    }
}
