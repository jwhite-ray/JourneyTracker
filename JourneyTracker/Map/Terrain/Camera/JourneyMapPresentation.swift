//
//  JourneyMapPresentation.swift
//  JourneyTracker
//
//  The read-only model both P3 map surfaces share (KAN-20). It bundles an
//  authored map, its generated `TerrainScene`, and a marker mileage, and derives
//  everything the camera needs: the marker's map-unit position, the current leg
//  (last-reached → next waypoint), and the chapter / full-journey framings.
//
//  It only READS progress — the marker's mileage is an input, interpolated along
//  the trek path by real distance exactly like `MarkerPositionCalculator` (App
//  Concept doc: "the map reads progress; it never owns or computes it"). P4 wires
//  a real `UserJourney`'s distance in here; today the debug entries drive it with
//  sample / fixture data and a fixed mid-journey mileage.
//

import CoreGraphics

struct JourneyMapPresentation {
    let authoring: MapAuthoring
    let scene: TerrainScene
    /// The marker's position along the journey, in real miles from the start.
    var markerMiles: Double

    /// The trek path sampled to the same smoothed curve the renderer draws, so
    /// arc length ↔ mileage matches the validator and the rendered line.
    let sampledTrek: [CGPoint]

    init(authoring: MapAuthoring, scene: TerrainScene, markerMiles: Double) {
        self.authoring = authoring
        self.scene = scene
        self.markerMiles = markerMiles
        self.sampledTrek = MapGeometry.catmullRomSampled(authoring.trekPath?.points ?? [])
    }

    /// Miles per map unit for this journey (0 if there's no measurable path).
    var milesPerMapUnit: Double { authoring.milesPerMapUnit }

    private func mapUnits(forMiles miles: Double) -> CGFloat {
        guard milesPerMapUnit > 0 else { return 0 }
        return CGFloat(miles / milesPerMapUnit)
    }

    /// The marker's map-unit position — the point `markerMiles` along the path.
    var markerPosition: CGPoint {
        MapGeometry.pointAtArcLength(sampledTrek, arcLength: mapUnits(forMiles: markerMiles))
    }

    /// Waypoints sorted by mileage.
    private var orderedWaypoints: [MapWaypoint] {
        authoring.waypoints.sorted { $0.milesFromStart < $1.milesFromStart }
    }

    /// The current leg: (last-reached waypoint, next waypoint). Degrades sensibly
    /// at the ends (before the first / after the last).
    var currentLeg: (lastReached: MapWaypoint, next: MapWaypoint)? {
        let wps = orderedWaypoints
        guard wps.count >= 2 else { return nil }
        let reached = wps.last { $0.milesFromStart <= markerMiles + 0.0001 } ?? wps.first!
        let next = wps.first { $0.milesFromStart > markerMiles + 0.0001 } ?? wps.last!
        // If reached == next (marker exactly on a middle waypoint at the array
        // end), widen to the adjacent pair so the leg has extent.
        if reached.id == next.id, let idx = wps.firstIndex(where: { $0.id == reached.id }) {
            let lo = wps[max(0, idx - 1)]
            let hi = wps[min(wps.count - 1, idx + 1)]
            return (lo, hi)
        }
        return (reached, next)
    }

    /// Sampled trek vertices lying on the current leg — passed to chapter framing
    /// so a leg that meanders outside its endpoint box still fits.
    private func legVertices(from lo: Double, to hi: Double) -> [CGPoint] {
        guard sampledTrek.count > 1, milesPerMapUnit > 0 else { return [] }
        var out: [CGPoint] = []
        var acc: CGFloat = 0
        for i in 0..<sampledTrek.count {
            if i > 0 { acc += MapGeometry.dist(sampledTrek[i - 1], sampledTrek[i]) }
            let miles = Double(acc) * milesPerMapUnit
            if miles >= lo - 0.001 && miles <= hi + 0.001 { out.append(sampledTrek[i]) }
        }
        return out
    }

    // MARK: - Framings

    /// Chapter view: current leg framed, marker centered (Justin's KAN-20 ruling).
    func chapterCamera(viewport: CGSize, padding: CGFloat = 44) -> MapCamera {
        guard let leg = currentLeg else {
            return MapCamera.fullJourney(bounds: authoring.bounds, in: viewport)
        }
        let extra = legVertices(from: leg.lastReached.milesFromStart, to: leg.next.milesFromStart)
        return MapCamera.chapter(lastReached: leg.lastReached.position,
                                 next: leg.next.position,
                                 marker: markerPosition,
                                 extraPoints: extra,
                                 in: viewport,
                                 padding: padding)
    }

    /// Full-journey overview: the whole authored map on one screen.
    func overviewCamera(viewport: CGSize, padding: CGFloat = 28) -> MapCamera {
        MapCamera.fullJourney(bounds: authoring.bounds, in: viewport, padding: padding)
    }

    /// Min zoom = full-journey fit. Max zoom lets the user dive until the map hits
    /// the DESIGN REFERENCE scale (ptPerMile == referencePtPerMile, where the size
    /// taper reaches 1.0 and the map shows full approved-chapter detail) — or the
    /// 2× chapter cap, whichever is deeper (KAN-20 Gate 3). On a long journey the
    /// reference is a deep dive; capping there prevents glyphs exceeding authored
    /// sizes (the taper is min-clamped at 1.0 anyway).
    func zoomBounds(viewport: CGSize) -> (min: CGFloat, max: CGFloat) {
        let overview = overviewCamera(viewport: viewport).zoom
        let chapter = chapterCamera(viewport: viewport).zoom
        let lo = min(overview, chapter)
        let referenceZoom = MapLOD().referencePtPerMile * CGFloat(max(milesPerMapUnit, 0))
        let hi = max(max(overview, chapter) * 2, referenceZoom)
        return (lo, max(hi, lo * 1.0001))
    }
}
