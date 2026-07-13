//
//  MapGenerator.swift
//  JourneyTracker
//
//  The P2 seeded scatter generator (KAN-19, epic KAN-16). A PURE function
//  `(MapAuthoring, seed) → TerrainScene`: the same regions + seed produce
//  identical placements on every device and launch (App Concept doc's hard
//  determinism requirement). No `Date()`, no unseeded RNG, no global state.
//
//  It EMITS the exact P1 value types (`TerrainScene`/`TerrainGlyph`/`TerrainBlob`/…)
//  so `TerrainRenderer` is unchanged. This is the deliberate, real generator — it
//  is NOT `TerrainSpecimenScene`'s P1-only scatter helpers dressed up (Rooster's
//  warning): per-region substreams, a glyphs-per-area density model, and derived
//  river mouths are all new here.
//
//  Determinism through DECORRELATED PER-REGION SUBSTREAMS: each region draws all
//  its jitter from a stream keyed by `(map seed, region id)`. Editing one region's
//  records never touches another region's stream, so the map doesn't reshuffle —
//  the property the tuning harness and future map edits depend on.
//

import CoreGraphics

enum MapGenerator {

    /// Global knobs the tuning harness applies OVER each region's authored scatter
    /// params. `seed` overrides the authored map seed (the "reroll seed" button).
    struct Tuning: Equatable {
        var seed: UInt64?
        var densityMultiplier: Double = 1
        var jitterMultiplier: Double = 1
        var featherMultiplier: Double = 1
        /// Global multiplier (0…1) over the KAN-23 organic pass — the coast/river
        /// octaves, tributary meander, and trek waver. 1 = full authored roughness,
        /// 0 = straight traced lines (a clean before/after in the harness).
        var roughnessMultiplier: Double = 1
    }

    enum GeneratorError: Error { case invalidAuthoring([MapViolation]) }

    /// Validates, then generates. Throws with ALL violations if the authoring is
    /// invalid — the generator refuses to emit a scene from a broken map.
    static func generate(_ authoring: MapAuthoring, tuning: Tuning = .init()) throws -> TerrainScene {
        let violations = MapValidator.validate(authoring)
        guard violations.isEmpty else { throw GeneratorError.invalidAuthoring(violations) }
        return generateUnchecked(authoring, tuning: tuning)
    }

