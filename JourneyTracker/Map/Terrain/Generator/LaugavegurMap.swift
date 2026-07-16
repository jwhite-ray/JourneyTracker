//
//  LaugavegurMap.swift
//  JourneyTracker
//
//  KAN-43: the first authored REAL-WORLD faceted map — Iceland's Laugavegur,
//  Landmannalaugar → Þórsmörk (34.18 mi / 55 km), authored through the KAN-23
//  pipeline (REGION records + a deterministic seed) from the real trail's
//  geography, stylized in the §07 terrain vocabulary. Real place names are
//  authentic geography, not IP (App Concept doc scope clarification, KAN-43/44).
//
//  Coordinates are map units in a 900×1240 portrait space (origin top-left,
//  north up). Composition follows the real trail map (design-gate round 2,
//  Justin's reference): Landmannalaugar in the top-right under the Torfajökull
//  rhyolite country, the trek trending SOUTH-WEST, and the Mýrdalsjökull ice
//  cap as the huge pale mass filling the lower right — authored with the
//  water-blob (lake) vocabulary, the §07 kind that reads as that big glacial
//  expanse; the trail hugs its western edge from Emstrur down to Þórsmörk.
//  Tindfjallajökull sits mid-left, Eyjafjallajökull off the bottom-left,
//  Álftavatn lake in its green valley mid-route with the Bláfjallakvísl wade
//  flowing in, the Mælifellssandur black sands (dunes) east of the
//  Hvanngil–Emstrur leg, and the glacial Markarfljót running the west side.
//  Huts render as settlements. Waypoint positions are smoothed-trek samples
//  at the canonical stage mileages (validated anchor-consistent).
//

import CoreGraphics

enum LaugavegurMap {

    /// Canonical total distance (App Concept doc catalog): 55 km at
    /// 1 km = 0.621371 mi.
    static let journeyMiles = 34.18

    /// The trek, authored NE → SW like the reference map. Waypoint positions
    /// are exact smoothed-arc samples (the anchor tolerance here is ±1.7 mi).
    static let trek: [CGPoint] = [
        CGPoint(x: 640, y: 110),   // Landmannalaugar (start, top-right)
        CGPoint(x: 560, y: 200),   // SW through the Laugahraun obsidian field
        CGPoint(x: 510, y: 330),   // Hrafntinnusker plateau
        CGPoint(x: 480, y: 450),   // Jökultungur descent
        CGPoint(x: 470, y: 555),   // Álftavatn shore
        CGPoint(x: 475, y: 635),   // Hvanngil glen
        CGPoint(x: 430, y: 745),   // SW across the black sands
        CGPoint(x: 390, y: 855),   // Emstrur (Botnar), west of the ice cap
        CGPoint(x: 370, y: 965),   // down the Markarfljót canyon country
        CGPoint(x: 330, y: 1085)   // Þórsmörk (destination)
    ]

