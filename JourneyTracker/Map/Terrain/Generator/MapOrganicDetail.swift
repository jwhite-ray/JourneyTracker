//
//  MapOrganicDetail.swift
//  JourneyTracker
//
//  The ORGANIC-DETAIL pass for the seeded map generator (KAN-23, epic KAN-16).
//  Justin ruled at the KAN-20 gate that generated geography looks computer-made —
//  "ocean is all one straight line, rivers aren't meandering enough." Phase 4a's
//  pipeline is: he hand-draws the world → the coordinator digitizes it into
//  `MapRegion` records (coastlines/rivers traced as ~20–40 control points) → THIS
//  pass adds seeded organic detail so his traced linework renders INKED, not
//  plotted, at every zoom.
//
//  Everything here is a PURE function of its inputs plus a per-region substream
//  (App Concept doc: "the generator is a pure function of `(regions, seed)`" — no
//  `Date()`, no unseeded RNG, substream-isolated per region). `MapGenerator` calls
//  these at GENERATION time; the displaced/meandered geometry becomes the scene's
//  `TerrainCoast` / `TerrainRiver`s, so `TerrainRenderer` and the P3 camera path
//  are unchanged. The `MapValidator` still validates AUTHORING (undisplaced), while
//  the generator's own placement mask (`WaterMask`) validates against what is
//  actually DRAWN — the displaced coastline — so a home is never left standing in a
//  bay the noise carved (the KAN-19/20 hard-won lesson: validate what you draw).
//

import CoreGraphics

enum MapOrganicDetail {

    // MARK: - Tuning constants (all in real MILES where scale matters, so a coast
    // wanders the same physical amount whether the map is 30 mi or 1,800 mi).

    /// A coast should never wander more than a few real miles from the authored
    /// line — the sketch is authority. This is the hard ceiling; the actual
    /// amplitude is proportional to authored segment length and usually well under.
    static let coastMaxWanderMiles = 2.0
    /// Coast displacement amplitude as a fraction of mean authored segment length
    /// (before the mile clamp). Tuned so a hand-traced coast reads as coves/points.
    static let coastAmpFactor: CGFloat = 0.28
    /// Map-unit radius over which the coast is pinned back toward the authored line
    /// around an anchor (a river sea-mouth, a shoreside town): keeps mouths melting
    /// on the drawn shore and shoreside settlements dry.
    static let coastAnchorPinRadius: CGFloat = 22

    /// A river's meandered centerline may not inflate its drawn length past this
    /// multiple of the (smoothed) authored hint — visual honesty; the mile-scale
    /// anchor lives on the trek, but a river shouldn't silently double in length.
    static let riverMaxLengthRatio: CGFloat = 1.5
    /// The meander TARGET: amplitude is searched so the drawn river is this much
    /// longer than its hint — a river that visibly snakes (Justin's KAN-20 note:
    /// "rivers aren't meandering enough"), comfortably under the 1.5 hard cap.
    static let riverTargetLengthRatio: CGFloat = 1.38
    /// Headroom on the authored `meanderAmplitude` when searching for the target
    /// ratio (the authored value scales the ceiling; roughness=0 keeps it straight).
    static let riverAmplitudeHeadroom: CGFloat = 6

    /// Physical wavelength of the trek/road hand-waver — a gentle wander a couple of
    /// real miles long, so a straight leg reads hand-inked, not ruler-drawn.
    static let pathWaverWavelengthMiles = 1.5

    /// One tributary per this many real miles of main river, capped.
    static let tributarySpacingMiles = 7.0
    static let tributaryMaxCount = 4
    /// How far a tributary will look for an uphill range to run toward.
    static let tributaryReachMiles = 30.0
    static let tributaryMaxMiles = 3.0
    static let tributaryMinMiles = 1.3
    /// A tributary is drawn thin at its own source, scaling INTO the main river's
    /// local body width at the junction (so it melts, not caps — §07.3.3).
    static let tributarySourceWidth: CGFloat = 2.5

