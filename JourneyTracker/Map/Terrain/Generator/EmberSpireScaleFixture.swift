//
//  EmberSpireScaleFixture.swift
//  JourneyTracker
//
//  A DEBUG-ONLY performance fixture (KAN-20, P3): a full ~1,800-mile journey —
//  the real Ember Spire distance — authored as a programmatically generated,
//  SEEDED region list so the camera / LOD / culling / size-taper can be
//  stress-tested at true journey scale. It is NOT shipping content and NOT the P4
//  real Ember Spire map (authored deliberately at P4); it is a deterministic
//  scale torture test that must pass every validator.
//
//  The world is a WIDE ribbon (~10,000 × 21,000 map units, ≈1:2 at overview): the
//  trek meanders east-west in serpentine lobes down the whole world instead of a
//  thin vertical thread. Ranges are ORIENTED oblique massifs at varied angles (not
//  full-width horizontal walls); lakes are rejection-placed clear of the trek and
//  sized toward the upper half of their bound so they hold their own; rivers drain
//  a range into a lake or the coast. Everything is sized in REAL MILES and
//  converted through the measured miles-per-map-unit, so region bounds hold
//  regardless of the exact trek arc length (ranges may run off-map; the renderer
//  clips). Names reuse the App Concept doc's canonical Ember Spire waypoints —
//  original JourneyTracker proper nouns, no real-world IP.
//

import CoreGraphics

enum EmberSpireScaleFixture {

    static let journeyMiles = 1800.0

    static func make(seed: UInt64 = 0x5CA1_E7E5_7) -> MapAuthoring {
        let bounds = CGRect(x: 0, y: 0, width: 10000, height: 21000)

        // 1 · The serpentine trek spine, measured to derive the real-distance scale.
        let trekPoints = makeTrek()
        let sampled = MapGeometry.catmullRomSampled(trekPoints)
        let arc = MapGeometry.polylineLength(sampled)
        let mpu = journeyMiles / Double(arc)
        func u(_ miles: Double) -> CGFloat { CGFloat(miles / mpu) }

        var rng = SplitMix64(seed: seed)
        var regions: [MapRegion] = []

        // 2 · Coast down the far east edge (gentle wave). Sea mouths terminate here;
        // the trek (x ≤ ~8,600) never reaches it.
        let coastX: CGFloat = 9650
        let coastControls: [CGPoint] = (0...15).map { i in
            CGPoint(x: coastX + 45 * sin(Double(i) * 0.8), y: -300 + Double(i) * 1450)
        }
        regions.append(.coast(.init(
            id: "coast.east",
            coastline: coastControls,
            seaward: CGVector(dx: 1, dy: 0),
            seaCorners: [CGPoint(x: 10500, y: 21400), CGPoint(x: 10500, y: -400)]
        )))

        // 3 · Oblique mountain massifs at varied positions and angles. 190 mi long,
        // 8 mi wide (inside 15–300 / ≤10 by construction). Several run off-map.
        struct RangeRef { let center: CGPoint }
        var ranges: [RangeRef] = []
        for k in 0..<10 {
            let cx = CGFloat(700 + Double.random(in: 0...8600, using: &rng))
            let cy = CGFloat(900 + Double(k) * 2000 + Double.random(in: -400...400, using: &rng))
            let angle = CGFloat(Double.random(in: -0.9...0.9, using: &rng))
            regions.append(.range(.init(
                id: "range.\(k)",
                center: CGPoint(x: cx, y: cy),
                axisAngle: angle,
                halfLength: u(95),   // 190 mi
                halfWidth: u(4),     // 8 mi
                snowCaps: 4,
                scatter: ScatterParams(density: 0.00055, feather: 0.5)
            )))
            ranges.append(RangeRef(center: CGPoint(x: cx, y: cy)))
        }
        func nearestRange(to p: CGPoint, maxMiles: Double) -> CGPoint? {
            var best: CGPoint?; var bestD = CGFloat.greatestFiniteMagnitude
            for r in ranges {
                let d = MapGeometry.dist(r.center, p)
                if d < bestD { bestD = d; best = r.center }
            }
            guard let best, Double(bestD) * mpu <= maxMiles else { return nil }
            return best
        }

        // 4 · Lakes, rejection-placed well clear of the trek (so the trek never
        // crosses water), sized ~15–20 sq mi (mid-range of 0.3–60).
        let lakeRadius = u(2.6)
        for k in 0..<8 {
            var center: CGPoint?
            for _ in 0..<60 {
                let c = CGPoint(x: CGFloat(Double.random(in: 900...9100, using: &rng)),
                                y: CGFloat(Double.random(in: 900...20100, using: &rng)))
                // Clear of the trek by more than the ring radius + margin.
                if MapGeometry.distanceToPolyline(c, sampled) > 2 * lakeRadius + u(3) {
                    center = c; break
                }
            }
            guard let c = center else { continue }
            regions.append(.lake(.init(id: "lake.\(k)", ring: lakeRing(c, lakeRadius, &rng))))
            // A lakeside settlement (homes resampled dry by the generator).
            regions.append(.settlement(.init(
                id: "town.lake\(k)",
                site: CGPoint(x: c.x + lakeRadius + u(1.0), y: c.y),
                name: "Rillford \(k)", homeCount: 4)))
            // A river draining a nearby range INTO this lake (freshwater mouth).
            if let src = nearestRange(to: c, maxMiles: 150) {
                regions.append(.river(.init(
                    id: "river.fresh\(k)",
                    hint: [src, CGPoint(x: (src.x + c.x) / 2, y: (src.y + c.y) / 2), c],
                    meanderAmplitude: u(1.6), sourceWidth: 4, mouthWidth: 9)))
            }
        }

        // 5 · A few sea rivers: an easterly range → the nearest coast point.
        var seaCount = 0
        for r in ranges where r.center.x > 5500 && seaCount < 4 {
            let ctrlIdx = min(coastControls.count - 1, max(0, Int((r.center.y + 300) / 1450)))
            let mouth = coastControls[ctrlIdx]
            guard Double(MapGeometry.dist(r.center, mouth)) * mpu <= 200 else { continue }
            regions.append(.river(.init(
                id: "river.sea\(seaCount)",
                hint: [r.center, CGPoint(x: (r.center.x + mouth.x) / 2, y: (r.center.y + mouth.y) / 2), mouth],
                meanderAmplitude: u(1.4), sourceWidth: 4, mouthWidth: 11)))
            regions.append(.settlement(.init(
                id: "town.sea\(seaCount)",
                site: CGPoint(x: mouth.x - u(2.0), y: mouth.y),
                name: "Saltmere \(seaCount)", homeCount: 3)))
            seaCount += 1
        }

        // 6 · Forests — feathered elliptical masses at varied positions & aspect
        // (23–110 sq mi, inside 0.5–300).
        for k in 0..<16 {
            let cx = CGFloat(700 + Double.random(in: 0...8300, using: &rng))
            let cy = CGFloat(700 + Double.random(in: 0...19600, using: &rng))
            regions.append(.forest(.init(
                id: "forest.\(k)",
                center: CGPoint(x: cx, y: cy),
                rx: u(Double.random(in: 3.5...7.0, using: &rng)),
                ry: u(Double.random(in: 2.6...5.0, using: &rng)),
                autumn: k % 5 == 0)))
        }

        // 7 · Plains washes (scattered tufts) for broad ground-cover grain.
        for k in 0..<7 {
            let cx = CGFloat(1000 + Double.random(in: 0...7000, using: &rng))
            let cy = CGFloat(1200 + Double(k) * 2700 + Double.random(in: -500...500, using: &rng))
            regions.append(.groundCover(.init(
                id: "plains.\(k)", kind: .plains,
                ring: blobRing(CGPoint(x: cx, y: cy), u(9), &rng))))
        }

        // 8 · The dot-dash trek path + its waypoints (canonical Ember Spire names).
        // Positions are read off the sampled path at real mileage, so each lies ON
        // the path and its anchor is exact.
        regions.append(.trekPath(.init(id: "trek.emberspire", points: trekPoints)))

        let waypointSpec: [(String, String, Double, String, MapWaypoint.State, Bool)] = [
            ("wp.thistledown", "Thistledown",   0,    DesignToken.accentPrimary,   .reached,  false),
            ("wp.crosswater",  "Crosswater",    120,  DesignToken.accentPrimary,   .reached,  false),
            ("wp.silvergate",  "Silvergate",    460,  DesignToken.accentPrimary,   .reached,  false),
            ("wp.deepdelve",   "The Deepdelve",  660,  DesignToken.accentSecondary, .next,    false),
            ("wp.whisperwood", "Whisperwood",   720,  DesignToken.accentSecondary, .upcoming, false),
            ("wp.windmark",    "The Windmark",  1040,  DesignToken.accentSecondary, .upcoming, false),
            ("wp.whitewatch",  "Whitewatch",    1540,  DesignToken.accentSecondary, .upcoming, false),
            ("wp.emberspire",  "Ember Spire",    1800,  DesignToken.reward,          .upcoming, true)
        ]
        let waypoints = waypointSpec.map { spec -> MapWaypoint in
            let pos = MapGeometry.pointAtArcLength(sampled, arcLength: u(spec.2))
            return MapWaypoint(id: spec.0, position: pos, name: spec.1,
                               milesFromStart: spec.2, accentToken: spec.3,
                               state: spec.4, isDestination: spec.5)
        }

        return MapAuthoring(
            name: "Ember Spire — scale test (KAN-20 debug fixture)",
            bounds: bounds,
            seed: seed,
            journeyMiles: journeyMiles,
            regions: regions,
            waypoints: waypoints
        )
    }

