//
//  SampleJourneyMap.swift
//  JourneyTracker
//
//  A replace-level PROOF for the P2 generator (KAN-19): the P1 specimen's layout,
//  re-expressed as authored REGION records + a seed instead of hand-placed glyphs.
//  It passes every validator and generates a scene the renderer draws with the
//  approved P1 aesthetic (feathered masses, faceting, melting mouths, snow caps).
//
//  Scale (App Concept doc, "the specimen looks like 10 miles, not 1,800"): this is
//  a ~30-mile leg, so one full-screen render ≈ chapter zoom and proportions match
//  the approved P1 specimen — the lake reads clearly bigger than the river width,
//  forests read as dense masses, not specks. Region sizes still obey the canonical
//  real-mile bounds; because a 75-mi-minimum range can't fit a 30-mi corridor, the
//  Ember Spire range runs off BOTH map edges (validated on TOTAL length; the
//  renderer clips) — scenery is bigger than the journey, exactly as intended.
//
//  All names are original JourneyTracker proper nouns — no real-world IP.
//

import CoreGraphics

enum SampleJourneyMap {

    /// A ~30-mile stretch. The trek path's smoothed arc length (~470 map units)
    /// anchors miles-per-map-unit at ≈0.064 mi/unit, under which every region below
    /// validates (see the per-region comments).
    static let journeyMiles = 30.0