    /// Generates without re-validating. Used by the harness, which validates once
    /// and then reruns generation live as knobs move (knobs never change validity).
    static func generateUnchecked(_ authoring: MapAuthoring, tuning: Tuning = .init()) -> TerrainScene {
        let master = tuning.seed ?? authoring.seed
        let mpu = authoring.milesPerMapUnit
        let roughG = tuning.roughnessMultiplier
        var scene = TerrainScene()
        scene.bounds = authoring.bounds

        var glyphs: [TerrainGlyph] = []
        var pins: [TerrainPin] = []

        // Anchors that hold the organically-displaced coastline back toward the
        // traced line (KAN-23): authored river sea-mouths (so a mouth still melts on
        // the DRAWN shore) and shoreside town projections (so a shoreside settlement
        // stays dry after the bays are carved). Computed from AUTHORING, before the
        // coast is displaced.
        let coastAnchors = coastPinAnchors(authoring, mpu: mpu)

        // Pass 1 — water. Emit coast/lakes/rivers AND build the wetness mask that
        // pass-2 settlements resample away from, so `TerrainRenderer` never draws a
        // home standing in a lake, the sea, or a river (validation "over the region
        // set and its GENERATED placement", App Concept doc). Everything downstream
        // validates against what is actually DRAWN — the displaced coast and the
        // meandered centerlines — never the pre-noise authoring (KAN-19/20 lesson).
        var water = WaterMask()

        // 1 · Displace every coastline UP FRONT. Each coast's displacement is a pure
        // function of its OWN substream + authoring anchors, so this is
        // order-independent — and it lets the river meander and the tributaries below
        // avoid the DRAWN sea, not the traced line.
        for region in authoring.regions {
            guard case .coast(let c) = region else { continue }
            var rng = MapRNG.substream(master: master, regionID: region.id)
            let displaced = MapOrganicDetail.displaceCoastline(
                c.coastline, seaward: c.seaward,
                roughness: c.roughness, globalRoughness: roughG,
                milesPerMapUnit: mpu, anchors: coastAnchors, rng: &rng)
            scene.coasts.append(TerrainCoast(coastline: displaced, seaward: c.seaward, seaCorners: c.seaCorners))
            water.seaPolygons.append(MapGeometry.seaPolygon(coastline: displaced, seaCorners: c.seaCorners))
        }
        let displacedSeas = water.seaPolygons.filter { $0.count >= 3 }

        // 2 · Lakes (smoothed rings the renderer fills).
        let lakeRings = authoring.lakes.map { MapGeometry.catmullRomSampledClosed($0.ring) }
        for l in authoring.lakes { scene.lakes.append(TerrainBlob(ring: l.ring)) }
        water.lakeRings = lakeRings

        // 3 · Meander every MAIN river first, water-checked against the DRAWN sea/lakes
        // (its own mouth's approach into its receiver is excluded). Carry each river's
        // substream forward so its tributaries resume the exact same stream.
        struct MainRiver { let region: MapRegion.River; var rng: SplitMix64; let river: TerrainRiver }
        var mains: [MainRiver] = []
        for region in authoring.regions {
            guard case .river(let r) = region else { continue }
            var rng = MapRNG.substream(master: master, regionID: region.id)
            let mouth = mouthKind(for: r, in: authoring)
            let receiver = receiverPolygon(for: r, mouth: mouth, seas: displacedSeas, lakeRings: lakeRings)
            let centerline = MapOrganicDetail.meanderRiver(
                r.hint, amplitude: r.meanderAmplitude, globalRoughness: roughG,
                avoidSeas: displacedSeas, avoidLakes: lakeRings, receiver: receiver, rng: &rng)
            mains.append(MainRiver(region: r, rng: rng,
                                   river: TerrainRiver(centerline: centerline,
                                                       sourceWidth: r.sourceWidth,
                                                       mouthWidth: r.mouthWidth, mouth: mouth)))
        }

        // 4 · Emit mains + their tributaries. Tributaries avoid the DRAWN sea, lakes,
        // the trek/roads, and the OTHER mains' MEANDERED (drawn) centerlines.
        let pathPolylines: [[CGPoint]] = authoring.regions.compactMap { region in
            if case .trekPath(let t) = region { return MapGeometry.catmullRomSampled(t.points) }
            if case .road(let rd) = region { return MapGeometry.catmullRomSampled(rd.points) }
            return nil
        }
        let ranges: [MapRegion.Range] = authoring.regions.compactMap {
            if case .range(let rg) = $0 { return rg }; return nil
        }
        for mr in mains {
            scene.rivers.append(mr.river)
            water.riverLines.append((mr.river.centerline, mr.river.mouthWidth / 2))
            var rng = mr.rng
            let siblingLines = mains.filter { $0.region.id != mr.region.id }.map { $0.river.centerline }
            let context = MapOrganicDetail.TributaryContext(
                lakeRings: lakeRings,
                seaPolygons: displacedSeas,
                avoidPolylines: pathPolylines + siblingLines,
                ranges: ranges,
                milesPerMapUnit: mpu)
            let tributaries = MapOrganicDetail.tributaries(
                hasTributaries: mr.region.tributaries, mainCenterline: mr.river.centerline,
                mainSourceWidth: mr.region.sourceWidth, mainMouthWidth: mr.region.mouthWidth,
                globalRoughness: roughG, context: context, rng: &rng)
            for tr in tributaries {
                scene.rivers.append(tr)
                water.riverLines.append((tr.centerline, tr.mouthWidth / 2))
            }
        }

        // Pass 2 — land features + settlements. Every region draws only from its own
        // id-keyed substream, so iteration order never affects placement.
        for region in authoring.regions {
            var rng = MapRNG.substream(master: master, regionID: region.id)
            switch region {
            case .coast, .lake, .river:
                break // emitted in pass 1

            case .range(let r):
                glyphs += makeRange(r, tuning: tuning, rng: &rng)

            case .forest(let f):
                glyphs += makeForest(f, tuning: tuning, rng: &rng)

            case .groundCover(let g):
                switch g.kind {
                case .plains:
                    scene.plains.append(TerrainPlains(wash: TerrainBlob(ring: g.ring)))
                    glyphs += makeTufts(g, tuning: tuning, rng: &rng)
                case .dunes:
                    glyphs += makeDunes(g, tuning: tuning, rng: &rng)
                case .marsh:
                    scene.marshes.append(makeMarsh(g, rng: &rng))
                }

            case .settlement(let s):
                glyphs += makeVillage(s, water: water, rng: &rng)

            case .road(let r):
                let pts = MapOrganicDetail.waverPath(r.points, pinnedVertices: [],
                                                     globalRoughness: roughG, milesPerMapUnit: mpu,
                                                     lakeRings: water.lakeRings, seaPolygons: water.seaPolygons,
                                                     rng: &rng)
                scene.paths.append(TerrainPath(points: pts, style: r.major ? .majorRoad : .road))

            case .trekPath(let t):
                // Waypoints sit ON the drawn trek (a validator), so pin the waver to
                // zero at each waypoint position — the traced spine still wavers
                // between them so long straight legs don't render ruler-straight.
                let pts = MapOrganicDetail.waverPath(t.points, pinnedVertices: authoring.waypoints.map(\.position),
                                                     globalRoughness: roughG, milesPerMapUnit: mpu,
                                                     lakeRings: water.lakeRings, seaPolygons: water.seaPolygons,
                                                     rng: &rng)
                scene.paths.append(TerrainPath(points: pts, style: .trek))
            }
        }

        // Waypoint pins (§07.6 — always last). Authored positions already lie on
        // the trek path (validated), so each teardrop tip anchors to the curve.
        for wp in authoring.waypoints {
            pins.append(TerrainPin(position: wp.position, name: wp.name,
                                   accentToken: wp.accentToken,
                                   state: pinState(wp.state), isDestination: wp.isDestination))
        }

        scene.glyphs = glyphs
        scene.pins = pins
        return scene
    }

