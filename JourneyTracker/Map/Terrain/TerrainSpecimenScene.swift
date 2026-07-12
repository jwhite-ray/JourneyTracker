//
//  TerrainSpecimenScene.swift
//  JourneyTracker
//
//  The KAN-18 (P1) look-proof: ONE hand-authored scene exercising every terrain
//  element, so the team can answer "does faceted terrain on parchment look cool
//  on a phone?" before P2 builds the real region generator.
//
//  This is deliberately a specimen, not the generator. Regions are hand-placed
//  here — allowed at P1 ONLY (App Concept doc, phase P1) — but placements still
//  obey the §07.4 scatter contract: positions AND sizes are jittered, masses are
//  center-dense / rim-sparse (feathered), density is moderate, nothing sits on a
//  grid. Jitter comes from a small, LOCAL seeded RNG (`SpecimenRNG`) so the proof
//  is stable between launches; it is explicitly NOT the P2 deterministic
//  `(regions, seed)` generator, just a way to author a believable one-off.
//
//  All names are original JourneyTracker proper nouns (Ember Spire, Thistledown,
//  Crosswater) — no real-world IP.
//

import CoreGraphics

/// A tiny SplitMix64 generator — local to the specimen, seeded, no wall-clock, so
/// the hand-placed jitter is identical every launch. (The P2 generator is a
/// separate, deterministic `(regions, seed)` function; this is not it.)
struct SpecimenRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

enum TerrainSpecimenScene {

    /// The authored canvas — roughly one iPhone screen of logical space.
    static let canvas = CGRect(x: 0, y: 0, width: 390, height: 700)