    /// Trek/road hand-waver amplitude at the design-reference scale (~1–2 pt).
    static let pathWaverMiles = 0.12
    static let pathWaverUnitsFallback: CGFloat = 1.5
    /// Map-unit radius around a waypoint over which the waver tapers to ZERO — a
    /// waypoint must sit EXACTLY on the drawn path (waypoints-on-path is a validator).
    static let pathWaverPinRadius: CGFloat = 4

    // MARK: - Multi-octave smooth value noise

    /// Deterministic multi-octave value noise over a normalized parameter s ∈ [0,1].
    /// Each octave is a lattice of random values in [-1,1] (drawn from the region's
    /// substream), smoothstep-interpolated and summed with decreasing weights, then
    /// normalized to ~[-1,1]. Reads as organic coves/bends rather than a sine wave.
    struct OctaveNoise {
        private let octaves: [(nodes: [Double], weight: Double)]
        private let weightSum: Double

        init(nodeCounts: [Int], weights: [Double], rng: inout SplitMix64) {
            var oct: [(nodes: [Double], weight: Double)] = []
            var ws = 0.0
            for (i, raw) in nodeCounts.enumerated() {
                let count = max(2, raw)
                let w = i < weights.count ? weights[i] : (weights.last ?? 1)
                var nodes: [Double] = []
                nodes.reserveCapacity(count)
                for _ in 0..<count { nodes.append(Double.random(in: -1...1, using: &rng)) }
                oct.append((nodes, w))
                ws += w
            }
            octaves = oct
            weightSum = ws > 0 ? ws : 1
        }

        func value(_ s: Double) -> Double {
            let ss = min(max(s, 0), 1)
            var acc = 0.0
            for (nodes, w) in octaves {
                let n = nodes.count
                let xf = ss * Double(n - 1)
                let i0 = min(Int(xf), n - 2)
                let t = xf - Double(i0)
                let u = t * t * (3 - 2 * t) // smoothstep
                acc += (nodes[i0] + (nodes[i0 + 1] - nodes[i0]) * u) * w
            }
            return acc / weightSum
        }
    }

    // MARK: - 1 · Coastline organic displacement (§07.3.5)

