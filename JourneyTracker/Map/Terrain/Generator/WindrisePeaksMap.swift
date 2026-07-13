//
//  WindrisePeaksMap.swift
//  JourneyTracker
//
//  The first hand-drawn-map journey (KAN-23 pilot): "Road to The Windrise Peaks",
//  digitized from Justin's own drawing and re-expressed as authored REGION records
//  + a seed, following the SampleJourneyMap / EmberSpireScaleFixture conventions.
//
//  Coordinates are SOURCE-IMAGE PIXELS (1190×896, origin top-left) used directly as
//  map units; the image's mile bar gives ~6.85 px per mile. The trek was authored
//  WEST → EAST (travel direction per Justin). Region ids below are INTERNAL only —
//  they key each region's RNG substream and never surface; the DISPLAY names are the
//  Justin-approved waypoint names in `make()`.
//
//  KAN-23 "the drawing trumps the rules": the digitization conflicts the original
//  bounds table caught were resolved by loosening the rules to fit the real
//  geography (looser range/hill length, ≤40-mi inland settlements, land-anywhere
//  river sources, off-map river mouths, raised lake cap). This authoring passes
//  every current validator (MapValidator.validate → 0).
//

import CoreGraphics

enum WindrisePeaksMap {

    /// The journey's real total distance (App Concept doc catalog). Anchors
    /// miles-per-map-unit against the trek path's smoothed arc length.
    static let journeyMiles = 302.4

    /// Image scale from the drawing's mile bar (~6.85 px per mile). Informational —
    /// the authoritative scale is derived from trek arc length ↔ `journeyMiles`.
    static let pxPerMile = 6.85

    /// The dotted route traced from the image, authored WEST → EAST.
    static let trek: [CGPoint] = [
        CGPoint(x: 88, y: 302),
        CGPoint(x: 120, y: 330),
        CGPoint(x: 168, y: 356),
        CGPoint(x: 196, y: 392),
        CGPoint(x: 240, y: 430),
        CGPoint(x: 302, y: 455),
        CGPoint(x: 392, y: 470),
        CGPoint(x: 468, y: 470),
        CGPoint(x: 528, y: 488),
        CGPoint(x: 526, y: 520),
        CGPoint(x: 480, y: 570),
        CGPoint(x: 452, y: 636),
        CGPoint(x: 482, y: 702),
        CGPoint(x: 546, y: 747),
        CGPoint(x: 616, y: 736),
        CGPoint(x: 686, y: 706),
        CGPoint(x: 758, y: 678),
        CGPoint(x: 792, y: 702),
        CGPoint(x: 862, y: 743),
        CGPoint(x: 952, y: 732),
        CGPoint(x: 1006, y: 693),
        CGPoint(x: 988, y: 625),
        CGPoint(x: 1032, y: 565),
        CGPoint(x: 1090, y: 520),
        CGPoint(x: 1098, y: 470),
        CGPoint(x: 1075, y: 412),
        CGPoint(x: 1082, y: 332),
        CGPoint(x: 1122, y: 272),
        CGPoint(x: 1140, y: 205),
        CGPoint(x: 1122, y: 120),
        CGPoint(x: 1085, y: 42)
    ]

    /// The default marker position for the debug entry — before Millhollow (.next
    /// at 14.2) so the marker sits ahead of its "next" pin like the sibling
    /// fixtures, and chapter framing shows the opening Wavecrest → Millhollow leg.
    static let defaultMarkerMiles = 10.0