    /// Where water is, for keeping generated homes out of it. Lake rings and the
    /// sea polygon are the SMOOTHED shapes the renderer fills; river lines are the
    /// generated (meandered) centerlines with a bank half-width.
    private struct WaterMask {
        var lakeRings: [[CGPoint]] = []
        var seaPolygons: [[CGPoint]] = []
        var riverLines: [(line: [CGPoint], halfWidth: CGFloat)] = []

        /// True if `p` sits in any water fill, allowing `clearance` map units of
        /// dry margin (a home's footprint half-width).
        func isWet(_ p: CGPoint, clearance: CGFloat) -> Bool {
            for ring in lakeRings where MapGeometry.polygonContains(p, ring) { return true }
            for sea in seaPolygons where MapGeometry.polygonContains(p, sea) { return true }
            for r in riverLines where MapGeometry.distanceToPolyline(p, r.line) <= r.halfWidth + clearance { return true }
            return false
        }
    }

    // MARK: - Per-kind scatter defaults (glyphs per map-unit²)

    /// Per-kind default densities (glyphs per map-unit²), calibrated to the APPROVED
    /// P1 specimen's on-screen density so any region renders at the proven look and
    /// scales naturally with its own area (a bigger forest → proportionally more
    /// trees, same visual density).
    private enum Density {
        static let range = 0.00134   // P1: ~40 peaks over ~29,800 units²
        static let forest = 0.0038   // P1: ~46 conifers over ~13,500 units²
        static let tufts = 0.00097   // P1: ~40 tufts over ~41,500 units² (texture, not a forest)
        static let dunes = 0.0024    // P1: ~6 dunes over ~2,500 units²
    }

    // MARK: - Ranges (§07.3.1)