    static func make() -> TerrainScene {
        var rng = SpecimenRNG(seed: 0xE3B_5CA7)
        var scene = TerrainScene()
        scene.bounds = canvas

        // 1 · Ocean / coast down the right edge, with bays (curving inland) and
        // headlands (curving seaward) — never a straight edge (§07.5).
        scene.coast = TerrainCoast(
            coastline: [
                CGPoint(x: 325, y: -12), CGPoint(x: 332, y: 60), CGPoint(x: 300, y: 132),
                CGPoint(x: 348, y: 202), CGPoint(x: 314, y: 286), CGPoint(x: 356, y: 360),
                CGPoint(x: 305, y: 440), CGPoint(x: 342, y: 520), CGPoint(x: 322, y: 612),
                CGPoint(x: 330, y: 712)
            ],
            seaward: CGVector(dx: 1, dy: 0),
            seaCorners: [CGPoint(x: 420, y: 720), CGPoint(x: 420, y: -20)]
        )

        // 2 · Ground cover.
        // Plains wash across the lower-central land.
        scene.plains = [
            TerrainPlains(wash: TerrainBlob(ring: [
                CGPoint(x: 55, y: 400), CGPoint(x: 150, y: 372), CGPoint(x: 260, y: 392),
                CGPoint(x: 300, y: 470), CGPoint(x: 280, y: 580), CGPoint(x: 190, y: 660),
                CGPoint(x: 90, y: 640), CGPoint(x: 48, y: 520)
            ]))
        ]
        // Grass tufts scattered over the plains (texture, not a forest — §07.3.6).
        let tufts = scatter(kind: .grassTuft, center: CGPoint(x: 165, y: 520),
                            rx: 110, ry: 120, count: 40,
                            minHeight: 5, maxHeight: 9, widthRatio: 1.0,
                            feather: 0.35, rng: &rng)

        // A small dune patch, lower-left.
        let dunes = scatterDunes(center: CGPoint(x: 78, y: 636), rx: 40, ry: 20,
                                 count: 6, rng: &rng)

        // A small marsh next to the lake/river.
        scene.marshes = [makeMarsh(center: CGPoint(x: 118, y: 548), rng: &rng)]

        // 3 · A lake, shoreline rim traced by the renderer.
        scene.lakes = [
            TerrainBlob(ring: [
                CGPoint(x: 150, y: 462), CGPoint(x: 188, y: 452), CGPoint(x: 214, y: 478),
                CGPoint(x: 206, y: 512), CGPoint(x: 170, y: 526), CGPoint(x: 138, y: 502)
            ])
        ]

        // 4 · Two rivers. One meanders from the range into the lake; one ends
        // abruptly AT the coastline (§07.5 — never mid-land, never under the sea).
        scene.rivers = [
            TerrainRiver(centerline: [
                CGPoint(x: 150, y: 196), CGPoint(x: 176, y: 256), CGPoint(x: 134, y: 306),
                CGPoint(x: 178, y: 360), CGPoint(x: 150, y: 410), CGPoint(x: 172, y: 462)
            ], sourceWidth: 5, mouthWidth: 11),
            TerrainRiver(centerline: [
                CGPoint(x: 214, y: 178), CGPoint(x: 246, y: 240), CGPoint(x: 220, y: 300),
                CGPoint(x: 262, y: 360), CGPoint(x: 244, y: 412), CGPoint(x: 296, y: 440)
            ], sourceWidth: 5, mouthWidth: 12)
        ]

        // 5 · Forests — a big one and a smaller one, both feathered masses.
        let forest1 = scatter(kind: .conifer, center: CGPoint(x: 92, y: 430),
                              rx: 74, ry: 58, count: 46,
                              minHeight: 10, maxHeight: 26, widthRatio: 0.68,
                              feather: 0.5, rng: &rng)
        let forest2 = scatter(kind: .conifer, center: CGPoint(x: 252, y: 566),
                              rx: 46, ry: 36, count: 24,
                              minHeight: 10, maxHeight: 22, widthRatio: 0.68,
                              feather: 0.5, rng: &rng)

        // 6 · Mountain range — ~30 jittered peaks, snow on the tallest four.
        let mountains = scatter(kind: .mountain, center: CGPoint(x: 152, y: 178),
                                rx: 128, ry: 74, count: 40,
                                minHeight: 16, maxHeight: 52, widthRatio: 0.95,
                                feather: 0.45, rng: &rng)
        let cappedMountains = capTallest(mountains, count: 4)

        // 7 · The dot-dash trek path, staying on land, meandering to the summit.
        // It starts at the southern village (by the lake), swings WEST to clear the
        // lake fill with margin (the smoothed Catmull-Rom leg stays x < 127 through
        // the lake's y-band of 452–526, ≥11pt west of the lake's min x = 138), then
        // climbs to Ember Spire. It never crosses the lake or the ocean (§07.5).
        scene.paths = [
            TerrainPath(points: [
                CGPoint(x: 150, y: 566), CGPoint(x: 120, y: 520), CGPoint(x: 104, y: 452),
                CGPoint(x: 126, y: 384), CGPoint(x: 150, y: 312), CGPoint(x: 140, y: 240),
                CGPoint(x: 158, y: 176), CGPoint(x: 160, y: 150)
            ], style: .trek)
        ]

        // 8 · Two villages, each a tight cluster placed next to water (§07.5).
        // Village 1 hugs the lake's east/SE shore; village 2 sits just south of the
        // lake's south shore — both genuinely by water, neither overlapping the
        // lake fill (checked against the fixed seed).
        let village1 = clusterHomes(center: CGPoint(x: 248, y: 470), count: 4, rng: &rng)   // lake SE shore
        let village2 = clusterHomes(center: CGPoint(x: 155, y: 565), count: 3, rng: &rng)   // lake south shore

        // Assemble all point-anchored glyphs into one bag; the renderer buckets
        // them into their §07.6 draw stages by kind.
        scene.glyphs = tufts + dunes + forest1 + forest2 + cappedMountains + village1 + village2

        // 9 · Waypoint pins — original names only. The three exercise all §08
        // marker states: Thistledown (the reached start, at the southern village
        // by the lake), Crosswater (the single "next" — the only pin whose Cinzel
        // name chip is always shown, plus its accent/reward ring), and Ember Spire
        // (further-unreached — the dashed 60% outline).
        scene.pins = [
            TerrainPin(position: CGPoint(x: 155, y: 556), name: "Thistledown",
                       accentToken: DesignToken.accentPrimary, state: .reached),
            TerrainPin(position: CGPoint(x: 178, y: 452), name: "Crosswater",
                       accentToken: DesignToken.accentSecondary, state: .next),
            TerrainPin(position: CGPoint(x: 160, y: 150), name: "Ember Spire",
                       accentToken: DesignToken.reward, state: .upcoming)
        ]

        return scene
    }

    // MARK: - Scatter (§07.4): jittered position + size, center-dense, rim-sparse

