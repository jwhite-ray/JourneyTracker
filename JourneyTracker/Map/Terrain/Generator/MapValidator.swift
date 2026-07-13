//
//  MapValidator.swift
//  JourneyTracker
//
//  Build-time validators for authored maps (KAN-19, P2). Placement rules are
//  build-time checks, not runtime conventions: a map that breaks a rule is an
//  AUTHORING error the author fixes, and the shipped map is correct by
//  construction (App Concept doc, "placement rules are build-time validators").
//
//  `validate` returns ALL violations (never first-failure), each naming the region
//  and the rule, so an author fixes everything in one pass. `MapGenerator` runs
//  this first and refuses to emit a scene from an invalid authoring.
//
//  Real-mile bounds come from the App Concept doc's canonical table and are checked
//  against TOTAL authored size (ranges may run off-map; the renderer clips).
//

import Foundation
import CoreGraphics

/// One authoring-rule violation.
struct MapViolation: Identifiable, Equatable {
    var id = UUID()
    /// The offending region/waypoint identifier, for the author to locate it.
    var subject: String
    /// The rule that failed, human-readable.
    var rule: String
    /// What was wrong (measured value vs. bound, etc.).
    var detail: String

    var message: String { "\(subject): \(rule) — \(detail)" }
}

enum MapValidator {

    /// Soft sanity cap on how far inland a settlement may sit from water (KAN-23
    /// "drawing trumps the rules": real worlds have road/market towns miles from any
    /// shore — the pilot's farthest is ~33 mi). This is a physical-absurdity guard,
    /// not the §07.5 "villages hug the shore" aesthetic (which is now Jeff's design
    /// preference, not a validator).
    static let settlementWaterMiles = 40.0
    /// Map-unit tolerance for "waypoint lies on the trek path."
    static let onPathToleranceUnits: CGFloat = 1.5
    /// Map-unit tolerance for a river mouth counting as "at the coastline."
    static let coastMouthToleranceUnits: CGFloat = 10
    /// Ceiling on the anchor tolerance; the effective tolerance is the smaller of
    /// this and 5% of the journey, so a 10/20-mi journey isn't vacuously valid.
    static let anchorMileToleranceCeiling = 6.0
    /// Spacing for distance-sampling paths, so a minimum-size lake can't slip
    /// between two path samples (§07.5 paths stay on land).
    static let pathSampleSpacing: CGFloat = 2

    static func anchorMileTolerance(for authoring: MapAuthoring) -> Double {
        min(anchorMileToleranceCeiling, 0.05 * authoring.journeyMiles)
    }

    /// Returns every violation in `authoring`. Empty ⇒ the map is valid.
    static func validate(_ authoring: MapAuthoring) -> [MapViolation] {
        var out: [MapViolation] = []
        out += validateUniqueIDs(authoring)
        out += validateAnchor(authoring)
        out += validateRealMileBounds(authoring)
        out += validateRivers(authoring)
        out += validatePathsAvoidWater(authoring)
        out += validateSettlements(authoring)
        out += validateWaypointsOnPath(authoring)
        return out
    }

    // MARK: - Unique region ids (each keys an RNG substream)

    private static func validateUniqueIDs(_ a: MapAuthoring) -> [MapViolation] {
        var seen = Set<String>()
        var out: [MapViolation] = []
        for region in a.regions where !seen.insert(region.id).inserted {
            out.append(MapViolation(subject: region.id, rule: "region ids unique",
                                    detail: "duplicate id — region substreams would collide and reshuffle"))
        }
        var seenWP = Set<String>()
        for wp in a.waypoints where !seenWP.insert(wp.id).inserted {
            out.append(MapViolation(subject: wp.id, rule: "waypoint ids unique",
                                    detail: "duplicate waypoint id"))
        }
        return out
    }

    // MARK: - Smoothed water geometry (mirrors what the renderer FILLS)

    /// Lake rings sampled as the renderer's CLOSED smoothed loop — the bulged
    /// shape actually filled, not the raw authored chords.
    static func smoothedLakeRings(_ a: MapAuthoring) -> [[CGPoint]] {
        a.lakes.map { MapGeometry.catmullRomSampledClosed($0.ring) }
    }

    /// The closed sea polygon per coast (KAN-23: a map may have several coasts).
    /// Empty polygons are dropped.
    static func seaPolygons(_ a: MapAuthoring) -> [[CGPoint]] {
        a.coasts.map { MapGeometry.seaPolygon(coastline: $0.coastline, seaCorners: $0.seaCorners) }
            .filter { !$0.isEmpty }
    }

    /// The smoothed shore polyline (open) per coast, for river-mouth "at the coast"
    /// distance and settlement "by water" distance.
    static func smoothedCoastlines(_ a: MapAuthoring) -> [[CGPoint]] {
        a.coasts.map { MapGeometry.catmullRomSampled($0.coastline) }
    }

    // MARK: - Scale anchor: trek arc length ↔ journey mileage

