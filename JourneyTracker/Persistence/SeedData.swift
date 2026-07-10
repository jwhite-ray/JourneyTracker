//
//  SeedData.swift
//  JourneyTracker
//
//  First-run seeding: the starter journeys plus the single shared delta
//  anchor. Journey and waypoint numbers come from the App Concept doc's
//  tables and live here in the DATA layer, never as literals in view code.
//
//  Journeys start at first-run "now", and the anchor's anchorStartDate is that
//  same instant, so there is no gap to backfill on a fresh install.
//
//  Every insertable piece is guarded INDEPENDENTLY so an already-seeded dev
//  install still receives anything added after it was first seeded, without
//  ever duplicating a journey, waypoint, or anchor.
//

import Foundation
import SwiftData

enum SeedData {

    /// 1 statute mile in meters — sourced from the single formatting authority,
    /// never re-hardcoded here.
    private static let metersPerMile = DistanceFormatter.metersPerMile

    // Stable identities used by the independent existence guards below. Names
    // are the match key: these are seed-owned, original strings that no user
    // flow renames, so name equality is a reliable identity for "already seeded"
    // without needing a separate stable-UUID registry.
    private static let emberSpireName = "The Road to Ember Spire"
    private static let firstJourneyName = "First Journey"

    /// Waypoint table for "The Road to Ember Spire" (name, cumulative miles,
    /// normalized map position). Positions are image-relative (0...1).
    private static let emberSpireWaypoints: [(name: String, miles: Double, x: Double, y: Double)] = [
        ("Thistledown",    0,    0.12, 0.88),
        ("Crosswater",     120,  0.28, 0.78),
        ("Silvergate",     460,  0.20, 0.60),
        ("The Deepdelve",  660,  0.40, 0.52),
        ("Whisperwood",    720,  0.58, 0.55),
        ("The Windmark",   1040, 0.52, 0.38),
        ("Whitewatch",     1540, 0.70, 0.24),
        ("Ember Spire",    1800, 0.82, 0.12),
    ]

    /// Waypoint table for "First Journey" (name, cumulative miles, normalized
    /// map position).
    private static let firstJourneyWaypoints: [(name: String, miles: Double, x: Double, y: Double)] = [
        ("Trailhead",         0,  0.15, 0.85),
        ("First Rest",        1,  0.30, 0.72),
        ("Willowbend",        3,  0.45, 0.60),
        ("Old Oak",           7,  0.60, 0.42),
        ("Lastlight Bridge",  9,  0.75, 0.28),
        ("Journey's End",     10, 0.88, 0.14),
    ]

    /// Seeds the journeys and the single shared anchor. Each insertable is
    /// guarded INDEPENDENTLY so, whenever the existence checks can be trusted,
    /// exactly one of each is ever created. Idempotent — safe on every launch.
    ///
    /// If any existence fetch THROWS, we can't tell "empty" from "unknown", so
    /// we abort seeding entirely rather than risk duplicating on a populated
    /// store.
    static func seedIfNeeded(in context: ModelContext) {
        let now = Date()

        // Distinguish "fetch threw" from "genuinely empty" — a throwing fetch
        // must not read as empty and trigger duplicate inserts.
        let existingJourneys: [Journey]
        let existingAnchors: [ProgressUpdate]
        do {
            existingJourneys = try context.fetch(FetchDescriptor<Journey>())
            existingAnchors = try context.fetch(FetchDescriptor<ProgressUpdate>())
        } catch {
            print("[SeedData] Existence check failed; aborting seed to avoid duplicates: \(error)")
            return
        }

        // MARK: - Original starter set (Ember Spire + Around the World)
        //
        // Guarded on the store being empty, preserving the original all-or-
        // nothing behavior for the very first seed of these two.
        if existingJourneys.isEmpty {
            // Journey 1 — fantasy, 1,800 mi. Themed.
            let emberSpire = Journey(
                name: emberSpireName,
                type: .fantasy,
                totalDistance: 2_896_819,
                startDate: now,
                backgroundImageName: "ember_spire_bg",
                markerImageName: "marker_wren",
                accentColorToken: "accent/primary",
                pathColorToken: "ink"
            )
            context.insert(emberSpire)

            var waypoints: [Waypoint] = []
            for (index, entry) in emberSpireWaypoints.enumerated() {
                let waypoint = Waypoint(
                    order: index,
                    positionX: entry.x,
                    positionY: entry.y,
                    distanceFromStart: entry.miles * metersPerMile,
                    name: entry.name
                )
                waypoint.journey = emberSpire
                context.insert(waypoint)
                waypoints.append(waypoint)
            }
            emberSpire.waypoints = waypoints

            // Journey 2 — real world, circumference of the Earth. Neutral theme:
            // no map in scope, so background/marker stay empty and accent/path
            // fall to their model defaults.
            let aroundTheWorld = Journey(
                name: "Around the World",
                type: .realWorld,
                totalDistance: 40_075_000,
                startDate: now
            )
            context.insert(aroundTheWorld)
        }

        // MARK: - First Journey — independent existence guard
        //
        // Keyed on name equality against the current store snapshot, mirroring
        // the anchor's independent guard. Inserted iff not already present, so
        // an install seeded before First Journey existed still receives it, and
        // relaunches never duplicate it.
        if !existingJourneys.contains(where: { $0.name == firstJourneyName }) {
            let firstJourney = Journey(
                name: firstJourneyName,
                type: .fantasy,
                totalDistance: 10 * metersPerMile,
                startDate: now,
                isActive: true,
                backgroundImageName: "first_journey_bg",
                markerImageName: "marker_wren",
                accentColorToken: "accent/secondary",
                pathColorToken: "ink"
            )
            context.insert(firstJourney)

            var waypoints: [Waypoint] = []
            for (index, entry) in firstJourneyWaypoints.enumerated() {
                let waypoint = Waypoint(
                    order: index,
                    positionX: entry.x,
                    positionY: entry.y,
                    distanceFromStart: entry.miles * metersPerMile,
                    name: entry.name
                )
                waypoint.journey = firstJourney
                context.insert(waypoint)
                waypoints.append(waypoint)
            }
            firstJourney.waypoints = waypoints
        }

        // MARK: - Ember Spire position backfill (one-time, self-limiting)
        //
        // Older installs seeded Ember Spire's waypoints at the (0, 0) sentinel.
        // Rewrite any still at that sentinel to their real coordinates, keyed by
        // `order`. Safe precisely because no seeded coordinate is (0, 0), so a
        // correctly-positioned waypoint is never mistaken for un-seeded and the
        // backfill is a no-op once applied.
        for journey in existingJourneys where journey.name == emberSpireName {
            guard let waypoints = journey.waypoints else { continue }
            for waypoint in waypoints where waypoint.positionX == 0 && waypoint.positionY == 0 {
                guard waypoint.order < emberSpireWaypoints.count else { continue }
                let entry = emberSpireWaypoints[waypoint.order]
                waypoint.positionX = entry.x
                waypoint.positionY = entry.y
            }
        }

        // MARK: - Shared delta anchor — independent existence guard
        //
        // On a normal fresh install it shares `now` with the journeys above, so
        // there is no gap to backfill.
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
    }
}
