//
//  FirstJourneyMap.swift
//  JourneyTracker
//
//  The second authored faceted-map journey (KAN-40): "First Journey", the 10-mile
//  fixture. Translated from Justin's real ~9.6-mi canyon-reservoir loop (Lehi UT)
//  and re-expressed in the Design-System §07 terrain vocabulary — same authoring
//  shape as WindrisePeaksMap: REGION records + a deterministic seed, following the
//  SampleJourneyMap / EmberSpireScaleFixture conventions.
//
//  Coordinates are SOURCE-PIXEL map units (1000×680, origin top-left) used directly.
//  The trek was authored WEST-of-start → destination (waypoint order). Region ids
//  below are INTERNAL only — they key each region's RNG substream and never surface;
//  the DISPLAY names are the approved waypoint names in `make()`.
//
//  "Small map, big scenery" (KAN-23 off-map-range ruling): the western faceted range
//  runs off the top/bottom/left edges, so a <10-mi frame still reads as a real place.
//  The fixture is canonically 10 mi (NOT the real 9.6 — the model rescales the trek
//  arc to `journeyMiles`). This authoring passes every current validator
//  (MapValidator.validate → 0).
//

import CoreGraphics

enum FirstJourneyMap {

    /// The journey's canonical total distance (App Concept doc catalog / SeedData).
    /// Anchors miles-per-map-unit against the trek path's smoothed arc length. This
    /// is the fixture value (10), not the real-world 9.6 — the model rescales.
    static let journeyMiles = 10.0

    /// The authored trek — EXACTLY the six waypoint positions, in order. Catmull-Rom
    /// is interpolating, so each waypoint is a control point on the smoothed curve.
    static let trek: [CGPoint] = [
        CGPoint(x: 300, y: 544),   // Fernhollow  (start)
        CGPoint(x: 460, y: 585),   // Mallow Bend
        CGPoint(x: 630, y: 496),   // Greenway Cross
        CGPoint(x: 800, y: 367),   // Fenwick Rise
        CGPoint(x: 710, y: 238),   // Rushmere
        CGPoint(x: 635, y: 139)    // Cragmouth Gate (destination)
    ]

    /// The default marker position for the debug entry — between the reached start
    /// and the `.next` pin, matching the Windrise pattern.
    static let defaultMarkerMiles = 1.0

    static func make() -> MapAuthoring {
        var regions: [MapRegion] = []

        // Western faceted range (foothills w/ snow caps) — runs off-map
        // top/bottom/left, the KAN-23 "small map, big scenery" ruling.
        regions.append(.range(.init(id: "range.westwall", center: CGPoint(x: 90, y: 340),
                                    axisAngle: 1.53, halfLength: 750, halfWidth: 105,
                                    snowCaps: 2, scatter: ScatterParams(density: 0.0018, feather: 0.5))))

        // Canyon lake (the reservoir; the destination sits on its south shore).
        regions.append(.lake(.init(id: "lake.craghollow", ring: [
            CGPoint(x: 462, y: 82), CGPoint(x: 500, y: 58), CGPoint(x: 558, y: 50),
            CGPoint(x: 620, y: 60), CGPoint(x: 656, y: 86), CGPoint(x: 628, y: 118),
            CGPoint(x: 572, y: 126), CGPoint(x: 505, y: 120), CGPoint(x: 470, y: 100)
        ])))

        // River "Dry Creek" — rises in the NW range area, meanders SE, exits the
        // south edge off-map. Source on land (allowed, KAN-23); it fords the trek
        // near the start (allowed — only lakes/sea block paths).
        regions.append(.river(.init(id: "river.drycreek",
            hint: [CGPoint(x: 150, y: 163), CGPoint(x: 200, y: 300), CGPoint(x: 250, y: 430),
                   CGPoint(x: 300, y: 540), CGPoint(x: 370, y: 630), CGPoint(x: 430, y: 690)],
            meanderAmplitude: 9, sourceWidth: 4, mouthWidth: 11)))

        // Forests (city parks).
        regions.append(.forest(.init(id: "forest.central", center: CGPoint(x: 560, y: 469), rx: 60, ry: 40)))
        regions.append(.forest(.init(id: "forest.east", center: CGPoint(x: 820, y: 517), rx: 58, ry: 38)))
        regions.append(.forest(.init(id: "forest.west", center: CGPoint(x: 360, y: 592), rx: 48, ry: 32)))

        // Settlements (sites; display names live on the waypoints).
        let sites: [(String, CGFloat, CGFloat, Int)] = [
            ("settle.start", 300, 517, 4),
            ("settle.mid", 690, 326, 3),
            ("settle.dest", 600, 163, 4)
        ]
        for s in sites {
            regions.append(.settlement(.init(id: s.0, site: CGPoint(x: s.1, y: s.2),
                                             name: "", homeCount: s.3)))
        }

        regions.append(.trekPath(.init(id: "trek.firstjourney", points: trek)))

        // Waypoints (approved; positions ARE the trek control points, so each lies on
        // the path trivially). Non-destination waypoints take the theme accent
        // (First Journey's theme is secondary); the destination takes `reward`.
        // Fresh-journey states: Fernhollow reached at mile 0, Mallow Bend next, the
        // rest upcoming.
        let waypointSpec: [(String, String, CGPoint, Double, String, MapWaypoint.State, Bool)] = [
            ("wp.fernhollow",    "Fernhollow",     CGPoint(x: 300, y: 544), 0.0,   DesignToken.accentSecondary, .reached,  false),
            ("wp.mallowbend",    "Mallow Bend",    CGPoint(x: 460, y: 585), 1.94,  DesignToken.accentSecondary, .next,     false),
            ("wp.greenwaycross", "Greenway Cross", CGPoint(x: 630, y: 496), 4.19,  DesignToken.accentSecondary, .upcoming, false),
            ("wp.fenwickrise",   "Fenwick Rise",   CGPoint(x: 800, y: 367), 6.70,  DesignToken.accentSecondary, .upcoming, false),
            ("wp.rushmere",      "Rushmere",       CGPoint(x: 710, y: 238), 8.54,  DesignToken.accentSecondary, .upcoming, false),
            ("wp.cragmouthgate", "Cragmouth Gate", CGPoint(x: 635, y: 139), 10.0,  DesignToken.reward,          .upcoming, true)
        ]
        let waypoints = waypointSpec.map { spec in
            MapWaypoint(id: spec.0, position: spec.2, name: spec.1,
                        milesFromStart: spec.3, accentToken: spec.4,
                        state: spec.5, isDestination: spec.6)
        }

        return MapAuthoring(
            name: "First Journey",
            bounds: CGRect(x: 0, y: 0, width: 1000, height: 680),
            seed: 0xF1_2A07,
            journeyMiles: journeyMiles,
            regions: regions,
            waypoints: waypoints
        )
    }
}