    private static func makeRange(_ r: MapRegion.Range,
                                  tuning: Tuning,
                                  rng: inout SplitMix64) -> [TerrainGlyph] {
        let params = r.scatter ?? ScatterParams()
        let density = (params.density ?? Density.range) * tuning.densityMultiplier
        let area = Double.pi * Double(r.halfLength) * Double(r.halfWidth)
        let count = max(0, Int((density * area).rounded()))

        var peaks = scatterOriented(kind: .mountain, count: count,
                                    center: r.center, halfA: r.halfLength, halfB: r.halfWidth,
                                    axisAngle: r.axisAngle,
                                    minHeight: 16, maxHeight: 52, widthRatio: 0.95,
                                    feather: params.feather * tuning.featherMultiplier,
                                    jitter: params.jitter * tuning.jitterMultiplier,
                                    rng: &rng)
        // Snow caps on the tallest few peaks only (§07.3.1 — the exception). Tie
        // heights break by index so the choice is stable across stdlib versions
        // (Swift's `sort` isn't guaranteed stable).
        let capCount = r.snowCaps ?? max(2, count / 12)
        let tallest = Set(peaks.enumerated()
            .sorted { a, b in
                a.element.size.height != b.element.size.height
                    ? a.element.size.height > b.element.size.height
                    : a.offset < b.offset
            }
            .prefix(capCount).map(\.offset))
        for i in peaks.indices { peaks[i].snowCap = tallest.contains(i) }
        return peaks
    }

    // MARK: - Forests (§07.3.2)

    private static func makeForest(_ f: MapRegion.Forest,
                                   tuning: Tuning,
                                   rng: inout SplitMix64) -> [TerrainGlyph] {
        let params = f.scatter ?? ScatterParams()
        let density = (params.density ?? Density.forest) * tuning.densityMultiplier
        let count = max(0, Int((density * Double.pi * Double(f.rx) * Double(f.ry)).rounded()))
        var trees = scatterOriented(kind: .conifer, count: count,
                                    center: f.center, halfA: f.rx, halfB: f.ry, axisAngle: 0,
                                    minHeight: 10, maxHeight: 26, widthRatio: 0.68,
                                    feather: params.feather * tuning.featherMultiplier,
                                    jitter: params.jitter * tuning.jitterMultiplier,
                                    rng: &rng)
        if f.autumn { for i in trees.indices { trees[i].autumn = true } }
        return trees
    }

    // MARK: - Ground cover (§07.3.6)

    private static func makeTufts(_ g: MapRegion.GroundCover,
                                  tuning: Tuning,
                                  rng: inout SplitMix64) -> [TerrainGlyph] {
        let params = g.scatter ?? ScatterParams(feather: 0.3)
        let bb = MapGeometry.boundingRect(g.ring)
        let density = (params.density ?? Density.tufts) * tuning.densityMultiplier
        let count = max(0, Int((density * Double(bb.width * bb.height) * 0.7).rounded()))
        var out: [TerrainGlyph] = []
        for _ in 0..<count {
            let p = CGPoint(x: bb.minX + CGFloat.random(in: 0...bb.width, using: &rng),
                            y: bb.minY + CGFloat.random(in: 0...bb.height, using: &rng))
            guard MapGeometry.polygonContains(p, g.ring) else { continue }
            let h = CGFloat.random(in: 5...9, using: &rng)
            out.append(TerrainGlyph(kind: .grassTuft, base: p, size: CGSize(width: h, height: h)))
        }
        return out
    }

    private static func makeDunes(_ g: MapRegion.GroundCover,
                                  tuning: Tuning,
                                  rng: inout SplitMix64) -> [TerrainGlyph] {
        let params = g.scatter ?? ScatterParams()
        let bb = MapGeometry.boundingRect(g.ring)
        let density = (params.density ?? Density.dunes) * tuning.densityMultiplier
        let count = max(0, Int((density * Double(bb.width * bb.height) * 0.7).rounded()))
        var out: [TerrainGlyph] = []
        for _ in 0..<count {
            let p = CGPoint(x: bb.minX + CGFloat.random(in: 0...bb.width, using: &rng),
                            y: bb.minY + CGFloat.random(in: 0...bb.height, using: &rng))
            guard MapGeometry.polygonContains(p, g.ring) else { continue }
            let w = CGFloat.random(in: 26...42, using: &rng)
            let h = CGFloat.random(in: 9...15, using: &rng)
            out.append(TerrainGlyph(kind: .dune, base: p, size: CGSize(width: w, height: h)))
        }
        return out
    }

