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
        var scene = TerrainScene()
        scene.bounds = authoring.bounds

        var glyphs: [TerrainGlyph] = []
        var pins: [TerrainPin] = []

        // Pass 1 — water. Emit coast/lakes/rivers AND build the wetness mask that
        // pass-2 settlements resample away from, so `TerrainRenderer` never draws a
        // home standing in a lake, the sea, or a river (validation "over the region
        // set and its GENERATED placement", App Concept doc). Rivers are meandered
        // from their own substream here, so their generated centerlines are known
        // before any home is placed.
        var water = WaterMask()
        for region in authoring.regions {
            switch region {
            case .coast(let c):
                scene.coast = TerrainCoast(coastline: c.coastline, seaward: c.seaward, seaCorners: c.seaCorners)
                water.seaPolygon = MapGeometry.seaPolygon(coastline: c.coastline, seaCorners: c.seaCorners)
            case .lake(let l):
                scene.lakes.append(TerrainBlob(ring: l.ring))
                water.lakeRings.append(MapGeometry.catmullRomSampledClosed(l.ring))
            case .river(let r):
                var rng = MapRNG.substream(master: master, regionID: region.id)
                let river = makeRiver(r, authoring: authoring, rng: &rng)
                scene.rivers.append(river)
                water.riverLines.append((river.centerline, river.mouthWidth / 2))
            default:
                break
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
                scene.paths.append(TerrainPath(points: r.points, style: r.major ? .majorRoad : .road))

            case .trekPath(let t):
                scene.paths.append(TerrainPath(points: t.points, style: .trek))
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
        var seaPolygon: [CGPoint] = []
        var riverLines: [(line: [CGPoint], halfWidth: CGFloat)] = []

        /// True if `p` sits in any water fill, allowing `clearance` map units of
        /// dry margin (a home's footprint half-width).
        func isWet(_ p: CGPoint, clearance: CGFloat) -> Bool {
            for ring in lakeRings where MapGeometry.polygonContains(p, ring) { return true }
            if !seaPolygon.isEmpty, MapGeometry.polygonContains(p, seaPolygon) { return true }
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
            // Rejection-resample a dry site. Every attempt draws from THIS region's
            // own substream, so determinism holds: the same seed always consumes the
            // same draws and lands the home in the same dry spot — and a reroll can
            // never leave a home standing in water.
            var candidate: TerrainGlyph?
            for _ in 0..<12 {
                let dx = CGFloat.random(in: -16...16, using: &rng)
                let dy = CGFloat.random(in: -12...12, using: &rng)
                let w = CGFloat.random(in: 11...16, using: &rng)
                let h = w * CGFloat.random(in: 1.0...1.2, using: &rng)
                let base = CGPoint(x: s.site.x + dx, y: s.site.y + dy)
                candidate = TerrainGlyph(kind: .home, base: base, size: CGSize(width: w, height: h))
                if !water.isWet(base, clearance: w * 0.5) { break }
            }
            if let glyph = candidate { homes.append(glyph) }
        }
        return homes
    }

    // MARK: - Rivers (§07.3.3 / §07.5)

    private static func makeRiver(_ r: MapRegion.River,
                                  authoring: MapAuthoring,
                                  rng: inout SplitMix64) -> TerrainRiver {
        let centerline = meander(r.hint, amplitude: r.meanderAmplitude, rng: &rng)
        return TerrainRiver(centerline: centerline,
                            sourceWidth: r.sourceWidth,
                            mouthWidth: r.mouthWidth,
                            mouth: mouthKind(for: r, in: authoring))
    }

    /// Meanders a source→mouth hint: resample it, then push each interior sample
    /// perpendicular by an alternating, envelope-tapered offset (§07.5 "rivers
    /// meander: alternating curves"). Endpoints keep ZERO offset so the source
    /// stays in its range and the mouth stays in its lake/at the coast.
    private static func meander(_ hint: [CGPoint], amplitude: CGFloat, rng: inout SplitMix64) -> [CGPoint] {
        guard hint.count >= 2 else { return hint }
        let base = MapGeometry.catmullRomSampled(hint, perSegment: 8)
        let n = base.count
        guard n >= 3 else { return base }
        // Roughly one meander lobe per ~70 map units of length.
        let length = MapGeometry.polylineLength(base)
        let lobes = max(1.5, Double(length) / 70)
        let phase = Double.random(in: 0..<(2 * .pi), using: &rng)
        var out: [CGPoint] = []
        for i in 0..<n {
            let t = Double(i) / Double(n - 1)
            let envelope = sin(t * .pi)                              // 0 at both ends
            let wobble = 0.75 + 0.5 * Double.random(in: 0...1, using: &rng)
            let offsetMag = CGFloat(Double(amplitude) * envelope * wobble * sin(t * lobes * .pi + phase))
            // Local tangent → left normal.
            let prev = base[max(i - 1, 0)], next = base[min(i + 1, n - 1)]
            let tangent = CGVector(dx: next.x - prev.x, dy: next.y - prev.y).normalizedVector
            let normal = tangent.normal
            out.append(CGPoint(x: base[i].x + normal.dx * offsetMag,
                               y: base[i].y + normal.dy * offsetMag))
        }
        // Pin the exact endpoints (the sampled curve already ends on them, but
        // guard against any drift so the mouth/source stay put).
        out[0] = hint.first!
        out[n - 1] = hint.last!
        return out
    }

    /// Derives a river's mouth kind from what it TERMINATES in (§07.3.3): inside a
    /// lake ⇒ freshwater; at the coastline ⇒ sea; otherwise inland (the validator
    /// rejects inland, so a valid map never reaches that case).
    private static func mouthKind(for river: MapRegion.River, in authoring: MapAuthoring) -> TerrainRiver.Mouth {
        guard let mouth = river.hint.last else { return .inland }
        // Test against the SMOOTHED shapes the renderer fills / draws, matching the
        // validator, so the derived mouth kind can't disagree with the render.
        if authoring.lakes.contains(where: {
            MapGeometry.polygonContains(mouth, MapGeometry.catmullRomSampledClosed($0.ring))
        }) {
            return .freshwater
        }
        if let coast = authoring.coast,
           MapGeometry.distanceToPolyline(mouth, MapGeometry.catmullRomSampled(coast.coastline)) <= MapValidator.coastMouthToleranceUnits {
            return .sea
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