    /// Displaces an authored coastline polyline by seeded multi-octave perpendicular
    /// noise — large gentle sweeps + medium bays + fine crenellation — so a traced
    /// shore reads inked at every scale. Amplitude is proportional to authored
    /// segment length and clamped to a few real miles. The two endpoints and a
    /// radius around each `anchor` (river sea-mouths, shoreside towns) are pinned
    /// back to the authored line, so mouths still melt on the drawn shore and
    /// shoreside settlements stay dry. Bays curve toward land, headlands toward open
    /// water — the symmetric noise produces both (§07.3.5), never sawtooth.
    static func displaceCoastline(_ coastline: [CGPoint],
                                  seaward: CGVector,
                                  roughness: Double,
                                  globalRoughness: Double,
                                  milesPerMapUnit: Double,
                                  anchors: [CGPoint],
                                  rng: inout SplitMix64) -> [CGPoint] {
        guard coastline.count >= 2 else { return coastline }
        let effRough = max(0, roughness) * max(0, globalRoughness)
        guard effRough > 0 else { return coastline }

        let base = MapGeometry.catmullRomSampled(coastline, perSegment: 12)
        let n = base.count
        guard n >= 4 else { return coastline }

        let authoredSegs = max(1, coastline.count - 1)
        let meanSeg = MapGeometry.polylineLength(coastline) / CGFloat(authoredSegs)
        let clampUnits: CGFloat = milesPerMapUnit > 0
            ? CGFloat(coastMaxWanderMiles / milesPerMapUnit) : meanSeg
        let amplitude = min(clampUnits, coastAmpFactor * CGFloat(effRough) * meanSeg)
        guard amplitude > 0 else { return coastline }

        // Octave node counts scale with authored vertex count → constant physical
        // wavelength regardless of map size (a long coast gets proportionally more
        // bays, not longer ones).
        let noise = OctaveNoise(
            nodeCounts: [max(3, Int((Double(authoredSegs) * 0.45).rounded())),
                         max(6, Int((Double(authoredSegs) * 1.4).rounded())),
                         max(12, Int((Double(authoredSegs) * 3.2).rounded()))],
            weights: [1.0, 0.5, 0.28], rng: &rng)

        let arc = cumulativeArc(base)
        let total = arc.last ?? 0
        guard total > 0 else { return coastline }
        let pinArc = max(Double(meanSeg), total * 0.05)

        var out: [CGPoint] = []
        out.reserveCapacity(n)
        for i in 0..<n {
            let s = Double(arc[i]) / Double(total)
            // Endpoint taper (the coast runs off-map; keep the sea-polygon closure
            // to the corners clean).
            let endEnv = min(smoothRamp(Double(arc[i]) / pinArc),
                             smoothRamp(Double(total - arc[i]) / pinArc))
            var pinEnv = 1.0
            for a in anchors {
                pinEnv = min(pinEnv, smoothRamp(Double(MapGeometry.dist(base[i], a) / coastAnchorPinRadius)))
            }
            let env = CGFloat(min(endEnv, pinEnv))
            let offset = amplitude * env * CGFloat(noise.value(s))
            let normal = localNormal(base, i)
            out.append(CGPoint(x: base[i].x + normal.dx * offset,
                               y: base[i].y + normal.dy * offset))
        }
        out[0] = base[0]
        out[n - 1] = base[n - 1]
        _ = seaward // orientation is carried by TerrainCoast; noise is symmetric.
        return out
    }

    // MARK: - 2 · River meander upgrade (§07.3.3 / §07.5)

    /// Meanders a source→mouth hint with layered octaves (long sweeps + medium
    /// bends + small wiggles) instead of the old single-frequency alternating lobe.
    /// A `sin(πt)` envelope pins both endpoints (source in its range, mouth in the
    /// water) and tapers the wander to nothing there. Amplitude is shrunk until the
    /// drawn length stays within `riverMaxLengthRatio` of the smoothed hint.
    ///
    /// WATER-CHECK (KAN-23, Rooster finding 1): if `avoidSeas`/`avoidLakes` are given,
    /// the amplitude is further shrunk until no mid-course sample lands in the sea or
    /// a lake — so a lobe never crosses into the ocean bands and back ("continuing
    /// under the ocean fill", forbidden). The mouth's OWN approach into its `receiver`
    /// (the lake/sea it drains into) is excluded from the check, since a river is
    /// meant to enter its receiver there.
    static func meanderRiver(_ hint: [CGPoint],
                             amplitude: CGFloat,
                             globalRoughness: Double,
                             avoidSeas: [[CGPoint]] = [],
                             avoidLakes: [[CGPoint]] = [],
                             receiver: [CGPoint]? = nil,
                             rng: inout SplitMix64) -> [CGPoint] {
        guard hint.count >= 2 else { return hint }
        let base = MapGeometry.catmullRomSampled(hint, perSegment: 8)
        let n = base.count
        guard n >= 3 else {
            var out = base
            if let f = hint.first { out[0] = f }
            if let l = hint.last { out[out.count - 1] = l }
            return out
        }
        let amp = amplitude * CGFloat(max(0, globalRoughness))
        let length = MapGeometry.polylineLength(base)
        guard amp > 0, length > 0 else {
            var out = base
            out[0] = hint.first!; out[n - 1] = hint.last!
            return out
        }

        // Weight the MEDIUM (bend) octave highest so the river SNAKES — alternating
        // curves (§07.5), not a single broad bow. A low-freq octave alone just bows
        // the river once; the medium octave gives the several sign-reversals that
        // read as meander, with fine wiggles on top.
        let noise = OctaveNoise(
            nodeCounts: [max(2, Int(Double(length) / 150)),
                         max(4, Int(Double(length) / 42)),
                         max(6, Int(Double(length) / 18))],
            weights: [0.5, 1.0, 0.5], rng: &rng)

        // Dimensionless unit offset per sample: envelope × noise, zero at both ends.
        var unit = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / Double(n - 1)
            unit[i] = sin(t * .pi) * noise.value(t)
        }