    private static func validateAnchor(_ a: MapAuthoring) -> [MapViolation] {
        var out: [MapViolation] = []
        guard let trek = a.trekPath, trek.points.count >= 2 else {
            out.append(MapViolation(subject: a.name, rule: "trek path required",
                                    detail: "a map needs one trekPath region with ≥2 points to anchor scale"))
            return out
        }
        guard a.journeyMiles > 0 else {
            out.append(MapViolation(subject: a.name, rule: "journey mileage required",
                                    detail: "journeyMiles must be > 0 to define miles-per-map-unit"))
            return out
        }
        let mpu = a.milesPerMapUnit
        guard mpu > 0 else {
            out.append(MapViolation(subject: trek.id, rule: "trek arc length",
                                    detail: "trek path has zero measurable arc length"))
            return out
        }
        // Each waypoint's arc position along the path (in miles) must agree with
        // its authored milesFromStart — this is the anchor being consistent.
        let sampled = MapGeometry.catmullRomSampled(trek.points)
        let tolerance = anchorMileTolerance(for: a)
        var lastDistance = -Double.greatestFiniteMagnitude
        for wp in a.waypoints {
            if wp.milesFromStart < 0 || wp.milesFromStart > a.journeyMiles {
                out.append(MapViolation(subject: wp.name, rule: "milesFromStart in range",
                                        detail: "\(fmt(wp.milesFromStart)) mi is outside 0…\(fmt(a.journeyMiles)) mi"))
            }
            if wp.milesFromStart < lastDistance {
                out.append(MapViolation(subject: wp.name, rule: "waypoints monotonic",
                                        detail: "milesFromStart decreases along the path"))
            }
            lastDistance = wp.milesFromStart
            let arcMiles = Double(MapGeometry.arcLengthAtNearest(wp.position, on: sampled)) * mpu
            if abs(arcMiles - wp.milesFromStart) > tolerance {
                out.append(MapViolation(subject: wp.name, rule: "anchor consistency",
                                        detail: "sits at \(fmt(arcMiles)) mi along the path but is authored at \(fmt(wp.milesFromStart)) mi (tolerance \(fmt(tolerance)) mi)"))
            }
        }
        return out
    }

    // MARK: - Real-mile bounds (App Concept doc's canonical table)

    private static func validateRealMileBounds(_ a: MapAuthoring) -> [MapViolation] {
        let mpu = a.milesPerMapUnit
        guard mpu > 0 else { return [] } // anchor validator already reported this
        let sqMpu = a.squareMilesPerSquareUnit
        var out: [MapViolation] = []

        for region in a.regions {
            switch region {
            case .range(let r):
                let lengthMi = Double(2 * r.halfLength) * mpu
                let widthMi = Double(2 * r.halfWidth) * mpu
                // KAN-23: 15 mi min covers hill-chains as well as great massifs
                // (one `range` kind spans both; the renderer draws short/low ones as
                // hills). Loosened from 75 to fit real hand-drawn hill country.
                if lengthMi < 15 || lengthMi > 300 {
                    out.append(MapViolation(subject: r.id, rule: "range/hill-chain length 15–300 mi",
                                            detail: "authored length is \(fmt(lengthMi)) mi"))
                }
                if widthMi > 10 {
                    out.append(MapViolation(subject: r.id, rule: "range width ≤ 10 mi",
                                            detail: "authored width is \(fmt(widthMi)) mi"))
                }
            case .forest(let f):
                let areaMi = Double(.pi * f.rx * f.ry) * sqMpu
                if areaMi < 0.5 || areaMi > 300 {
                    out.append(MapViolation(subject: f.id, rule: "forest area 0.5–300 sq mi",
                                            detail: "authored area is \(fmt(areaMi)) sq mi"))
                }
            case .lake(let l):
                let areaMi = Double(MapGeometry.polygonArea(l.ring)) * sqMpu
                if areaMi < 0.3 || areaMi > 60 {  // KAN-23: cap raised 30 → 60 sq mi
                    out.append(MapViolation(subject: l.id, rule: "lake area 0.3–60 sq mi",
                                            detail: "authored area is \(fmt(areaMi)) sq mi"))
                }
            case .river(let r):
                let lengthMi = Double(MapGeometry.polylineLength(r.hint)) * mpu
                if lengthMi < 2 {
                    out.append(MapViolation(subject: r.id, rule: "river length ≥ 2 mi",
                                            detail: "authored length is \(fmt(lengthMi)) mi"))
                }
            case .coast, .groundCover, .settlement, .road, .trekPath:
                break // ocean unbounded; ground cover / roads / paths have no size rule
            }
        }
        return out
    }

    // MARK: - Rivers: source not IN water; mouth in a lake, at the coast, or off-map