    /// The default marker position for the debug entry — a bit past Silvergate, so
    /// the current leg is Silvergate → The Deepdelve.
    static let defaultMarkerMiles = 560.0

    // MARK: - Builders

    /// A serpentine trek: it sweeps east-west in lobes while descending the world.
    private static func makeTrek() -> [CGPoint] {
        let n = 57
        return (0..<n).map { i in
            let t = Double(i) / Double(n - 1)
            let x = 5000 + 3600 * sin(t * .pi * 5)   // ~2.5 east-west lobes
            let y = 20600 - t * 20200                 // top-to-bottom descent
            return CGPoint(x: x, y: y)
        }
    }

    private static func lakeRing(_ c: CGPoint, _ radius: CGFloat, _ rng: inout SplitMix64) -> [CGPoint] {
        (0..<7).map { i in
            let a = Double(i) / 7 * 2 * .pi
            let rr = radius * CGFloat(0.82 + 0.30 * Double.random(in: 0...1, using: &rng))
            return CGPoint(x: c.x + cos(a) * rr, y: c.y + sin(a) * rr * 0.88)
        }
    }

    private static func blobRing(_ c: CGPoint, _ radius: CGFloat, _ rng: inout SplitMix64) -> [CGPoint] {
        (0..<8).map { i in
            let a = Double(i) / 8 * 2 * .pi
            let rr = radius * CGFloat(0.82 + 0.3 * Double.random(in: 0...1, using: &rng))
            return CGPoint(x: c.x + cos(a) * rr, y: c.y + sin(a) * rr * 0.9)
        }
    }
}