        func build(_ A: CGFloat) -> [CGPoint] {
            var out: [CGPoint] = []
            out.reserveCapacity(n)
            for i in 0..<n {
                let normal = localNormal(base, i)
                out.append(CGPoint(x: base[i].x + normal.dx * A * CGFloat(unit[i]),
                                   y: base[i].y + normal.dy * A * CGFloat(unit[i])))
            }
            out[0] = hint.first!
            out[n - 1] = hint.last!
            return out
        }
        func lengthAt(_ A: CGFloat) -> CGFloat { MapGeometry.polylineLength(build(A)) }

        // Drawn length grows monotonically with amplitude, so binary-search the
        // amplitude that meanders the river to the TARGET ratio (a visible snake),
        // bounded by the authored-amplitude ceiling and the 1.5 hard cap.
        let amplitudeCeiling = amp * riverAmplitudeHeadroom
        let targetLen = riverTargetLengthRatio * length
        let maxLen = riverMaxLengthRatio * length
        var A: CGFloat
        if lengthAt(amplitudeCeiling) <= targetLen {
            A = amplitudeCeiling            // authored amplitude can't reach the target
        } else {
            var lo: CGFloat = 0, hi = amplitudeCeiling
            for _ in 0..<24 {
                let mid = (lo + hi) / 2
                if lengthAt(mid) < targetLen { lo = mid } else { hi = mid }
            }
            A = lo
        }
        // Never exceed the hard cap.
        if lengthAt(A) > maxLen {
            var lo: CGFloat = 0, hi = A
            for _ in 0..<24 {
                let mid = (lo + hi) / 2
                if lengthAt(mid) < maxLen { lo = mid } else { hi = mid }
            }
            A = lo
        }
        // Water clearance: shrink until no mid-course sample (excluding the mouth's
        // own approach into its receiver) sits in a forbidden sea/lake. Monotone-ish
        // in A; a few multiplicative steps converge. If even a straight river (A→0)
        // isn't clear, the AUTHORED hint itself crosses water (an authoring error the
        // fixtures don't have) — we return the straightest we can.
        if !avoidSeas.isEmpty || !avoidLakes.isEmpty {
            var guardIter = 0
            while A > 0.01,
                  meanderEntersWater(build(A), seas: avoidSeas, lakes: avoidLakes, receiver: receiver),
                  guardIter < 20 {
                A *= 0.7
                guardIter += 1
            }
            if A <= 0.01 { A = 0 }
        }
        return build(A)
    }

    /// True if any sample of `line` sits inside a sea/lake fill it must NOT cross. The
    /// final contiguous run of samples inside `receiver` (the mouth's legitimate
    /// approach into its own receiving water) is excluded.
    private static func meanderEntersWater(_ line: [CGPoint],
                                           seas: [[CGPoint]],
                                           lakes: [[CGPoint]],
                                           receiver: [CGPoint]?) -> Bool {
        var approachStart = line.count
        if let receiver, receiver.count >= 3 {
            var k = line.count - 1
            while k >= 0, MapGeometry.polygonContains(line[k], receiver) { k -= 1 }
            approachStart = k + 1
        }
        for i in 0..<min(approachStart, line.count) {
            let p = line[i]
            for sea in seas where MapGeometry.polygonContains(p, sea) { return true }
            for lake in lakes where MapGeometry.polygonContains(p, lake) { return true }
        }
        return false
    }

    // MARK: - 3 · Tributaries (§07.3.3)

    /// The geometry a tributary must not cross: it's texture, not navigation.
    struct TributaryContext {
        var lakeRings: [[CGPoint]]      // smoothed lake rings (drawn)
        var seaPolygons: [[CGPoint]]    // displaced sea polygons (drawn), one per coast
        var avoidPolylines: [[CGPoint]] // trek + roads + OTHER rivers' meandered lines
        var ranges: [MapRegion.Range]
        var milesPerMapUnit: Double
    }

    /// Generates a main river's optional side-streams from its substream: each
    /// branches from a deterministic point along the main centerline, runs uphill
    /// toward a nearby range (or a few miles off into terrain), is drawn thin at its
    /// own source and scales into the main's local body width at the junction, and
    /// MELTS into the main via the same fill-continuity trick as a mouth (a
    /// `.confluence` mouth: no hard cap at the join). Count scales with main length.
    /// A tributary that would cross a lake, the sea, the trek, or another river is
    /// shortened and, failing that, skipped — conservatively placed, always
    /// deterministic.
    static func tributaries(hasTributaries: Bool,
                            mainCenterline: [CGPoint],
                            mainSourceWidth: CGFloat,
                            mainMouthWidth: CGFloat,
                            globalRoughness: Double,
                            context: TributaryContext,
                            rng: inout SplitMix64) -> [TerrainRiver] {
        guard hasTributaries else { return [] }
        let mpu = context.milesPerMapUnit
        guard mpu > 0, mainCenterline.count >= 2 else { return [] }
        let lengthMiles = Double(MapGeometry.polylineLength(mainCenterline)) * mpu
        let count = min(tributaryMaxCount, Int((lengthMiles / tributarySpacingMiles).rounded(.down)))
        guard count > 0 else { return [] }

        func u(_ miles: Double) -> CGFloat { CGFloat(miles / mpu) }
        var out: [TerrainRiver] = []
        for k in 0..<count {
            // Spread branch points across the mid-river, jittered from the substream.
            let slot = (Double(k) + 0.5) / Double(count)
            let branchT = min(0.82, max(0.28, slot * 0.6 + 0.28 + Double.random(in: -0.05...0.05, using: &rng)))
            let junction = pointAtFraction(mainCenterline, branchT)
            let mainWidthHere = mainSourceWidth + (mainMouthWidth - mainSourceWidth) * CGFloat(branchT)
            let tangent = tangentAtFraction(mainCenterline, branchT)

            var dir: CGVector
            if let range = nearestRangeCenter(junction, ranges: context.ranges,
                                              maxMiles: tributaryReachMiles, mpu: mpu) {
                dir = CGVector(dx: range.x - junction.x, dy: range.y - junction.y).normalizedVector
            } else {
                let side: CGFloat = Double.random(in: 0...1, using: &rng) < 0.5 ? -1 : 1
                dir = CGVector(dx: tangent.normal.dx * side, dy: tangent.normal.dy * side)
            }
            if dir.length == 0 { continue }

            // Try a few lengths, longest first; accept the first that stays clear.
            var placed: TerrainRiver?
            for attempt in 0..<4 {
                let miles = tributaryMaxMiles - Double(attempt) * 0.55
                guard miles >= tributaryMinMiles else { break }
                let far = CGPoint(x: junction.x + dir.dx * u(miles),
                                  y: junction.y + dir.dy * u(miles))
                let mid = CGPoint(x: (far.x + junction.x) / 2 + dir.normal.dx * u(0.3),
                                  y: (far.y + junction.y) / 2 + dir.normal.dy * u(0.3))
                let line = meanderRiver([far, mid, junction], amplitude: u(0.25),
                                        globalRoughness: globalRoughness, rng: &rng)
                if tributaryClear(line, context: context) {
                    placed = TerrainRiver(centerline: line,
                                          sourceWidth: tributarySourceWidth,
                                          mouthWidth: max(tributarySourceWidth + 0.5, mainWidthHere),
                                          mouth: .confluence,
                                          meltRunIn: u(0.15))
                    break
                }
            }
            if let placed { out.append(placed) }
        }
        return out
    }

    private static func tributaryClear(_ line: [CGPoint], context: TributaryContext) -> Bool {
        let samples = MapGeometry.densify(line, spacing: 2)
        let margin: CGFloat = 3
        for p in samples {
            for ring in context.lakeRings where MapGeometry.polygonContains(p, ring) { return false }
            for sea in context.seaPolygons where MapGeometry.polygonContains(p, sea) { return false }
            for poly in context.avoidPolylines where MapGeometry.distanceToPolyline(p, poly) < margin { return false }
        }
        return true
    }

    // MARK: - 4 · Trek/road hand-feel waver (§07.3.7)

    /// Adds a very subtle single-octave waver to an authored road/trek polyline so
    /// long straight segments between the author's control points don't render
    /// ruler-straight. The waver bows each authored segment with a `sin` bump that
    /// is ZERO at both authored endpoints — so every authored vertex stays exact —
    /// and additionally tapers to zero within `pathWaverPinRadius` of any
    /// `pinnedVertices` (waypoint positions that sit mid-segment), keeping waypoints
    /// precisely on the drawn path. If the wavered path would enter water it is
    /// shrunk, and failing that the authored polyline is returned unchanged.
    static func waverPath(_ points: [CGPoint],
                          pinnedVertices: [CGPoint],
                          globalRoughness: Double,
                          milesPerMapUnit mpu: Double,
                          lakeRings: [[CGPoint]],
                          seaPolygons: [[CGPoint]],
                          rng: inout SplitMix64) -> [CGPoint] {
        guard points.count >= 2 else { return points }
        let g = max(0, globalRoughness)
        guard g > 0 else { return points }
        let ampMax = (mpu > 0 ? CGFloat(pathWaverMiles / mpu) : pathWaverUnitsFallback) * CGFloat(g)
        guard ampMax > 0 else { return points }

        // Waver the SMOOTHED drawn curve, not the raw control chords — otherwise the
        // subdivision would flatten the author's Catmull-Rom curvature and pull the
        // drawn path off waypoints that sit mid-segment. The renderer re-smooths this
        // dense polyline, which barely moves an already-smooth curve.
        let base = MapGeometry.catmullRomSampled(points)
        let n = base.count
        guard n >= 3 else { return points }

        let length = MapGeometry.polylineLength(base)
        let lengthMiles = mpu > 0 ? Double(length) * mpu : Double(length)
        let nodes = max(4, Int(lengthMiles / pathWaverWavelengthMiles))
        let noise = OctaveNoise(nodeCounts: [nodes], weights: [1], rng: &rng)

        let arc = cumulativeArc(base)
        let total = arc.last ?? 0
        guard total > 0 else { return points }
        let pinArc = max(Double(pathWaverPinRadius), total * 0.02)

        func build(_ amp: CGFloat) -> [CGPoint] {
            var out: [CGPoint] = []
            out.reserveCapacity(n)
            for i in 0..<n {
                let s = Double(arc[i]) / Double(total)
                // Endpoints and any mid-segment waypoint pin the waver to zero.
                var env = min(smoothRamp(Double(arc[i]) / pinArc),
                              smoothRamp(Double(total - arc[i]) / pinArc))
                for wp in pinnedVertices {
                    env = min(env, smoothRamp(Double(MapGeometry.dist(base[i], wp) / pathWaverPinRadius)))
                }
                let off = amp * CGFloat(env) * CGFloat(noise.value(s))
                let normal = localNormal(base, i)
                out.append(CGPoint(x: base[i].x + normal.dx * off,
                                   y: base[i].y + normal.dy * off))
            }
            return out
        }

        var amp = ampMax
        var result = build(amp)
        var iter = 0
        while iter < 3, pathCrossesWater(result, lakeRings: lakeRings, seaPolygons: seaPolygons) {
            amp *= 0.4
            if amp < 0.05 { return points }
            result = build(amp)
            iter += 1
        }
        if pathCrossesWater(result, lakeRings: lakeRings, seaPolygons: seaPolygons) { return points }
        return result
    }

    // MARK: - Shared helpers

    private static func pathCrossesWater(_ line: [CGPoint],
                                         lakeRings: [[CGPoint]],
                                         seaPolygons: [[CGPoint]]) -> Bool {
        let samples = MapGeometry.densify(line, spacing: MapValidator.pathSampleSpacing)
        for p in samples {
            for ring in lakeRings where MapGeometry.polygonContains(p, ring) { return true }
            for sea in seaPolygons where MapGeometry.polygonContains(p, sea) { return true }
        }
        return false
    }

    /// Nearest point on a polyline to `p` (its nearest segment's projection) —
    /// used to project a shoreside settlement onto the coast for a pin anchor.
    static func nearestPointOnPolyline(_ p: CGPoint, _ pts: [CGPoint]) -> CGPoint {
        guard pts.count > 1 else { return pts.first ?? p }
        var best = pts[0]
        var bestD = CGFloat.greatestFiniteMagnitude
        for i in 1..<pts.count {
            let a = pts[i - 1], b = pts[i]
            let dx = b.x - a.x, dy = b.y - a.y
            let len2 = dx * dx + dy * dy
            var t: CGFloat = 0
            if len2 > 0 { t = min(max(((p.x - a.x) * dx + (p.y - a.y) * dy) / len2, 0), 1) }
            let proj = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
            let d = MapGeometry.dist(p, proj)
            if d < bestD { bestD = d; best = proj }
        }
        return best
    }

    private static func nearestRangeCenter(_ p: CGPoint,
                                           ranges: [MapRegion.Range],
                                           maxMiles: Double,
                                           mpu: Double) -> CGPoint? {
        var best: CGPoint?
        var bestD = CGFloat.greatestFiniteMagnitude
        for r in ranges {
            let d = MapGeometry.dist(r.center, p)
            if d < bestD { bestD = d; best = r.center }
        }
        guard let best, Double(bestD) * mpu <= maxMiles else { return nil }
        return best
    }

    /// The left normal of the local tangent at sample `i` of a polyline.
    private static func localNormal(_ pts: [CGPoint], _ i: Int) -> CGVector {
        let n = pts.count
        let prev = pts[max(i - 1, 0)]
        let next = pts[min(i + 1, n - 1)]
        return CGVector(dx: next.x - prev.x, dy: next.y - prev.y).normalizedVector.normal
    }

    private static func pointAtFraction(_ pts: [CGPoint], _ f: CGFloat) -> CGPoint {
        guard pts.count > 1 else { return pts.first ?? .zero }
        let x = min(max(f, 0), 1) * CGFloat(pts.count - 1)
        let i = min(Int(x), pts.count - 2)
        let t = x - CGFloat(i)
        return CGPoint(x: pts[i].x + (pts[i + 1].x - pts[i].x) * t,
                       y: pts[i].y + (pts[i + 1].y - pts[i].y) * t)
    }

    private static func tangentAtFraction(_ pts: [CGPoint], _ f: CGFloat) -> CGVector {
        guard pts.count > 1 else { return CGVector(dx: 1, dy: 0) }
        let x = min(max(f, 0), 1) * CGFloat(pts.count - 1)
        let i = min(Int(x), pts.count - 2)
        return CGVector(dx: pts[i + 1].x - pts[i].x, dy: pts[i + 1].y - pts[i].y).normalizedVector
    }

    private static func cumulativeArc(_ pts: [CGPoint]) -> [CGFloat] {
        var arc = [CGFloat](repeating: 0, count: pts.count)
        for i in 1..<pts.count { arc[i] = arc[i - 1] + MapGeometry.dist(pts[i - 1], pts[i]) }
        return arc
    }

    private static func smoothRamp(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }
}