    private static func validateRivers(_ a: MapAuthoring) -> [MapViolation] {
        var out: [MapViolation] = []
        let lakeRings = smoothedLakeRings(a)
        let seas = seaPolygons(a)
        let shores = smoothedCoastlines(a)

        for river in a.rivers {
            guard let source = river.hint.first, let mouth = river.hint.last else { continue }
            // KAN-23 "drawing trumps the rules": a source may rise anywhere on land
            // (upland spring, range, or off-map). The only kept rule is that it must
            // NOT rise inside water — a river can't spring out of a lake or the sea.
            let sourceInLake = lakeRings.contains { MapGeometry.polygonContains(source, $0) }
            let sourceInSea = seas.contains { MapGeometry.polygonContains(source, $0) }
            if sourceInLake || sourceInSea {
                out.append(MapViolation(subject: river.id, rule: "river source not in water",
                                        detail: "source \(fmt(source)) rises inside a lake or the sea"))
            }
            // A mouth terminates in a lake, at the coast, OR by exiting the authored
            // bounds (draining to an off-map sea/basin; the renderer clips). Only a
            // mouth that stops mid-land inside the map is an error.
            let endsInLake = lakeRings.contains { MapGeometry.polygonContains(mouth, $0) }
            let endsAtCoast = shores.contains { MapGeometry.distanceToPolyline(mouth, $0) <= coastMouthToleranceUnits }
            let endsOffMap = !a.bounds.contains(mouth)
            if !endsInLake && !endsAtCoast && !endsOffMap {
                out.append(MapViolation(subject: river.id, rule: "river mouth in a lake, at the coast, or off-map",
                                        detail: "mouth \(fmt(mouth)) terminates mid-land inside the map"))
            }
        }
        return out
    }

    // MARK: - Roads / trek path never cross a lake or the ocean

    private static func validatePathsAvoidWater(_ a: MapAuthoring) -> [MapViolation] {
        var out: [MapViolation] = []
        let lakeRings = smoothedLakeRings(a)
        let seas = seaPolygons(a)
        let lakeIDs = a.lakes.map(\.id)

        func check(_ id: String, _ label: String, _ points: [CGPoint]) {
            // Sample the SMOOTHED path (the drawn curve), then densify to a fixed
            // spacing so no small lake fits between two samples.
            let sampled = MapGeometry.densify(MapGeometry.catmullRomSampled(points), spacing: pathSampleSpacing)
            for p in sampled {
                if let idx = lakeRings.firstIndex(where: { MapGeometry.polygonContains(p, $0) }) {
                    out.append(MapViolation(subject: id, rule: "\(label) stays on land",
                                            detail: "crosses lake \(lakeIDs[idx]) near \(fmt(p))"))
                    return
                }
                if seas.contains(where: { MapGeometry.polygonContains(p, $0) }) {
                    out.append(MapViolation(subject: id, rule: "\(label) stays on land",
                                            detail: "crosses the ocean near \(fmt(p))"))
                    return
                }
            }
        }

        for region in a.regions {
            if case .trekPath(let t) = region { check(t.id, "trek path", t.points) }
            if case .road(let r) = region { check(r.id, "road", r.points) }
        }
        return out
    }

    // MARK: - Settlements sit by water

    private static func validateSettlements(_ a: MapAuthoring) -> [MapViolation] {
        var out: [MapViolation] = []
        let mpu = a.milesPerMapUnit
        guard mpu > 0 else { return [] }
        let lakeRings = smoothedLakeRings(a)
        let rivers = a.rivers
        let shores = smoothedCoastlines(a)

        for region in a.regions {
            guard case .settlement(let s) = region else { continue }
            var nearestUnits = CGFloat.infinity
            for ring in lakeRings {
                var closed = ring
                if let first = ring.first { closed.append(first) } // close the loop for distance
                nearestUnits = min(nearestUnits, MapGeometry.distanceToPolyline(s.site, closed))
            }
            for river in rivers {
                nearestUnits = min(nearestUnits, MapGeometry.distanceToPolyline(s.site, MapGeometry.catmullRomSampled(river.hint)))
            }
            for shore in shores {
                nearestUnits = min(nearestUnits, MapGeometry.distanceToPolyline(s.site, shore))
            }
            let nearestMiles = Double(nearestUnits) * mpu
            if nearestMiles > settlementWaterMiles {
                out.append(MapViolation(subject: s.name ?? s.id, rule: "settlement within \(Int(settlementWaterMiles)) mi of water",
                                        detail: "nearest water is \(fmt(nearestMiles)) mi away (cap \(fmt(settlementWaterMiles)) mi)"))
            }
        }
        return out
    }

    // MARK: - Every waypoint lies on the trek path

    private static func validateWaypointsOnPath(_ a: MapAuthoring) -> [MapViolation] {
        guard let trek = a.trekPath else { return [] } // anchor validator flags a missing path
        let sampled = MapGeometry.catmullRomSampled(trek.points)
        var out: [MapViolation] = []
        for wp in a.waypoints {
            let d = MapGeometry.distanceToPolyline(wp.position, sampled)
            if d > onPathToleranceUnits {
                out.append(MapViolation(subject: wp.name, rule: "waypoint on trek path",
                                        detail: "is \(fmt(Double(d))) map units off the path (tolerance \(fmt(Double(onPathToleranceUnits))))"))
            }
        }
        return out
    }

    // MARK: - Helpers

    private static func fmt(_ v: Double) -> String { String(format: "%.1f", v) }
    private static func fmt(_ p: CGPoint) -> String { String(format: "(%.0f, %.0f)", p.x, p.y) }
}
