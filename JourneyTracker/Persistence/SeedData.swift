//
//  SeedData.swift
//  JourneyTracker
//
//  First-run + every-launch seeding (KAN-10 shape).
//
//  Templates are CATALOG CONTENT: always ensured idempotently by name, with
//  their waypoints, positions, and theme tokens — the same canonical tables
//  from the App Concept doc, living here in the DATA layer, never as literals
//  in view code.
//
//  Instances (UserJourney) are the user's runs and are NEVER auto-created — a
//  fresh install has a fully-seeded catalog and an EMPTY "Your Journeys".
//  Creating instances is a user action (KAN-11). The one exception is the
//  migration restore: a store upgraded from the shipped combined-Journey shape
//  recreates its instances from the migration stash (see JourneyMigration.swift)
//  once, right after the templates it references are ensured.
//
//  The shared delta anchor is still seeded here (unchanged from KAN-6).
//

import Foundation
import SwiftData

enum SeedData {

    /// 1 statute mile in meters — sourced from the single formatting authority,
    /// never re-hardcoded here.
    private static let metersPerMile = DistanceFormatter.metersPerMile

    private static let firstJourneyName = "First Journey"
    private static let aroundTheWorldName = "Around the World"
    private static let windrisePeaksName = "Road to The Windrise Peaks"

    /// Journeys retired from the catalog (KAN-45) but preserved for a future
    /// return — their full seed tables and notification sheets live in
    /// `docs/archive/`. Seeding DELETES any template still carrying one of
    /// these names (instances explicitly, since `JourneyTemplate.instances`
    /// has no cascade rule; waypoints cascade with the template), so an
    /// upgraded install drops them the same as a fresh one.
    private static let retiredTemplateNames: Set<String> = [
        "The Road to Ember Spire",
        "The Lantern Road",
    ]

    /// A canonical template definition, seeded idempotently by name.
    private struct TemplateSeed {
        let name: String
        let type: JourneyType
        let totalMiles: Double
        let backgroundImageName: String
        let markerImageName: String
        let accentColorToken: String
        let pathColorToken: String
        /// (name, cumulative miles, normalized map x, normalized map y).
        let waypoints: [(name: String, miles: Double, x: Double, y: Double)]
    }

    /// The full catalog. Positions are image-relative (0...1). "Around the
    /// World" is intentionally themeless (empty image names, default accent/
    /// path) and has no mapped route.
    private static let catalog: [TemplateSeed] = [
        // KAN-40: First Journey now carries a faceted authored map (FirstJourneyMap),
        // so its catalog waypoints match that map's control points. Positions are the
        // FirstJourneyMap source pixels (1000×680) normalized to the map bounds —
        // x/1000, y/680. Miles are the validator-confirmed anchor mileages. Names are
        // originals (no real-world IP). Its faceted authoring lives in FirstJourneyMap.
        TemplateSeed(
            name: firstJourneyName,
            type: .fantasy,
            totalMiles: 10,
            backgroundImageName: "first_journey_bg",
            markerImageName: "marker_wren",
            accentColorToken: "accent/secondary",
            pathColorToken: "ink",
            waypoints: [
                ("Fernhollow",      0,    300.0 / 1000, 544.0 / 680),
                ("Mallow Bend",     1.94, 460.0 / 1000, 585.0 / 680),
                ("Greenway Cross",  4.19, 630.0 / 1000, 496.0 / 680),
                ("Fenwick Rise",    6.70, 800.0 / 1000, 367.0 / 680),
                ("Rushmere",        8.54, 710.0 / 1000, 238.0 / 680),
                ("Cragmouth Gate",  10,   635.0 / 1000, 139.0 / 680),
            ]
        ),
        // KAN-23: the first hand-drawn-map journey. The catalog record here drives
        // "Available Journeys" and the KAN-7 journey screen (normalized 0…1 pin
        // positions); its faceted map authoring lives in `WindrisePeaksMap`. The ten
        // waypoint positions are the source-image pixels (1190×896) normalized to the
        // map bounds — x/1190, y/896. Names are Justin's originals (no real-world IP).
        TemplateSeed(
            name: windrisePeaksName,
            type: .fantasy,
            totalMiles: 302.4,
            backgroundImageName: "windrise_peaks_bg",
            markerImageName: "marker_wren",
            accentColorToken: "accent/primary",
            pathColorToken: "ink",
            waypoints: [
                ("Wavecrest",           0,     88.0 / 1190, 302.0 / 896),
                ("Millhollow",          14.2,  168.0 / 1190, 356.0 / 896),
                ("Sable Ford",          20.9,  196.0 / 1190, 392.0 / 896),
                ("Hallowmere",          72.9,  528.0 / 1190, 488.0 / 896),
                ("Oxbow Crossing",      122.6, 557.0 / 1190, 749.0 / 896),
                ("Thistlewood",         153.9, 758.0 / 1190, 678.0 / 896),
                ("Farrow's Rest",       172.1, 862.0 / 1190, 743.0 / 896),
                ("Stonewash Ford",      218.8, 1041.0 / 1190, 557.0 / 896),
                ("Rivergate",           227.7, 1090.0 / 1190, 520.0 / 896),
                ("The Windrise Peaks",  302.4, 1085.0 / 1190, 42.0 / 896),
            ]
        ),
        TemplateSeed(
            name: aroundTheWorldName,
            type: .realWorld,
            totalMiles: 40_075_000 / 1609.344, // circumference in meters -> miles
            backgroundImageName: "",
            markerImageName: "",
            accentColorToken: "accent/primary",
            pathColorToken: "ink",
            waypoints: []
        ),
    ]