    static func make() -> MapAuthoring {
        var regions: [MapRegion] = []

        // Ocean / coast down the right edge — bays curve inland, headlands seaward,
        // never a straight edge (§07.5). River 2 meets the sea at (314, 286).
        regions.append(.coast(.init(
            id: "coast.east",
            coastline: [
                CGPoint(x: 325, y: -12), CGPoint(x: 332, y: 60), CGPoint(x: 300, y: 132),
                CGPoint(x: 348, y: 202), CGPoint(x: 314, y: 286), CGPoint(x: 356, y: 360),
                CGPoint(x: 305, y: 440), CGPoint(x: 342, y: 520), CGPoint(x: 322, y: 612),
                CGPoint(x: 330, y: 712)
            ],
            seaward: CGVector(dx: 1, dy: 0),
            seaCorners: [CGPoint(x: 420, y: 720), CGPoint(x: 420, y: -20)]
        )))

        // Ember Spire's range — a broad mass across the top, densest at the summit.
        // 1200 map units long ≈ 76.6 mi (75–300 ✓), 124 units wide ≈ 7.9 mi (≤10 ✓).
        // It runs off BOTH side edges (x −430…770); the renderer clips to bounds.
        // An explicit density keeps the on-screen (in-bounds) peak count moderate
        // (§07.4) despite the huge off-map authored area.
        regions.append(.range(.init(
            id: "range.emberspire",
            center: CGPoint(x: 170, y: 150),
            axisAngle: 0,
            halfLength: 600,
            halfWidth: 62,
            snowCaps: 5,
            scatter: ScatterParams(density: 0.00052, feather: 0.5)
        )))

        // Two forests — feathered elliptical masses, P1-scale. ~55 sq mi and ~21 sq
        // mi, both inside 0.5–300 sq mi.
        regions.append(.forest(.init(id: "forest.westwood", center: CGPoint(x: 92, y: 430), rx: 74, ry: 58)))
        regions.append(.forest(.init(id: "forest.copse", center: CGPoint(x: 255, y: 545), rx: 46, ry: 36)))

        // A lake — asymmetric blob, ≈11.9 sq mi (0.3–30 ✓), clearly wider than any
        // river. River 1 melts into it.
        regions.append(.lake(.init(
            id: "lake.stillwater",
            ring: [
                CGPoint(x: 165, y: 455), CGPoint(x: 187, y: 430), CGPoint(x: 219, y: 435),
                CGPoint(x: 237, y: 460), CGPoint(x: 215, y: 485), CGPoint(x: 175, y: 487)
            ]
        )))

        // River 1: source in the range, meanders down the CENTER-RIGHT corridor,
        // MELTS into the lake (freshwater mouth, derived). Kept well east of the
        // trek so the two never run alongside each other.
        regions.append(.river(.init(
            id: "river.brightwater",
            hint: [CGPoint(x: 215, y: 155), CGPoint(x: 222, y: 250),
                   CGPoint(x: 210, y: 350), CGPoint(x: 203, y: 450)],
            meanderAmplitude: 9, sourceWidth: 5, mouthWidth: 11
        )))
        // River 2: source in the range, MELTS into the sea at the coast (sea mouth,
        // derived).
        regions.append(.river(.init(
            id: "river.saltrun",
            hint: [CGPoint(x: 258, y: 155), CGPoint(x: 288, y: 215),
                   CGPoint(x: 310, y: 255), CGPoint(x: 314, y: 286)],
            meanderAmplitude: 9, sourceWidth: 5, mouthWidth: 12
        )))

        // Ground cover: a plains wash (with scattered tufts), a dune patch, a marsh.
        regions.append(.groundCover(.init(
            id: "plains.lowmeadow", kind: .plains,
            ring: [
                CGPoint(x: 60, y: 510), CGPoint(x: 160, y: 486), CGPoint(x: 270, y: 505),
                CGPoint(x: 300, y: 580), CGPoint(x: 260, y: 660), CGPoint(x: 150, y: 685),
                CGPoint(x: 75, y: 660), CGPoint(x: 50, y: 585)
            ]
        )))
        regions.append(.groundCover(.init(
            id: "dunes.saltflat", kind: .dunes,
            ring: [
                CGPoint(x: 45, y: 635), CGPoint(x: 80, y: 628), CGPoint(x: 118, y: 640),
                CGPoint(x: 120, y: 668), CGPoint(x: 82, y: 678), CGPoint(x: 48, y: 668)
            ]
        )))
        regions.append(.groundCover(.init(
            id: "marsh.reedbank", kind: .marsh,
            ring: [
                CGPoint(x: 118, y: 495), CGPoint(x: 138, y: 488), CGPoint(x: 160, y: 494),
                CGPoint(x: 164, y: 508), CGPoint(x: 144, y: 516), CGPoint(x: 122, y: 510)
            ]
        )))

        // Two villages, each within ~4 mi of water (§07.5) and spaced well apart —
        // and away from the Crosswater pin so the junction doesn't pile up. Homes
        // that jitter into water are resampled dry by the generator.
        regions.append(.settlement(.init(id: "village.rillford", site: CGPoint(x: 239, y: 472),
                                         name: "Rillford", homeCount: 4)))     // lake E shore
        regions.append(.settlement(.init(id: "village.mossbeck", site: CGPoint(x: 225, y: 320),
                                         name: "Mossbeck", homeCount: 3)))     // by river 1

        // The dot-dash trek path up the LEFT corridor. Its control points INCLUDE
        // the three waypoint positions (App Concept doc: "waypoints ARE control
        // points"), so the smoothed curve passes exactly through each pin. It stays
        // x ≤ 160 — clear of the lake (x ≥ 165) and river 1 (x ≥ 203), so it never
        // crosses water and never runs alongside the river (§07.5).
        regions.append(.trekPath(.init(
            id: "trek.emberspire",
            points: [
                CGPoint(x: 118, y: 566), CGPoint(x: 108, y: 500), CGPoint(x: 128, y: 455),
                CGPoint(x: 142, y: 440), CGPoint(x: 150, y: 375), CGPoint(x: 156, y: 290),
                CGPoint(x: 150, y: 210), CGPoint(x: 158, y: 175), CGPoint(x: 160, y: 150)
            ]
        )))

        let waypoints = [
            MapWaypoint(id: "wp.thistledown", position: CGPoint(x: 118, y: 566),
                        name: "Thistledown", milesFromStart: 0,
                        accentToken: DesignToken.accentPrimary, state: .reached),
            MapWaypoint(id: "wp.crosswater", position: CGPoint(x: 142, y: 440),
                        name: "Crosswater", milesFromStart: 8.5,
                        accentToken: DesignToken.accentSecondary, state: .next),
            MapWaypoint(id: "wp.emberspire", position: CGPoint(x: 160, y: 150),
                        name: "Ember Spire", milesFromStart: journeyMiles,
                        accentToken: DesignToken.reward, state: .upcoming, isDestination: true)
        ]

        return MapAuthoring(
            name: "Ember Spire — sample leg",
            bounds: CGRect(x: 0, y: 0, width: 390, height: 700),
            seed: 0xE3B_5CA7,
            journeyMiles: journeyMiles,
            regions: regions,
            waypoints: waypoints
        )
    }
}