    private static func scatter(kind: TerrainGlyphKind,
                                center: CGPoint,
                                rx: CGFloat, ry: CGFloat,
                                count: Int,
                                minHeight: CGFloat, maxHeight: CGFloat,
                                widthRatio: CGFloat,
                                feather: Double,
                                rng: inout SpecimenRNG) -> [TerrainGlyph] {
        var glyphs: [TerrainGlyph] = []
        for _ in 0..<count {
            let angle = Double.random(in: 0..<(2 * .pi), using: &rng)
            let u = Double.random(in: 0...1, using: &rng)
            let rNorm = pow(u, 1.5)   // center-dense: most points at small radius
            // Feather: cull with rising probability toward the rim, so the mass
            // fades out instead of stopping at a hard edge.
            if Double.random(in: 0...1, using: &rng) < feather * rNorm { continue }

            let px = center.x + CGFloat(cos(angle)) * rx * CGFloat(rNorm)
            let py = center.y + CGFloat(sin(angle)) * ry * CGFloat(rNorm)
            // Size tapers down toward the rim, with per-glyph jitter.
            let sizeFactor = CGFloat(1.0 - 0.5 * rNorm)
            let height = CGFloat.random(in: minHeight...maxHeight, using: &rng) * sizeFactor
            let width = height * widthRatio * CGFloat.random(in: 0.9...1.1, using: &rng)
            glyphs.append(TerrainGlyph(kind: kind, base: CGPoint(x: px, y: py),
                                       size: CGSize(width: width, height: height)))
        }
        return glyphs
    }

    /// Snow-caps the `count` tallest peaks (the exception, not the rule — §07.3.1).
    private static func capTallest(_ peaks: [TerrainGlyph], count: Int) -> [TerrainGlyph] {
        let tallIDs = peaks.enumerated()
            .sorted { $0.element.size.height > $1.element.size.height }
            .prefix(count)
            .map { $0.offset }
        let tallSet = Set(tallIDs)
        return peaks.enumerated().map { idx, peak in
            var p = peak
            p.snowCap = tallSet.contains(idx)
            return p
        }
    }

    private static func scatterDunes(center: CGPoint, rx: CGFloat, ry: CGFloat,
                                     count: Int, rng: inout SpecimenRNG) -> [TerrainGlyph] {
        var glyphs: [TerrainGlyph] = []
        for _ in 0..<count {
            let angle = Double.random(in: 0..<(2 * .pi), using: &rng)
            let rNorm = pow(Double.random(in: 0...1, using: &rng), 1.2)
            let px = center.x + CGFloat(cos(angle)) * rx * CGFloat(rNorm)
            let py = center.y + CGFloat(sin(angle)) * ry * CGFloat(rNorm)
            let width = CGFloat.random(in: 26...42, using: &rng)
            let height = CGFloat.random(in: 9...15, using: &rng)
            glyphs.append(TerrainGlyph(kind: .dune, base: CGPoint(x: px, y: py),
                                       size: CGSize(width: width, height: height)))
        }
        return glyphs
    }

    /// A village: 3–5 homes tightly clustered and jittered — deliberately too few
    /// to feather, reads as "a place" (§07.4).
    private static func clusterHomes(center: CGPoint, count: Int,
                                     rng: inout SpecimenRNG) -> [TerrainGlyph] {
        var homes: [TerrainGlyph] = []
        for _ in 0..<count {
            let dx = CGFloat.random(in: -16...16, using: &rng)
            let dy = CGFloat.random(in: -12...12, using: &rng)
            let width = CGFloat.random(in: 11...16, using: &rng)
            let height = width * CGFloat.random(in: 1.0...1.2, using: &rng)
            homes.append(TerrainGlyph(kind: .home,
                                      base: CGPoint(x: center.x + dx, y: center.y + dy),
                                      size: CGSize(width: width, height: height)))
        }
        return homes
    }

    private static func makeMarsh(center: CGPoint, rng: inout SpecimenRNG) -> TerrainMarsh {
        let ring = [
            CGPoint(x: center.x - 34, y: center.y - 10), CGPoint(x: center.x - 4, y: center.y - 22),
            CGPoint(x: center.x + 30, y: center.y - 8), CGPoint(x: center.x + 34, y: center.y + 16),
            CGPoint(x: center.x + 2, y: center.y + 26), CGPoint(x: center.x - 30, y: center.y + 14)
        ]
        var glints: [CGPoint] = []
        var reeds: [TerrainMarsh.Reed] = []
        for _ in 0..<5 {
            glints.append(CGPoint(x: center.x + CGFloat.random(in: -22...22, using: &rng),
                                  y: center.y + CGFloat.random(in: -12...14, using: &rng)))
        }
        for _ in 0..<6 {
            let base = CGPoint(x: center.x + CGFloat.random(in: -26...26, using: &rng),
                               y: center.y + CGFloat.random(in: -6...16, using: &rng))
            let lean = CGFloat.random(in: -3...3, using: &rng)
            reeds.append(TerrainMarsh.Reed(base: base,
                                           tip: CGPoint(x: base.x + lean, y: base.y - CGFloat.random(in: 8...14, using: &rng))))
        }
        return TerrainMarsh(body: TerrainBlob(ring: ring), glints: glints, reeds: reeds)
    }
}
