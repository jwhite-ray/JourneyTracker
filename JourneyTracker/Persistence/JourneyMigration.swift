//
//  JourneyMigration.swift
//  JourneyTracker
//
//  The V1 -> V2 SwiftData migration for KAN-10: the shipped single combined
//  `Journey` model (with isActive/isCompleted/isPremium booleans and its own
//  waypoints) is split into a catalog `JourneyTemplate` and an instance
//  `UserJourney` (with a `JourneyStatus` enum), and `Waypoint` moves from
//  `journey` to `template`.
//
//  Strategy (a CUSTOM stage — the change is not lightweight):
//   1. willMigrate reads every legacy Journey and STASHES a small snapshot of
//      the irreplaceable per-user fields (name, startDate, distanceAccumulated,
//      isActive, isCompleted) into the app-group UserDefaults, which survives
//      the schema boundary intact.
//   2. It then DELETES all legacy Journey + Waypoint rows so the structural
//      transform to V2 (drop `Journey`, add `JourneyTemplate`/`UserJourney`,
//      re-point `Waypoint`) runs against empty tables. Waypoints are pure seed
//      content and are re-created fresh from SeedData, so nothing is lost.
//   3. The shared delta anchor (ProgressUpdate) is UNCHANGED across the
//      boundary and is deliberately left untouched — progress keeps accruing
//      from the same monotonic anchor.
//   4. After launch, once SeedData has ensured the templates exist, the stash
//      is drained: each snapshot becomes a fresh UserJourney matched to its
//      template by name, with distanceAccumulated + startDate verbatim and
//      status mapped isCompleted -> .completed / isActive -> .active / else
//      .paused. Draining clears the stash, so it runs exactly once.
//

import Foundation
import SwiftData

// MARK: - Snapshot stash (survives the schema boundary)

/// One legacy Journey's irreplaceable fields, carried across the migration.
struct LegacyJourneySnapshot: Codable {
    let name: String
    let startDate: Date
    let distanceAccumulated: Double
    let isActive: Bool
    let isCompleted: Bool

    /// The KAN-10 status this legacy journey maps to. Completed wins over
    /// active, active over paused.
    var mappedStatus: JourneyStatus {
        if isCompleted { return .completed }
        if isActive { return .active }
        return .paused
    }
}

/// Persists the pre-migration journey snapshots across the V1 -> V2 boundary in
/// the app-group UserDefaults (falls back to `.standard` if the group is
/// unavailable, mirroring SharedModelContainer's store fallback).
enum MigrationStash {
    private static let key = "kan10.legacyJourneySnapshots"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: SharedModelContainer.appGroupID) ?? .standard
    }

    static func save(_ snapshots: [LegacyJourneySnapshot]) {
        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        defaults.set(data, forKey: key)
    }

    /// Returns the stashed snapshots, or nil when there is nothing to restore
    /// (fresh install, or already drained).
    static func load() -> [LegacyJourneySnapshot]? {
        guard let data = defaults.data(forKey: key),
              let snapshots = try? JSONDecoder().decode([LegacyJourneySnapshot].self, from: data)
        else { return nil }
        return snapshots
    }

    static func clear() {
        defaults.removeObject(forKey: key)
    }
}

// MARK: - Versioned schemas

/// The shipped (KAN-6/7/9) shape: one combined `Journey`, `Waypoint` keyed by
/// `journey`, and the shared `ProgressUpdate` anchor. Defined here as legacy
/// types used ONLY by the migration; the live app uses SchemaV2's types.
enum JourneySchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Journey.self, Waypoint.self, ProgressUpdate.self]
    }

    @Model
    final class Journey {
        var id: UUID = UUID()
        var name: String = ""
        var type: JourneyType = JourneyType.fantasy
        var totalDistance: Double = 0
        var distanceAccumulated: Double = 0
        var startDate: Date = Date()
        var isActive: Bool = true
        var isCompleted: Bool = false
        var isPremium: Bool = false
        var backgroundImageName: String = ""
        var markerImageName: String = ""
        var accentColorToken: String = "accent/primary"
        var pathColorToken: String = "ink"

        @Relationship(deleteRule: .cascade, inverse: \Waypoint.journey)
        var waypoints: [Waypoint]?

        init() {}
    }

    @Model
    final class Waypoint {
        var id: UUID = UUID()
        var order: Int = 0
        var positionX: Double = 0
        var positionY: Double = 0
        var distanceFromStart: Double = 0
        var name: String = ""
        var descriptionText: String = ""
        var journey: Journey?

        init() {}
    }
}

/// The KAN-10 shape: catalog `JourneyTemplate` + instance `UserJourney`,
/// `Waypoint` keyed by `template`, and the unchanged `ProgressUpdate` anchor.
/// These are the live top-level model types the app uses everywhere.
enum JourneySchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [JourneyTemplate.self, UserJourney.self, Waypoint.self, ProgressUpdate.self]
    }
}

// MARK: - Migration plan

enum JourneyMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [JourneySchemaV1.self, JourneySchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2]
    }

    static let migrateV1toV2 = MigrationStage.custom(
        fromVersion: JourneySchemaV1.self,
        toVersion: JourneySchemaV2.self,
        willMigrate: { context in
            // Snapshot every legacy journey's irreplaceable fields, then delete
            // journeys + waypoints so the structural transform runs on empty
            // tables. The anchor (ProgressUpdate) is intentionally left alone.
            //
            // Kill-safety: SwiftData may commit willMigrate's deletions to the
            // V1 store even if the later structural upgrade never commits — so
            // a crash mid-migration can leave a V1 store whose rows are already
            // gone but whose stash is the ONLY surviving copy of user progress.
            // On the next launch willMigrate re-runs against that empty store.
            // Two rules keep that safe:
            //   1. If the legacy fetch throws we ABORT (no stash write, no
            //      deletes) and leave the store untouched for a later retry.
            //   2. We NEVER clobber a non-empty stash with an empty snapshot
            //      set — an empty read on a re-run means "already drained the
            //      rows last time," not "there was never any progress."
            let legacy: [JourneySchemaV1.Journey]
            do {
                legacy = try context.fetch(FetchDescriptor<JourneySchemaV1.Journey>())
            } catch {
                print("[Migration] willMigrate: legacy fetch failed — aborting to leave the V1 store intact: \(error)")
                return
            }

            let snapshots = legacy.map {
                LegacyJourneySnapshot(
                    name: $0.name,
                    startDate: $0.startDate,
                    distanceAccumulated: $0.distanceAccumulated,
                    isActive: $0.isActive,
                    isCompleted: $0.isCompleted
                )
            }

            if !snapshots.isEmpty {
                MigrationStash.save(snapshots)
            } else if MigrationStash.load() != nil {
                // A prior (killed) pass already stashed and deleted the rows;
                // this empty re-read must not overwrite that good stash.
                print("[Migration] willMigrate: empty V1 store but a stash already exists — preserving it.")
            }

            for journey in legacy {
                context.delete(journey) // cascades to its waypoints
            }
            // Belt-and-braces: remove any orphan waypoints not caught by cascade.
            if let orphans = try? context.fetch(FetchDescriptor<JourneySchemaV1.Waypoint>()) {
                for waypoint in orphans {
                    context.delete(waypoint)
                }
            }
            do {
                try context.save()
            } catch {
                // The stash is already durable; a failed delete-save only means
                // the structural transform will run against non-empty tables.
                // Surface it loudly rather than swallowing it.
                print("[Migration] willMigrate: delete-save FAILED: \(error)")
            }
        },
        didMigrate: nil
    )
}