    private static func makeMarsh(_ g: MapRegion.GroundCover, rng: inout SplitMix64) -> TerrainMarsh {
        let bb = MapGeometry.boundingRect(g.ring)
        var glints: [CGPoint] = []
        var reeds: [TerrainMarsh.Reed] = []
        for _ in 0..<5 {
            glints.append(randomInsideRing(g.ring, bb: bb, rng: &rng))
        }
        for _ in 0..<6 {
            let base = randomInsideRing(g.ring, bb: bb, rng: &rng)
            let lean = CGFloat.random(in: -3...3, using: &rng)
            reeds.append(TerrainMarsh.Reed(base: base,
                                           tip: CGPoint(x: base.x + lean,
                                                        y: base.y - CGFloat.random(in: 8...14, using: &rng))))
        }
        return TerrainMarsh(body: TerrainBlob(ring: g.ring), glints: glints, reeds: reeds)
    }

    // MARK: - Settlements (§07.3.8)

    private static func makeVillage(_ s: MapRegion.Settlement,
                                    water: WaterMask,
                                    rng: inout SplitMix64) -> [TerrainGlyph] {
        let count = s.homeCount ?? Int.random(in: 3...5, using: &rng)
        var homes: [TerrainGlyph] = []
        for _ in 0..<count {
            // Rejection-resample a DRY site. Every attempt draws from THIS region's
            // own substream, so determinism holds: the same seed always consumes the
            // same draws and lands the home in the same dry spot. Append ONLY on a dry
            // break — never the last (still-wet) candidate. If all 12 draws land in
            // water (likelier now that tributaries thread through settlements), fall
            // back to the site itself if it's dry, else DROP the home rather than
            // plant it in water.
            var placed: TerrainGlyph?
            for _ in 0..<12 {
                let dx = CGFloat.random(in: -16...16, using: &rng)
                let dy = CGFloat.random(in: -12...12, using: &rng)
                let w = CGFloat.random(in: 11...16, using: &rng)
                let h = w * CGFloat.random(in: 1.0...1.2, using: &rng)
                let base = CGPoint(x: s.site.x + dx, y: s.site.y + dy)
                if !water.isWet(base, clearance: w * 0.5) {
                    placed = TerrainGlyph(kind: .home, base: base, size: CGSize(width: w, height: h))
                    break
                }
            }
            if let placed {
                homes.append(placed)
            } else {
                let w = CGFloat.random(in: 11...16, using: &rng)
                let h = w * CGFloat.random(in: 1.0...1.2, using: &rng)
                if !water.isWet(s.site, clearance: w * 0.5) {
                    homes.append(TerrainGlyph(kind: .home, base: s.site, size: CGSize(width: w, height: h)))
                }
            }
        }
        return homes
    }

    // MARK: - Rivers (§07.3.3 / §07.5)

    /// The specific DRAWN water polygon a river's mouth terminates in — the lake ring
    /// or sea polygon whose fill the mouth enters — so the meander water-check can
    /// EXCLUDE that legitimate approach while still catching a mid-course excursion
    /// into any other water body (KAN-23). `nil` for offMap/inland mouths (no on-map
    /// receiver).
    private static func receiverPolygon(for r: MapRegion.River,
                                        mouth: TerrainRiver.Mouth,
                                        seas: [[CGPoint]],
                                        lakeRings: [[CGPoint]]) -> [CGPoint]? {
        guard let end = r.hint.last else { return nil }
        switch mouth {
        case .freshwater:
            return lakeRings.first { MapGeometry.polygonContains(end, $0) }
        case .sea:
            // The mouth may sit just landward of the coast (within tolerance), so pick
            // the nearest sea polygon rather than requiring containment.
            return seas.min {
                MapGeometry.distanceToPolyline(end, $0) < MapGeometry.distanceToPolyline(end, $1)
            }
        case .confluence, .inland, .offMap:
            return nil
        }
    }

