//
//  IncaTrailMap.swift
//  JourneyTracker
//
//  KAN-44: the second authored REAL-WORLD faceted map — Peru's classic Inca
//  Trail, Km 82 (Piscacucho) → Machu Picchu (26.72 mi / 43 km), authored
//  through the KAN-23 pipeline (REGION records + a deterministic seed) from
//  the real trail's geography, stylized in the §07 terrain vocabulary. Real
//  place names (including Quechua) are authentic geography, not IP (App
//  Concept doc scope clarification, KAN-43/44).
//
//  Coordinates are map units in a 1200×800 landscape space (origin top-left,
//  north up). The trek runs SE → NW like the real trail: west along the
//  Urubamba from Km 82, south up the Cusichaca valley to Wayllabamba, then
//  over the three passes — Warmiwañusca (Dead Woman's Pass), Runkurakay,
//  Phuyupatamarca — through cloud forest down to Wiñay Wayna, and along the
//  canyon rim through Inti Punku (the Sun Gate) to Machu Picchu. Real
//  flanking features, stylized: the Urubamba river sweeping the north edge
//  and bending south around the citadel, the snow-capped Verónica (Wakay
//  Willka) massif north across the valley, the Salkantay massif far SW, high
//  puna grassland around Dead Woman's Pass, and cloud-forest masses on the
//  western descent. Ruin sites render as settlements. Waypoint positions are
//  smoothed-trek samples at the canonical mileages (validated
//  anchor-consistent).
//

import CoreGraphics

enum IncaTrailMap {

    /// Canonical total distance (App Concept doc catalog): 43 km at
    /// 1 km = 0.621371 mi.
    static let journeyMiles = 26.72

    /// The trek, authored SE → NW. Waypoint positions are exact smoothed-arc
    /// samples (the anchor tolerance here is ±1.3 mi).
    static let trek: [CGPoint] = [
        CGPoint(x: 1085, y: 300),  // Km 82 / Piscacucho (start)
        CGPoint(x: 1000, y: 315),  // along the Urubamba past Patallacta
        CGPoint(x: 950, y: 395),   // turning S up the Cusichaca valley
        CGPoint(x: 965, y: 505),   // Wayllabamba
        CGPoint(x: 870, y: 470),   // the Llulluchapampa climb
        CGPoint(x: 785, y: 420),   // Warmiwañusca (Dead Woman's Pass)
        CGPoint(x: 715, y: 375),   // down to Pacaymayo
        CGPoint(x: 655, y: 425),   // over the Runkurakay pass
        CGPoint(x: 595, y: 375),   // past Sayacmarca's spur
        CGPoint(x: 560, y: 395),   // Chaquicocha
        CGPoint(x: 480, y: 360),   // Phuyupatamarca
        CGPoint(x: 432, y: 295),   // the stair descent to Wiñay Wayna
        CGPoint(x: 368, y: 338),   // the canyon-rim contour to Inti Punku
        CGPoint(x: 300, y: 368)    // Machu Picchu (destination)
    ]