    /// Ensures the catalog + the shared anchor exist, then drains any migration
    /// stash into instances. Idempotent — safe on every launch.
    ///
    /// If any existence fetch THROWS, we can't tell "empty" from "unknown", so
    /// we abort rather than risk duplicating on a populated store.
    static func seedIfNeeded(in context: ModelContext) {
        let now = Date()

        let existingTemplates: [JourneyTemplate]
        let existingAnchors: [ProgressUpdate]
        do {
            existingTemplates = try context.fetch(FetchDescriptor<JourneyTemplate>())
            existingAnchors = try context.fetch(FetchDescriptor<ProgressUpdate>())
        } catch {
            print("[SeedData] Existence check failed; aborting seed to avoid duplicates: \(error)")
            return
        }

        // MARK: - Retired templates (KAN-45) — removed BEFORE the catalog is
        // ensured, so a retired name can never be re-inserted by a stale seed.
        // Deleting a template is otherwise not a user flow (JourneyTemplate.swift);
        // this seed-time pass is the one sanctioned exception.
        for template in existingTemplates where retiredTemplateNames.contains(template.name) {
            // Instances do NOT cascade from the template — delete them
            // explicitly (their crossings cascade via UserJourney.crossings).
            for instance in template.instances ?? [] {
                context.delete(instance)
            }
            context.delete(template)
        }

        // MARK: - Templates — always ensured idempotently, by name.
        for seed in catalog {
            if let existing = existingTemplates.first(where: { $0.name == seed.name }) {
                backfill(template: existing, from: seed)
            } else {
                insert(seed: seed, in: context)
            }
        }

        // MARK: - Shared delta anchor — independent existence guard.
        if existingAnchors.isEmpty {
            let anchor = ProgressUpdate(
                anchorStartDate: now,
                lastProcessedDistance: 0,
                lastUpdated: now,
                sourceDevice: .unknown
            )
            context.insert(anchor)
        }

        try? context.save()

        // MARK: - Migration restore — recreate instances from the stash ONCE,
        // now that every template they reference is guaranteed present.
        restoreMigratedInstances(in: context)
    }

    // MARK: - Template insert / backfill

    private static func insert(seed: TemplateSeed, in context: ModelContext) {
        let template = JourneyTemplate(
            name: seed.name,
            type: seed.type,
            totalDistance: seed.totalMiles * metersPerMile,
            backgroundImageName: seed.backgroundImageName,
            markerImageName: seed.markerImageName,
            accentColorToken: seed.accentColorToken,
            pathColorToken: seed.pathColorToken
        )
        context.insert(template)

        var waypoints: [Waypoint] = []
        for (index, entry) in seed.waypoints.enumerated() {
            let waypoint = Waypoint(
                order: index,
                positionX: entry.x,
                positionY: entry.y,
                distanceFromStart: entry.miles * metersPerMile,
                name: entry.name
            )
            waypoint.template = template
            context.insert(waypoint)
            waypoints.append(waypoint)
        }
        template.waypoints = waypoints
    }

