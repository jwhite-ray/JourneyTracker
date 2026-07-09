//
//  SeedData.swift
//  JourneyTracker
//
//  First-run seeding: the two starter journeys plus the single shared delta
//  anchor. Journey and waypoint numbers come from the App Concept doc's
//  tables and live here in the DATA layer, never as literals in view code.
//
//  Both journeys start at first-run "now", and the anchor's anchorStartDate
//  is that same instant, so there is no gap to backfill on a fresh install.
//

import Foundation
import SwiftData

enum SeedData {

    /// 1 statute mile in meters.
    private static let metersPerMile = 1609.344

    /// Waypoint table for "The Road to Ember Spire" (name, cumulative miles).
    /// Positions are placeholder image-relative values until real art exists.
    private static let emberSpireWaypoints: [(name: String, miles: Double)] = [
        ("Thistledown", 0),
        ("Crosswater", 120),
        ("Silvergate", 460),
        ("The Deepdelve", 660),
        ("Whisperwood", 720),
        ("The Windmark", 1040),
        ("Whitewatch", 1540),
        ("Ember Spire", 1800),
    ]

    /// Seeds the journeys and the single shared anchor. The journeys and the
    /// anchor are guarded INDEPENDENTLY so, whenever the existence checks can be
    /// trusted, exactly one anchor is ever created (a duplicate anchor with a
    /// fresh start date would replay all distance since install). Idempotent —
    /// safe to call on every launch.
    ///
    /// If either existence fetch THROWS, we can't tell "empty" from "unknown",
    /// so we abort seeding entirely rather than risk duplicating journeys or
    /// anchors on a populated store.
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

        if existingJourneys.isEmpty {
            // Journey 1 — fantasy, 1,800 mi.
            let emberSpire = Journey(
                name: "The Road to Ember Spire",
                type: .fantasy,
                totalDistance: 2_896_819,
                startDate: now
            )
            context.insert(emberSpire)

            var waypoints: [Waypoint] = []
            for (index, entry) in emberSpireWaypoints.enumerated() {
                let waypoint = Waypoint(
                    order: index,
                    distanceFromStart: entry.miles * metersPerMile,
                    name: entry.name
                )
                waypoint.journey = emberSpire
                context.insert(waypoint)
                waypoints.append(waypoint)
            }
            emberSpire.waypoints = waypoints

            // Journey 2 — real world, circumference of the Earth.
            let aroundTheWorld = Journey(
                name: "Around the World",
                type: .realWorld,
                totalDistance: 40_075_000,
                startDate: now
            )
            context.insert(aroundTheWorld)
        }

        // The single shared delta anchor — guarded on its own. On a normal
        // fresh install it shares `now` with the journeys above, so there is no
        // gap to backfill.
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
