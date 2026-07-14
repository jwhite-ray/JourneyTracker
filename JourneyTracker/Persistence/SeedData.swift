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

    private static let emberSpireName = "The Road to Ember Spire"
    private static let firstJourneyName = "First Journey"
    private static let aroundTheWorldName = "Around the World"
    private static let lanternRoadName = "The Lantern Road"
    private static let windrisePeaksName = "Road to The Windrise Peaks"

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
        TemplateSeed(
            name: emberSpireName,
            type: .fantasy,
            totalMiles: 1_800,
            backgroundImageName: "ember_spire_bg",
            markerImageName: "marker_wren",
            accentColorToken: "accent/primary",
            pathColorToken: "ink",
            waypoints: [
                ("Thistledown",    0,    0.12, 0.88),
                ("Crosswater",     120,  0.28, 0.78),
                ("Silvergate",     460,  0.20, 0.60),
                ("The Deepdelve",  660,  0.40, 0.52),
                ("Whisperwood",    720,  0.58, 0.55),
                ("The Windmark",   1040, 0.52, 0.38),
                ("Whitewatch",     1540, 0.70, 0.24),
                ("Ember Spire",    1800, 0.82, 0.12),
            ]
        ),
        TemplateSeed(
            name: firstJourneyName,
            type: .fantasy,
            totalMiles: 10,
            backgroundImageName: "first_journey_bg",
            markerImageName: "marker_wren",
            accentColorToken: "accent/secondary",
            pathColorToken: "ink",
            waypoints: [
                ("Trailhead",         0,  0.15, 0.85),
                ("First Rest",        1,  0.30, 0.72),
                ("Willowbend",        3,  0.45, 0.60),
                ("Old Oak",           7,  0.60, 0.42),
                ("Lastlight Bridge",  9,  0.75, 0.28),
                ("Journey's End",     10, 0.88, 0.14),
            ]
        ),
        TemplateSeed(
            name: lanternRoadName,
            type: .fantasy,
            totalMiles: 20,
            backgroundImageName: "lantern_road_bg",
            markerImageName: "marker_wren",
            accentColorToken: "accent/secondary",
            pathColorToken: "ink",
            waypoints: [
                ("Wickgate",         0,  0.14, 0.86),
                ("Foglow Bridge",    3,  0.24, 0.76),
                ("Palefire Hollow",  17, 0.74, 0.26),
                ("Lanternrest",      20, 0.86, 0.14),
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