    /// Map-unit distance from an authored coast within which a settlement counts as
    /// "shoreside" and pins the displaced coast in front of it (KAN-23). Kept small
    /// and independent of the now-40-mile settlement water cap: a town 30 mi inland
    /// is not a reason to freeze the coast.
    private static let coastalSettlementPinMiles = 4.0

    /// Map-unit distance from a trek/road within which the coast is pinned back to its
    /// traced line, so organic displacement can NEVER carve into a path corridor and
    /// leave the (invisible-to-validators) authored path underwater (KAN-23, Rooster
    /// finding 2). Covers the full wander budget plus a margin.
    private static let pathCoastPinMiles = MapOrganicDetail.coastMaxWanderMiles + 1.5

    /// Points that pin the displaced coastline back toward the traced line: authored
    /// river sea-mouths, shoreside settlement shore-projections, AND stretches of coast
    /// adjacent to the trek/roads (KAN-23). Handles any number of coasts.
    private static func coastPinAnchors(_ a: MapAuthoring, mpu: Double) -> [CGPoint] {
        let smoothCoasts = a.coasts.map { MapGeometry.catmullRomSampled($0.coastline) }
        guard !smoothCoasts.isEmpty else { return [] }
        var anchors: [CGPoint] = []
        for r in a.rivers {
            guard let mouth = r.hint.last else { continue }
            for shore in smoothCoasts where MapGeometry.distanceToPolyline(mouth, shore) <= MapValidator.coastMouthToleranceUnits {
                anchors.append(mouth)
                break
            }
        }
        guard mpu > 0 else { return anchors }
        for region in a.regions {
            switch region {
            case .settlement(let s):
                for shore in smoothCoasts {
                    let np = MapOrganicDetail.nearestPointOnPolyline(s.site, shore)
                    if Double(MapGeometry.dist(s.site, np)) * mpu <= coastalSettlementPinMiles {
                        anchors.append(np)
                    }
                }
            case .trekPath(let t):
                anchors += pathCoastAnchors(t.points, coasts: smoothCoasts, mpu: mpu)
            case .road(let rd):
                anchors += pathCoastAnchors(rd.points, coasts: smoothCoasts, mpu: mpu)
            default:
                break
            }
        }
        return anchors
    }

    /// Shore projections of a path's stretches that run within `pathCoastPinMiles` of
    /// a coast — pin points that keep the displaced coast out of the path corridor.
    private static func pathCoastAnchors(_ points: [CGPoint], coasts: [[CGPoint]], mpu: Double) -> [CGPoint] {
        var out: [CGPoint] = []
        // Sample the drawn path coarsely (one pin per anchor radius is plenty).
        let sampled = MapGeometry.densify(MapGeometry.catmullRomSampled(points),
                                          spacing: MapOrganicDetail.coastAnchorPinRadius)
        for p in sampled {
            for shore in coasts {
                let np = MapOrganicDetail.nearestPointOnPolyline(p, shore)
                if Double(MapGeometry.dist(p, np)) * mpu <= pathCoastPinMiles {
                    out.append(np)
                }
            }
        }
        return out
    }