    static func make() -> MapAuthoring {
        var regions: [MapRegion] = []

        // Torfajökull rhyolite country NE/E of the first leg (top-right),
        // running off the top/right edges.
        regions.append(.range(.init(id: "range.torfa", center: CGPoint(x: 760, y: 260),
                                    axisAngle: 0.5, halfLength: 260, halfWidth: 100,
                                    snowCaps: 4, scatter: ScatterParams(density: 0.0017, feather: 0.5))))
        // The Laugahraun-side heights NW of the start (top-left country).
        regions.append(.range(.init(id: "range.laugahraun", center: CGPoint(x: 200, y: 200),
                                    axisAngle: -0.2, halfLength: 250, halfWidth: 95,
                                    snowCaps: 2, scatter: ScatterParams(density: 0.0016, feather: 0.5))))
        // Kaldaklofsfjöll west of the high Hrafntinnusker section.
        regions.append(.range(.init(id: "range.kaldaklof", center: CGPoint(x: 230, y: 470),
                                    axisAngle: 1.25, halfLength: 240, halfWidth: 90,
                                    snowCaps: 4, scatter: ScatterParams(density: 0.0016, feather: 0.5))))
        // The Öldufellsjökull-side ridges NE of the ice cap, off the right edge.
        regions.append(.range(.init(id: "range.oldufell", center: CGPoint(x: 860, y: 620),
                                    axisAngle: 1.3, halfLength: 230, halfWidth: 80,
                                    snowCaps: 3, scatter: ScatterParams(density: 0.0016, feather: 0.5))))
        // Tindfjallajökull mid-left, west of the Emstrur leg.
        regions.append(.range(.init(id: "range.tindfjalla", center: CGPoint(x: 120, y: 800),
                                    axisAngle: 0.3, halfLength: 240, halfWidth: 95,
                                    snowCaps: 5, scatter: ScatterParams(density: 0.0016, feather: 0.5))))
        // Eyjafjallajökull south-west beyond Þórsmörk, off-map bottom-left.
        regions.append(.range(.init(id: "range.eyjafjalla", center: CGPoint(x: 240, y: 1210),
                                    axisAngle: 0.1, halfLength: 280, halfWidth: 115,
                                    snowCaps: 7, scatter: ScatterParams(density: 0.0017, feather: 0.5))))

        // Mýrdalsjökull — the great ice cap dominating the lower right of the
        // real map. Authored as the §07 water blob (the vocabulary's big pale
        // mass); the trail hugs its western edge. Kept ≤60 sq mi authored.
        regions.append(.lake(.init(id: "ice.myrdals", ring: [
            CGPoint(x: 585, y: 782), CGPoint(x: 700, y: 754), CGPoint(x: 795, y: 782),
            CGPoint(x: 822, y: 880), CGPoint(x: 782, y: 985), CGPoint(x: 690, y: 1025),
            CGPoint(x: 604, y: 988), CGPoint(x: 568, y: 880)
        ])))

        // Álftavatn — the lake the third stage descends to; the trail passes
        // its east shore.
        regions.append(.lake(.init(id: "lake.alftavatn", ring: [
            CGPoint(x: 370, y: 525), CGPoint(x: 400, y: 512), CGPoint(x: 432, y: 520),
            CGPoint(x: 445, y: 545), CGPoint(x: 432, y: 572), CGPoint(x: 398, y: 580),
            CGPoint(x: 372, y: 562)
        ])))

        // Markarfljót — the big glacial river running S along the west side,
        // draining off-map bottom (its canyon flanks the Emstrur leg).
        regions.append(.river(.init(id: "river.markarfljot",
            hint: [CGPoint(x: 260, y: 560), CGPoint(x: 230, y: 690), CGPoint(x: 215, y: 820),
                   CGPoint(x: 205, y: 950), CGPoint(x: 215, y: 1080), CGPoint(x: 245, y: 1180),
                   CGPoint(x: 275, y: 1250)],
            meanderAmplitude: 10, sourceWidth: 5, mouthWidth: 12)))
        // Bláfjallakvísl — the wade before Hvanngil, flowing W into Álftavatn.
        regions.append(.river(.init(id: "river.blafjalla",
            hint: [CGPoint(x: 600, y: 600), CGPoint(x: 530, y: 585), CGPoint(x: 470, y: 570),
                   CGPoint(x: 420, y: 552)],
            meanderAmplitude: 6, sourceWidth: 3, mouthWidth: 8)))

        // Mælifellssandur — the black-sand desert crossed between Hvanngil and
        // Emstrur, east of the trail and north of the ice cap.
        regions.append(.groundCover(.init(id: "dunes.maelifell", kind: .dunes, ring: [
            CGPoint(x: 480, y: 660), CGPoint(x: 600, y: 640), CGPoint(x: 680, y: 680),
            CGPoint(x: 660, y: 740), CGPoint(x: 560, y: 740), CGPoint(x: 480, y: 715)
        ])))
        // The green Álftavatn valley floor.
        regions.append(.groundCover(.init(id: "plains.alftavatn", kind: .plains, ring: [
            CGPoint(x: 360, y: 480), CGPoint(x: 500, y: 470), CGPoint(x: 545, y: 555),
            CGPoint(x: 500, y: 625), CGPoint(x: 390, y: 635), CGPoint(x: 330, y: 555)
        ])))

        // Þórsmörk's birch woods — the forested valley the trail finishes in,
        // tucked between the glaciers.
        regions.append(.forest(.init(id: "forest.thorsmork", center: CGPoint(x: 430, y: 1105), rx: 85, ry: 42)))
        regions.append(.forest(.init(id: "forest.hamraskogar", center: CGPoint(x: 500, y: 1030), rx: 45, ry: 26)))

        // Huts as settlements (sites just off-trail beside their snapped
        // waypoints; display names live on the waypoints).
        let sites: [(String, CGFloat, CGFloat, Int)] = [
            ("settle.landmannalaugar", 622, 98, 4),
            ("settle.hrafntinnusker", 506, 291, 3),
            ("settle.alftavatn", 458, 514, 3),
            ("settle.hvanngil", 490, 592, 3),
            ("settle.emstrur", 395, 778, 3),
            ("settle.thorsmork", 348, 1098, 4)
        ]
        for s in sites {
            regions.append(.settlement(.init(id: s.0, site: CGPoint(x: s.1, y: s.2),
                                             name: "", homeCount: s.3)))
        }

        regions.append(.trekPath(.init(id: "trek.laugavegur", points: trek)))

        // Waypoints at the canonical stage mileages (Ferðafélag Íslands hut
        // spacing, km → mi). Positions are smoothed-trek samples. Fresh-journey
        // states; the destination takes `reward`.
        let waypointSpec: [(String, String, CGPoint, Double, String, MapWaypoint.State, Bool)] = [
            ("wp.landmannalaugar", "Landmannalaugar",  CGPoint(x: 640, y: 110),  0.0,   DesignToken.accentPrimary, .reached,  false),
            ("wp.hrafntinnusker",  "Hrafntinnusker",   CGPoint(x: 520, y: 299),  7.46,  DesignToken.accentPrimary, .next,     false),
            ("wp.alftavatn",       "Álftavatn",        CGPoint(x: 472, y: 521),  14.91, DesignToken.accentPrimary, .upcoming, false),
            ("wp.hvanngil",        "Hvanngil",         CGPoint(x: 475, y: 597),  17.40, DesignToken.accentPrimary, .upcoming, false),
            ("wp.emstrur",         "Emstrur (Botnar)", CGPoint(x: 411, y: 793),  24.23, DesignToken.accentPrimary, .upcoming, false),
            ("wp.thorsmork",       "Þórsmörk",         CGPoint(x: 330, y: 1085), 34.18, DesignToken.reward,        .upcoming, true)
        ]
        let waypoints = waypointSpec.map { spec in
            MapWaypoint(id: spec.0, position: spec.2, name: spec.1,
                        milesFromStart: spec.3, accentToken: spec.4,
                        state: spec.5, isDestination: spec.6)
        }

        return MapAuthoring(
            name: "Laugavegur Trail",
            bounds: CGRect(x: 0, y: 0, width: 900, height: 1240),
            seed: 0x1CE_A9D,
            journeyMiles: journeyMiles,
            regions: regions,
            waypoints: waypoints
        )
    }
}