    static func make() -> MapAuthoring {
        var regions: [MapRegion] = []

        // Verónica (Wakay Willka) massif north across the Urubamba; off-map top.
        regions.append(.range(.init(id: "range.veronica", center: CGPoint(x: 760, y: 55),
                                    axisAngle: 0.08, halfLength: 330, halfWidth: 105,
                                    snowCaps: 8, scatter: ScatterParams(density: 0.0018, feather: 0.5))))
        // Salkantay massif far SW; off-map bottom-left.
        regions.append(.range(.init(id: "range.salkantay", center: CGPoint(x: 170, y: 760),
                                    axisAngle: -0.3, halfLength: 330, halfWidth: 120,
                                    snowCaps: 7, scatter: ScatterParams(density: 0.0017, feather: 0.5))))
        // The high puna ridge the three passes cross, south of the trail.
        regions.append(.range(.init(id: "range.puna", center: CGPoint(x: 660, y: 585),
                                    axisAngle: -0.1, halfLength: 330, halfWidth: 88,
                                    snowCaps: 2, scatter: ScatterParams(density: 0.0016, feather: 0.5))))
        // SE valley-flank hills below the Cusichaca turn.
        regions.append(.range(.init(id: "range.cusichaca", center: CGPoint(x: 1050, y: 640),
                                    axisAngle: -0.4, halfLength: 325, halfWidth: 85,
                                    snowCaps: 1, scatter: ScatterParams(density: 0.0016, feather: 0.5))))

        // The Urubamba — in from the E, west along the north edge, bending S
        // around the citadel's spur, out the west edge.
        regions.append(.river(.init(id: "river.urubamba",
            hint: [CGPoint(x: 1215, y: 175), CGPoint(x: 1080, y: 190), CGPoint(x: 950, y: 165),
                   CGPoint(x: 820, y: 195), CGPoint(x: 690, y: 170), CGPoint(x: 560, y: 195),
                   CGPoint(x: 450, y: 225), CGPoint(x: 350, y: 255), CGPoint(x: 250, y: 300),
                   CGPoint(x: 150, y: 330), CGPoint(x: 40, y: 335), CGPoint(x: -20, y: 340)],
            meanderAmplitude: 10, sourceWidth: 7, mouthWidth: 11)))
        // The Pacaymayo stream, dropping into the little Yanacocha tarn.
        regions.append(.river(.init(id: "river.pacaymayo",
            hint: [CGPoint(x: 600, y: 255), CGPoint(x: 630, y: 295), CGPoint(x: 655, y: 320),
                   CGPoint(x: 668, y: 345)],
            meanderAmplitude: 6, sourceWidth: 3, mouthWidth: 6)))

        // The Yanacocha tarn below the Runkurakay pass.
        regions.append(.lake(.init(id: "lake.yanacocha", ring: [
            CGPoint(x: 655, y: 345), CGPoint(x: 672, y: 337), CGPoint(x: 688, y: 345),
            CGPoint(x: 690, y: 361), CGPoint(x: 676, y: 371), CGPoint(x: 658, y: 367)
        ])))

        // High puna grassland around Dead Woman's Pass.
        regions.append(.groundCover(.init(id: "plains.puna", kind: .plains, ring: [
            CGPoint(x: 700, y: 330), CGPoint(x: 830, y: 355), CGPoint(x: 885, y: 430),
            CGPoint(x: 805, y: 495), CGPoint(x: 695, y: 465), CGPoint(x: 650, y: 395)
        ])))

        // Cloud forest — the western descent and the valley woods near the start.
        regions.append(.forest(.init(id: "forest.cloud.west", center: CGPoint(x: 450, y: 290), rx: 70, ry: 38)))
        regions.append(.forest(.init(id: "forest.cloud.mid", center: CGPoint(x: 585, y: 320), rx: 55, ry: 30)))
        regions.append(.forest(.init(id: "forest.valley.start", center: CGPoint(x: 940, y: 250), rx: 55, ry: 32)))
        regions.append(.forest(.init(id: "forest.machupicchu", center: CGPoint(x: 270, y: 300), rx: 42, ry: 26)))

        // Ruin sites and villages as settlements (stone clusters; display names
        // live on the waypoints).
        let sites: [(String, CGFloat, CGFloat, Int)] = [
            ("settle.km82", 1090, 288, 3),
            ("settle.wayllabamba", 975, 520, 4),
            ("settle.sayacmarca", 600, 358, 3),
            ("settle.winaywayna", 425, 278, 4),
            ("settle.machupicchu", 293, 352, 5)
        ]
        for s in sites {
            regions.append(.settlement(.init(id: s.0, site: CGPoint(x: s.1, y: s.2),
                                             name: "", homeCount: s.3)))
        }

        regions.append(.trekPath(.init(id: "trek.incatrail", points: trek)))

        // Waypoints at the canonical classic-route mileages (km → mi).
        // Positions are smoothed-trek samples. Fresh-journey states; the great
        // pass takes `accentSecondary` (the Windrise ford precedent for hard
        // crossings); the destination takes `reward`.
        let waypointSpec: [(String, String, CGPoint, Double, String, MapWaypoint.State, Bool)] = [
            ("wp.km82",          "Km 82 (Piscacucho)",              CGPoint(x: 1085, y: 300), 0.0,   DesignToken.accentPrimary,   .reached,  false),
            ("wp.wayllabamba",   "Wayllabamba",                     CGPoint(x: 952, y: 507),  7.46,  DesignToken.accentPrimary,   .next,     false),
            ("wp.warmiwanusca",  "Warmiwañusca (Dead Woman's Pass)", CGPoint(x: 792, y: 425),  11.81, DesignToken.accentSecondary, .upcoming, false),
            ("wp.pacaymayo",     "Pacaymayo",                       CGPoint(x: 730, y: 379),  13.67, DesignToken.accentPrimary,   .upcoming, false),
            ("wp.chaquicocha",   "Chaquicocha",                     CGPoint(x: 611, y: 388),  17.40, DesignToken.accentPrimary,   .upcoming, false),
            ("wp.winaywayna",    "Wiñay Wayna",                     CGPoint(x: 410, y: 303),  23.61, DesignToken.accentPrimary,   .upcoming, false),
            ("wp.intipunku",     "Inti Punku (Sun Gate)",           CGPoint(x: 347, y: 348),  25.48, DesignToken.accentPrimary,   .upcoming, false),
            ("wp.machupicchu",   "Machu Picchu",                    CGPoint(x: 300, y: 368),  26.72, DesignToken.reward,          .upcoming, true)
        ]
        let waypoints = waypointSpec.map { spec in
            MapWaypoint(id: spec.0, position: spec.2, name: spec.1,
                        milesFromStart: spec.3, accentToken: spec.4,
                        state: spec.5, isDestination: spec.6)
        }

        return MapAuthoring(
            name: "Inca Trail",
            bounds: CGRect(x: 0, y: 0, width: 1200, height: 800),
            seed: 0x17CA_11,
            journeyMiles: journeyMiles,
            regions: regions,
            waypoints: waypoints
        )
    }
}