    /// Derives a river's mouth kind from what it TERMINATES in (§07.3.3, KAN-23):
    /// inside a lake ⇒ freshwater; at a coastline ⇒ sea; outside the authored bounds
    /// ⇒ offMap (drains to an off-map sea/basin — the renderer clips); otherwise
    /// inland (the validator rejects a mid-land mouth, so a valid map never renders
    /// that case). Tested against ALL coasts.
    private static func mouthKind(for river: MapRegion.River, in authoring: MapAuthoring) -> TerrainRiver.Mouth {
        guard let mouth = river.hint.last else { return .inland }
        // Test against the SMOOTHED shapes the renderer fills / draws, matching the
        // validator, so the derived mouth kind can't disagree with the render.
        if authoring.lakes.contains(where: {
            MapGeometry.polygonContains(mouth, MapGeometry.catmullRomSampledClosed($0.ring))
        }) {
            return .freshwater
        }
        if authoring.coasts.contains(where: {
            MapGeometry.distanceToPolyline(mouth, MapGeometry.catmullRomSampled($0.coastline)) <= MapValidator.coastMouthToleranceUnits
        }) {
            return .sea
        }
        if !authoring.bounds.contains(mouth) {
            return .offMap
        }
        return .inland
    }

    // MARK: - Core scatter (§07.4): jittered position + size, center-dense / rim-sparse

    /// Scatters `count` glyphs across an oriented ellipse. `halfA` runs along
    /// `axisAngle`, `halfB` perpendicular. Center-dense via `pow(u, 1.5)`; feather
    /// culls with rising probability toward the rim (a mass fades, never stops);
    /// jitter controls per-glyph size spread + a small positional dither (§07.4's
    /// "jitter position AND size").
    private static func scatterOriented(kind: TerrainGlyphKind,
                                        count: Int,
                                        center: CGPoint,
                                        halfA: CGFloat, halfB: CGFloat,
                                        axisAngle: CGFloat,
                                        minHeight: CGFloat, maxHeight: CGFloat,
                                        widthRatio: CGFloat,
                                        feather: Double,
                                        jitter: Double,
                                        rng: inout SplitMix64) -> [TerrainGlyph] {
        var out: [TerrainGlyph] = []
        let ca = cos(axisAngle), sa = sin(axisAngle)
        let hMid = (minHeight + maxHeight) / 2
        let hSpread = (maxHeight - minHeight) / 2 * CGFloat(max(0, jitter))
        let dither = CGFloat(max(0, jitter)) * min(halfA, halfB) * 0.06
        for _ in 0..<count {
            let angle = Double.random(in: 0..<(2 * .pi), using: &rng)
            let rNorm = pow(Double.random(in: 0...1, using: &rng), 1.5) // center-dense
            if Double.random(in: 0...1, using: &rng) < feather * rNorm { continue } // rim cull
            // Position in the ellipse's local frame, then rotate into the scene.
            let lx = CGFloat(cos(angle)) * halfA * CGFloat(rNorm)
            let ly = CGFloat(sin(angle)) * halfB * CGFloat(rNorm)
            var px = center.x + lx * ca - ly * sa
            var py = center.y + lx * sa + ly * ca
            if dither > 0 {
                px += CGFloat.random(in: -dither...dither, using: &rng)
                py += CGFloat.random(in: -dither...dither, using: &rng)
            }
            let sizeFactor = CGFloat(1.0 - 0.5 * rNorm) // taper toward the rim
            let height = max(minHeight * 0.5,
                             (hMid + CGFloat.random(in: -hSpread...hSpread, using: &rng)) * sizeFactor)
            let width = height * widthRatio * (1 + CGFloat.random(in: -0.1...0.1, using: &rng))
            out.append(TerrainGlyph(kind: kind, base: CGPoint(x: px, y: py),
                                    size: CGSize(width: width, height: height)))
        }
        return out
    }

    private static func randomInsideRing(_ ring: [CGPoint], bb: CGRect, rng: inout SplitMix64) -> CGPoint {
        for _ in 0..<12 {
            let p = CGPoint(x: bb.minX + CGFloat.random(in: 0...bb.width, using: &rng),
                            y: bb.minY + CGFloat.random(in: 0...bb.height, using: &rng))
            if MapGeometry.polygonContains(p, ring) { return p }
        }
        return CGPoint(x: bb.midX, y: bb.midY)
    }

    private static func pinState(_ s: MapWaypoint.State) -> TerrainPin.State {
        switch s {
        case .reached: return .reached
        case .next: return .next
        case .upcoming: return .upcoming
        }
    }
}