    static func make() -> MapAuthoring {
        var regions: [MapRegion] = []

        // The sea wraps the map's top AND left (an L). Single coastline traced
        // SW → N → NE; sea ring closes through the NW corner. NOTE: the single
        // `seaward` vector is a known limitation for wrapped coasts — depth
        // bands will offset diagonally; flagged for a per-vertex-normal fix.
        regions.append(.coast(.init(
            id: "coast.westnorth",
            coastline: [
                CGPoint(x: 255, y: 940), CGPoint(x: 225, y: 860), CGPoint(x: 250, y: 835),
                CGPoint(x: 215, y: 800), CGPoint(x: 280, y: 770), CGPoint(x: 250, y: 715),
                CGPoint(x: 215, y: 660), CGPoint(x: 185, y: 600), CGPoint(x: 150, y: 555),
                CGPoint(x: 105, y: 520), CGPoint(x: 140, y: 480), CGPoint(x: 110, y: 435),
                CGPoint(x: 95, y: 380), CGPoint(x: 35, y: 330), CGPoint(x: 75, y: 290),
                CGPoint(x: 60, y: 255), CGPoint(x: 110, y: 225), CGPoint(x: 150, y: 200),
                CGPoint(x: 215, y: 205), CGPoint(x: 300, y: 170), CGPoint(x: 355, y: 160),
                CGPoint(x: 430, y: 185), CGPoint(x: 500, y: 160), CGPoint(x: 560, y: 145),
                CGPoint(x: 640, y: 120), CGPoint(x: 700, y: 105), CGPoint(x: 740, y: 90),
                CGPoint(x: 760, y: 70), CGPoint(x: 795, y: 45), CGPoint(x: 810, y: -20)
            ],
            seaward: CGVector(dx: -0.6, dy: -0.55),
            seaCorners: [CGPoint(x: -60, y: -60), CGPoint(x: -60, y: 955)]
        )))

        // Hill country, rendered as low ranges (the `range` kind spans hill-chains
        // through great massifs — KAN-23 loosened the length minimum to 15 mi to fit
        // real hand-drawn hill country; a dedicated hills glyph stays a future
        // Design System option).
        regions.append(.range(.init(id: "hills.grinne", center: CGPoint(x: 745, y: 505),
                                    axisAngle: 0.15, halfLength: 130, halfWidth: 30,
                                    snowCaps: 0, scatter: ScatterParams(density: 0.0016, feather: 0.5))))
        regions.append(.range(.init(id: "hills.south", center: CGPoint(x: 480, y: 862),
                                    axisAngle: 0.05, halfLength: 160, halfWidth: 28,
                                    snowCaps: 0, scatter: ScatterParams(density: 0.0016, feather: 0.5))))
        regions.append(.range(.init(id: "hills.calva", center: CGPoint(x: 375, y: 745),
                                    axisAngle: -0.3, halfLength: 90, halfWidth: 25,
                                    snowCaps: 0, scatter: ScatterParams(density: 0.0016, feather: 0.5))))
        regions.append(.range(.init(id: "hills.northeast", center: CGPoint(x: 1010, y: 95),
                                    axisAngle: 0.25, halfLength: 130, halfWidth: 30,
                                    snowCaps: 0, scatter: ScatterParams(density: 0.0016, feather: 0.5))))
        regions.append(.range(.init(id: "hills.east", center: CGPoint(x: 1120, y: 180),
                                    axisAngle: 1.0, halfLength: 90, halfWidth: 25,
                                    snowCaps: 0, scatter: ScatterParams(density: 0.0016, feather: 0.5))))
        regions.append(.range(.init(id: "hills.central", center: CGPoint(x: 700, y: 335),
                                    axisAngle: 0.1, halfLength: 110, halfWidth: 26,
                                    snowCaps: 0, scatter: ScatterParams(density: 0.0016, feather: 0.5))))
        regions.append(.range(.init(id: "hills.westknot", center: CGPoint(x: 255, y: 300),
                                    axisAngle: -0.2, halfLength: 70, halfWidth: 22,
                                    snowCaps: 0, scatter: ScatterParams(density: 0.0016, feather: 0.5))))

        // Forest masses.
        regions.append(.forest(.init(id: "forest.northcape", center: CGPoint(x: 835, y: 55), rx: 55, ry: 35)))
        regions.append(.forest(.init(id: "forest.northwood", center: CGPoint(x: 725, y: 125), rx: 60, ry: 40)))
        regions.append(.forest(.init(id: "forest.uplandwood", center: CGPoint(x: 610, y: 255), rx: 55, ry: 30)))
        regions.append(.forest(.init(id: "forest.midwood", center: CGPoint(x: 665, y: 440), rx: 75, ry: 40)))
        regions.append(.forest(.init(id: "forest.westthicket", center: CGPoint(x: 205, y: 430), rx: 55, ry: 45)))
        regions.append(.forest(.init(id: "forest.southwood.w", center: CGPoint(x: 395, y: 665), rx: 55, ry: 30)))
        regions.append(.forest(.init(id: "forest.southwood.e", center: CGPoint(x: 655, y: 712), rx: 115, ry: 35)))
        regions.append(.forest(.init(id: "forest.northeastwood", center: CGPoint(x: 900, y: 195), rx: 45, ry: 28)))
        regions.append(.forest(.init(id: "forest.southeastwood", center: CGPoint(x: 1065, y: 735), rx: 45, ry: 30)))
        regions.append(.forest(.init(id: "forest.heartcopse", center: CGPoint(x: 535, y: 395), rx: 40, ry: 25)))

        // Lakes.
        regions.append(.lake(.init(id: "lake.west", ring: [
            CGPoint(x: 288, y: 598), CGPoint(x: 322, y: 592), CGPoint(x: 342, y: 610),
            CGPoint(x: 330, y: 628), CGPoint(x: 298, y: 632), CGPoint(x: 280, y: 616)
        ])))
        regions.append(.lake(.init(id: "lake.southsmall", ring: [
            CGPoint(x: 380, y: 815), CGPoint(x: 408, y: 812), CGPoint(x: 420, y: 828),
            CGPoint(x: 405, y: 842), CGPoint(x: 382, y: 838)
        ])))

        // Rivers (hint polylines; mouths at the sea/lakes).
        regions.append(.river(.init(id: "river.northrun",
            hint: [CGPoint(x: 540, y: 400), CGPoint(x: 515, y: 330),
                   CGPoint(x: 500, y: 260), CGPoint(x: 490, y: 168)],
            meanderAmplitude: 10, sourceWidth: 4, mouthWidth: 10)))
        regions.append(.river(.init(id: "river.westrun",
            hint: [CGPoint(x: 430, y: 430), CGPoint(x: 350, y: 415),
                   CGPoint(x: 280, y: 395), CGPoint(x: 175, y: 380), CGPoint(x: 98, y: 392)],
            meanderAmplitude: 10, sourceWidth: 4, mouthWidth: 11)))
        regions.append(.river(.init(id: "river.inletrun",
            hint: [CGPoint(x: 330, y: 560), CGPoint(x: 270, y: 555),
                   CGPoint(x: 210, y: 540), CGPoint(x: 122, y: 512)],
            meanderAmplitude: 9, sourceWidth: 4, mouthWidth: 10)))
        regions.append(.river(.init(id: "river.longsouth",
            hint: [CGPoint(x: 760, y: 540), CGPoint(x: 660, y: 590), CGPoint(x: 590, y: 610),
                   CGPoint(x: 560, y: 660), CGPoint(x: 565, y: 730), CGPoint(x: 540, y: 800),
                   CGPoint(x: 450, y: 845), CGPoint(x: 380, y: 845), CGPoint(x: 228, y: 866)],
            meanderAmplitude: 11, sourceWidth: 4, mouthWidth: 12)))
        regions.append(.river(.init(id: "river.bayrun",
            hint: [CGPoint(x: 720, y: 160), CGPoint(x: 760, y: 120), CGPoint(x: 785, y: 60)],
            meanderAmplitude: 7, sourceWidth: 3, mouthWidth: 8)))
        regions.append(.river(.init(id: "river.eastrun",
            hint: [CGPoint(x: 820, y: 430), CGPoint(x: 900, y: 470), CGPoint(x: 960, y: 520),
                   CGPoint(x: 1060, y: 565), CGPoint(x: 1215, y: 600)],
            meanderAmplitude: 10, sourceWidth: 4, mouthWidth: 10)))

        // Desert stretch between Farrow's Rest and Stonewash Ford (Justin's ruling).
        regions.append(.groundCover(.init(id: "dunes.eaststretch", kind: .dunes, ring: [
            CGPoint(x: 880, y: 690), CGPoint(x: 960, y: 655), CGPoint(x: 1035, y: 610),
            CGPoint(x: 1062, y: 648), CGPoint(x: 1012, y: 718), CGPoint(x: 932, y: 762),
            CGPoint(x: 872, y: 742)
        ])))

        // One central plains wash.
        regions.append(.groundCover(.init(id: "plains.heart", kind: .plains, ring: [
            CGPoint(x: 520, y: 430), CGPoint(x: 700, y: 400), CGPoint(x: 830, y: 470),
            CGPoint(x: 800, y: 590), CGPoint(x: 650, y: 640), CGPoint(x: 520, y: 560)
        ])))

        // Settlements (sites from the image; homes that jitter into water are
        // resampled dry by the generator). Display names live on the waypoints.
        let sites: [(String, CGFloat, CGFloat, Int)] = [
            ("settle.01", 180, 212, 4), ("settle.02", 532, 158, 3), ("settle.03", 742, 72, 4),
            ("settle.04", 170, 352, 4), ("settle.05", 90, 300, 3), ("settle.06", 112, 505, 3),
            ("settle.07", 300, 600, 4), ("settle.08", 528, 487, 4), ("settle.09", 757, 678, 3),
            ("settle.10", 860, 742, 4), ("settle.11", 1092, 520, 4), ("settle.12", 180, 850, 3),
            ("settle.13", 400, 828, 3), ("settle.14", 612, 845, 3), ("settle.15", 952, 282, 4)
        ]
        for s in sites {
            regions.append(.settlement(.init(id: s.0, site: CGPoint(x: s.1, y: s.2),
                                             name: "", homeCount: s.3)))
        }

        regions.append(.trekPath(.init(id: "trek.windrise", points: trek)))

        // Waypoints (Justin-approved; positions are smoothed-trek samples, validated
        // anchor-consistent). Towns take `accentPrimary`; the three fords
        // (Sable / Oxbow Crossing / Stonewash) take `accentSecondary`; the
        // destination takes `reward`. Fresh-journey states: Wavecrest reached at mile
        // 0, Millhollow next, the rest upcoming.
        let waypointSpec: [(String, String, CGPoint, Double, String, MapWaypoint.State, Bool)] = [
            ("wp.wavecrest",     "Wavecrest",          CGPoint(x: 88,   y: 302), 0.0,   DesignToken.accentPrimary,   .reached,  false),
            ("wp.millhollow",    "Millhollow",         CGPoint(x: 168,  y: 356), 14.2,  DesignToken.accentPrimary,   .next,     false),
            ("wp.sableford",     "Sable Ford",         CGPoint(x: 196,  y: 392), 20.9,  DesignToken.accentSecondary, .upcoming, false),
            ("wp.hallowmere",    "Hallowmere",         CGPoint(x: 528,  y: 488), 72.9,  DesignToken.accentPrimary,   .upcoming, false),
            ("wp.oxbowcrossing", "Oxbow Crossing",     CGPoint(x: 557,  y: 749), 122.6, DesignToken.accentSecondary, .upcoming, false),
            ("wp.thistlewood",   "Thistlewood",        CGPoint(x: 758,  y: 678), 153.9, DesignToken.accentPrimary,   .upcoming, false),
            ("wp.farrowsrest",   "Farrow's Rest",      CGPoint(x: 862,  y: 743), 172.1, DesignToken.accentPrimary,   .upcoming, false),
            ("wp.stonewashford", "Stonewash Ford",     CGPoint(x: 1041, y: 557), 218.8, DesignToken.accentSecondary, .upcoming, false),
            ("wp.rivergate",     "Rivergate",          CGPoint(x: 1090, y: 520), 227.7, DesignToken.accentPrimary,   .upcoming, false),
            ("wp.windrisepeaks", "The Windrise Peaks", CGPoint(x: 1085, y: 42),  302.4, DesignToken.reward,          .upcoming, true)
        ]
        let waypoints = waypointSpec.map { spec in
            MapWaypoint(id: spec.0, position: spec.2, name: spec.1,
                        milesFromStart: spec.3, accentToken: spec.4,
                        state: spec.5, isDestination: spec.6)
        }

        return MapAuthoring(
            name: "Road to The Windrise Peaks",
            bounds: CGRect(x: 0, y: 0, width: 1190, height: 896),
            seed: 0xB1_07AA,
            journeyMiles: journeyMiles,
            regions: regions,
            waypoints: waypoints
        )
    }
}