    /// One-time, self-limiting backfills for a template seeded before a field
    /// existed. Each is guarded on a sentinel so it is a no-op once applied.
    private static func backfill(template: JourneyTemplate, from seed: TemplateSeed) {
        // Theme tokens: only backfill a template still at the empty-background
        // sentinel, and only for a seed that actually carries art ("Around the
        // World" stays intentionally themeless and is never backfilled).
        if template.backgroundImageName.isEmpty && !seed.backgroundImageName.isEmpty {
            template.backgroundImageName = seed.backgroundImageName
            template.markerImageName = seed.markerImageName
            template.accentColorToken = seed.accentColorToken
            template.pathColorToken = seed.pathColorToken
        }

        // Waypoint positions: rewrite any still at the (0, 0) sentinel to their
        // real coordinates, keyed by `order`. Safe because no seeded coordinate
        // is (0, 0), so a placed waypoint is never mistaken for un-seeded.
        guard let waypoints = template.waypoints else { return }
        for waypoint in waypoints where waypoint.positionX == 0 && waypoint.positionY == 0 {
            guard waypoint.order < seed.waypoints.count else { continue }
            let entry = seed.waypoints[waypoint.order]
            waypoint.positionX = entry.x
            waypoint.positionY = entry.y
        }

        // KAN-40: self-healing First-Journey waypoint reconciliation. First Journey's
        // waypoints were re-authored (new names/miles/positions to match the faceted
        // FirstJourneyMap). The (0,0) position sentinel above CANNOT catch this — the
        // old waypoints have real, non-zero coordinates — so a store that already
        // seeded the old six (every existing dev/QA sim) would keep stale
        // names/miles in `template.waypoints`, silently desyncing crossings,
        // JourneyStatsCalculator, leg labels, and notification-content lookup (which
        // keys on the NEW names) from the correct faceted MapAuthoring.
        //
        // Fix in place, scoped to First Journey only: the old→new mapping is 1:1 by
        // `order` (6→6), so we rewrite each waypoint's name / distanceFromStart /
        // positionX / positionY to the seed values — no row insert/delete, no schema
        // change, no store migration. Idempotent: once rewritten the fields match the
        // seed, so `needsReconcile` is false and this is a no-op on every later launch.
        //
        // Existing `WaypointCrossing` snapshots are historical and are intentionally
        // NOT rewritten here; they degrade gracefully under KAN-14's "date not
        // recorded" rules, which is acceptable.
        guard template.name == firstJourneyName else { return }
        for waypoint in waypoints {
            guard waypoint.order < seed.waypoints.count else { continue }
            let entry = seed.waypoints[waypoint.order]
            let expectedMeters = entry.miles * metersPerMile
            let needsReconcile = waypoint.name != entry.name
                || abs(waypoint.distanceFromStart - expectedMeters) > 0.5
                || waypoint.positionX != entry.x
                || waypoint.positionY != entry.y
            if needsReconcile {
                waypoint.name = entry.name
                waypoint.distanceFromStart = expectedMeters
                waypoint.positionX = entry.x
                waypoint.positionY = entry.y
            }
        }
    }

    // MARK: - Migration restore

    /// Drains the KAN-10 migration stash: each stashed legacy journey becomes a
    /// fresh UserJourney matched to its template by name, with distance and
    /// start date verbatim and status mapped from the old booleans. Clears the
    /// stash afterward, so this runs exactly once per upgrade.
    private static func restoreMigratedInstances(in context: ModelContext) {
        guard let snapshots = MigrationStash.load() else { return }

        let templates = (try? context.fetch(FetchDescriptor<JourneyTemplate>())) ?? []
        let byName = Dictionary(templates.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })

        // Drain idempotently. insert -> save -> clear is NOT crash-atomic: a
        // kill between the save and the clear would re-drain on the next launch
        // and duplicate every instance (including two `.active` of one template
        // — an invisible delta double-credit behind one-card precedence). So we
        // skip any snapshot whose template already carries an instance matching
        // it exactly (same startDate + distanceAccumulated). A re-run therefore
        // recreates nothing, and we only clear the stash after a CONFIRMED save.
        let existing = (try? context.fetch(FetchDescriptor<UserJourney>())) ?? []

        for snapshot in snapshots {
            guard let template = byName[snapshot.name] else {
                // No matching template (renamed/removed content). Nothing to
                // attach to — skip; the stash is still cleared below (once the
                // save succeeds) so it is not retried forever.
                continue
            }
            let alreadyRestored = existing.contains { instance in
                instance.template?.persistentModelID == template.persistentModelID
                    && instance.startDate == snapshot.startDate
                    && instance.distanceAccumulated == snapshot.distanceAccumulated
            }
            if alreadyRestored { continue }

            let instance = UserJourney(
                startDate: snapshot.startDate,
                distanceAccumulated: snapshot.distanceAccumulated,
                status: snapshot.mappedStatus,
                template: template
            )
            context.insert(instance)
        }

        do {
            try context.save()
            MigrationStash.clear() // only after the instances are durably saved
        } catch {
            print("[SeedData] Migration restore save failed — keeping stash for retry: \(error)")
        }
    }
}
