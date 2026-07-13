//
//  MapGeometry.swift
//  JourneyTracker
//
//  Deterministic primitives shared by the P2 seeded map generator and its
//  build-time validators (KAN-19, epic KAN-16). Pure value math — no SwiftUI, no
//  wall-clock, no unseeded RNG. Everything here is a pure function of its inputs
//  so the generator can be a pure function of `(regions, seed)` (App Concept doc:
//  "Determinism is a hard requirement").
//
//  The Catmull-Rom sampling here mirrors `TerrainRenderer`'s private smoothing so
//  the arc length the scale is anchored on, and the "waypoint lies on the path"
//  validator, measure the SAME curve the renderer actually draws.
//

import CoreGraphics

// MARK: - Deterministic RNG (SplitMix64) + stable hashing

/// A SplitMix64 generator — fast, high-quality, and fully seed-determined. No
/// wall-clock, no global state: the same seed yields the same stream on every
/// device and launch (App Concept doc's hard determinism requirement).
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

enum MapRNG {
    /// A deterministic 64-bit hash of a string (FNV-1a). We CANNOT use
    /// `String.hashValue` — Swift randomizes it per process, which would reshuffle
    /// every map between launches. This is the stable region-key hash.
    static func stableHash(_ s: String) -> UInt64 {
        var h: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in s.utf8 { h = (h ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
        return h
    }

    /// A PER-REGION substream: a stream that depends only on `(master, regionID)`,
    /// independent of every other region. Editing region B's records never touches
    /// region A's stream — the property the tuning harness and future map edits
    /// rely on so one change doesn't reshuffle the whole map.
    static func substream(master: UInt64, regionID: String) -> SplitMix64 {
        let key = stableHash(regionID)
        // Mix master and key, then run the SplitMix64 finalizer once so nearby
        // keys/seeds produce fully decorrelated streams.
        var z = master ^ (key &* 0x9E37_79B9_7F4A_7C15)
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return SplitMix64(seed: z)
    }
}

// MARK: - Polyline / polygon math

enum MapGeometry {

    /// Samples a Catmull-Rom curve through `pts` into many points, matching
    /// `TerrainRenderer.sampledCurve` so measured arc length equals the drawn one.
    static func catmullRomSampled(_ pts: [CGPoint], perSegment: Int = 10) -> [CGPoint] {
        guard pts.count > 2 else { return pts }
        var out: [CGPoint] = []
        let n = pts.count
        for i in 0..<(n - 1) {
            let a = i > 0 ? pts[i - 1] : pts[i]
            let p1 = pts[i]
            let p2 = pts[i + 1]
            let d = i + 2 < n ? pts[i + 2] : pts[i + 1]
            let c1 = CGPoint(x: p1.x + (p2.x - a.x) / 6, y: p1.y + (p2.y - a.y) / 6)
            let c2 = CGPoint(x: p2.x - (d.x - p1.x) / 6, y: p2.y - (d.y - p1.y) / 6)
            for s in 0..<perSegment {
                let t = CGFloat(s) / CGFloat(perSegment)
                out.append(cubic(p1, c1, c2, p2, t))
            }
        }
        out.append(pts[n - 1])
        return out
    }

    /// Samples a CLOSED Catmull-Rom loop through `pts` — mirroring
    /// `TerrainRenderer.smoothedPath(_:closed: true)` exactly, so the polygon the
    /// validators test is the same bulged shape the renderer actually FILLS. Raw
    /// chords bow outward once smoothed, so validating the raw ring lets a path
    /// validate clean yet render through water (the P1 bug class). The returned
    /// ring is closed (its wrap segment back to `[0]` is included by the callers'
    /// point-in-polygon, which connects last→first).
    static func catmullRomSampledClosed(_ pts: [CGPoint], perSegment: Int = 12) -> [CGPoint] {
        guard pts.count > 2 else { return pts }
        let n = pts.count
        var out: [CGPoint] = []
        for i in 0..<n {
            let p0 = pts[(i - 1 + n) % n]
            let p1 = pts[i % n]
            let p2 = pts[(i + 1) % n]
            let p3 = pts[(i + 2) % n]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            for s in 0..<perSegment {
                let t = CGFloat(s) / CGFloat(perSegment)
                out.append(cubic(p1, c1, c2, p2, t))
            }
        }
        return out
    }

    /// Resamples a polyline to points spaced ≈`spacing` map units apart, so a
    /// distance test can't skip past a small feature between samples (a
    /// minimum-size lake must not slip between two coarse path samples).
    static func densify(_ pts: [CGPoint], spacing: CGFloat) -> [CGPoint] {
        guard pts.count > 1, spacing > 0 else { return pts }
        var out: [CGPoint] = [pts[0]]
        for i in 1..<pts.count {
            let a = pts[i - 1], b = pts[i]
            let segLen = dist(a, b)
            guard segLen > 0 else { continue }
            let steps = max(1, Int((segLen / spacing).rounded(.up)))
            for s in 1...steps {
                let t = CGFloat(s) / CGFloat(steps)
                out.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
            }
        }
        return out
    }

    private static func cubic(_ p0: CGPoint, _ c1: CGPoint, _ c2: CGPoint, _ p1: CGPoint, _ t: CGFloat) -> CGPoint {
        let mt = 1 - t
        let a = mt * mt * mt, b = 3 * mt * mt * t, c = 3 * mt * t * t, d = t * t * t
        return CGPoint(x: a * p0.x + b * c1.x + c * c2.x + d * p1.x,
                       y: a * p0.y + b * c1.y + c * c2.y + d * p1.y)
    }

    /// The closed SEA polygon, built exactly as `TerrainRenderer.seaBand(offset: 0)`:
    /// the smoothed coastline (open Catmull-Rom) closed out to the two seaward
    /// corners. A point inside it is in open water — the correct "on the ocean side"
    /// test (a nearest-vertex dot false-fails on a curving coast).
    static func seaPolygon(coastline: [CGPoint], seaCorners: [CGPoint]) -> [CGPoint] {
        guard coastline.count >= 2 else { return [] }
        var ring = catmullRomSampled(coastline)
        ring.append(contentsOf: seaCorners)
        return ring
    }

    /// Offsets each vertex of an (already sampled) coastline SEAWARD by `offset`,
    /// choosing the seaward side PER VERTEX so ocean depth bands follow the coast
    /// around corners instead of shearing into self-intersecting shards on a wrapped
    /// (L-shaped) sea (KAN-23 wrapped-coast fix). The seaward side is the one a small
    /// step off the vertex lands INSIDE `seaPoly` (the coast's fill polygon: sampled
    /// coastline + seaCorners); where that test is degenerate it falls back to the
    /// authored `seawardHint`. Pure — usable by the renderer and by tests.
    static func offsetSeaward(_ samples: [CGPoint], seaPoly: [CGPoint],
                              seawardHint: CGVector, offset: CGFloat) -> [CGPoint] {
        guard offset != 0, samples.count >= 2 else { return samples }
        let n = samples.count
        let hint = seawardHint.normalizedVector
        var out: [CGPoint] = []
        out.reserveCapacity(n)
        for i in 0..<n {
            let prev = samples[max(i - 1, 0)]
            let next = samples[min(i + 1, n - 1)]
            var nrm = CGVector(dx: next.x - prev.x, dy: next.y - prev.y).normalizedVector.normal
            if nrm.length == 0 { nrm = hint }
            let seg = max(dist(prev, next), 0.001)
            let eps = min(0.4, 0.2 * seg)
            let probe = CGPoint(x: samples[i].x + nrm.dx * eps, y: samples[i].y + nrm.dy * eps)
            var seaward = nrm
            if seaPoly.count >= 3 {
                if !polygonContains(probe, seaPoly) { seaward = CGVector(dx: -nrm.dx, dy: -nrm.dy) }
            } else if (nrm.dx * hint.dx + nrm.dy * hint.dy) < 0 {
                seaward = CGVector(dx: -nrm.dx, dy: -nrm.dy)
            }
            out.append(CGPoint(x: samples[i].x + seaward.dx * offset,
                               y: samples[i].y + seaward.dy * offset))
        }
        return out
    }

    /// Straight-segment arc length of a polyline in map units.
    static func polylineLength(_ pts: [CGPoint]) -> CGFloat {
        guard pts.count > 1 else { return 0 }
        var total: CGFloat = 0
        for i in 1..<pts.count { total += dist(pts[i - 1], pts[i]) }
        return total
    }

    /// Arc length of the SMOOTHED curve through `controls` — the length the trek
    /// path actually draws, and the anchor for miles-per-map-unit.
    static func smoothedLength(_ controls: [CGPoint]) -> CGFloat {
        polylineLength(catmullRomSampled(controls))
    }

    static func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    /// The point at `arcLength` map units along a polyline (linearly between
    /// vertices). Clamps to the ends. Used to place a marker / bracket a leg by
    /// real mileage on the SAMPLED trek curve (arc length ↔ mileage, App Concept
    /// doc). Pure — the camera's chapter framing reads it, never HealthKit.
    static func pointAtArcLength(_ pts: [CGPoint], arcLength: CGFloat) -> CGPoint {
        guard let first = pts.first else { return .zero }
        guard pts.count > 1, arcLength > 0 else { return first }
        var remaining = arcLength
        for i in 1..<pts.count {
            let seg = dist(pts[i - 1], pts[i])
            if seg <= 0 { continue }
            if remaining <= seg {
                let t = remaining / seg
                return CGPoint(x: pts[i - 1].x + (pts[i].x - pts[i - 1].x) * t,
                               y: pts[i - 1].y + (pts[i].y - pts[i - 1].y) * t)
            }
            remaining -= seg
        }
        return pts[pts.count - 1]
    }

    /// Shortest distance from `p` to a polyline (its nearest segment).
    static func distanceToPolyline(_ p: CGPoint, _ pts: [CGPoint]) -> CGFloat {
        guard pts.count > 1 else { return pts.first.map { dist($0, p) } ?? .infinity }
        var best = CGFloat.infinity
        for i in 1..<pts.count {
            best = min(best, distanceToSegment(p, pts[i - 1], pts[i]))
        }
        return best
    }

    static func distanceToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        guard len2 > 0 else { return dist(p, a) }
        var t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2
        t = min(max(t, 0), 1)
        return dist(p, CGPoint(x: a.x + t * dx, y: a.y + t * dy))
    }

    /// Cumulative arc length from the polyline's start to the point on it nearest
    /// `p` (used to locate a waypoint's mileage position along the trek path).
    static func arcLengthAtNearest(_ p: CGPoint, on pts: [CGPoint]) -> CGFloat {
        guard pts.count > 1 else { return 0 }
        var acc: CGFloat = 0
        var bestDist = CGFloat.infinity
        var bestArc: CGFloat = 0
        for i in 1..<pts.count {
            let a = pts[i - 1], b = pts[i]
            let dx = b.x - a.x, dy = b.y - a.y
            let len2 = dx * dx + dy * dy
            var t: CGFloat = 0
            if len2 > 0 { t = min(max(((p.x - a.x) * dx + (p.y - a.y) * dy) / len2, 0), 1) }
            let proj = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
            let dpr = dist(p, proj)
            if dpr < bestDist {
                bestDist = dpr
                bestArc = acc + t * sqrt(len2)
            }
            acc += sqrt(len2)
        }
        return bestArc
    }

    /// Even-odd point-in-polygon (ray cast). Used to test river mouths against
    /// lakes and paths against lake fills.
    static func polygonContains(_ p: CGPoint, _ ring: [CGPoint]) -> Bool {
        guard ring.count >= 3 else { return false }
        var inside = false
        var j = ring.count - 1
        for i in 0..<ring.count {
            let a = ring[i], b = ring[j]
            if (a.y > p.y) != (b.y > p.y) {
                let xCross = (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x
                if p.x < xCross { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    /// Signed |shoelace| area of a closed ring, in map units².
    static func polygonArea(_ ring: [CGPoint]) -> CGFloat {
        guard ring.count >= 3 else { return 0 }
        var sum: CGFloat = 0
        var j = ring.count - 1
        for i in 0..<ring.count {
            sum += (ring[j].x + ring[i].x) * (ring[j].y - ring[i].y)
            j = i
        }
        return abs(sum) / 2
    }

    /// Axis-aligned bounding rect of a set of points.
    static func boundingRect(_ pts: [CGPoint]) -> CGRect {
        guard let first = pts.first else { return .zero }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for p in pts {
            minX = min(minX, p.x); minY = min(minY, p.y)
            maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

// MARK: - Small vector conveniences

extension CGVector {
    var length: CGFloat { hypot(dx, dy) }
    var normalizedVector: CGVector {
        let l = length
        return l == 0 ? .zero : CGVector(dx: dx / l, dy: dy / l)
    }
    /// Left normal (perpendicular), for river-meander offsets and ocean-side tests.
    var normal: CGVector { CGVector(dx: -dy, dy: dx) }
}
