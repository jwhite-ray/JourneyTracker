//
//  MapSceneGeometry.swift
//  JourneyTracker
//
//  The per-scene GEOMETRY CACHE for the P3 camera path (KAN-24). A `TerrainScene`
//  is static for the life of a journey map, yet the KAN-23 organic geography made
//  the camera's per-frame `MapRenderPlanner.plan` recompute the same expensive,
//  scene-invariant geometry on every scroll/zoom tick: the smoothed sea polygon,
//  per-vertex coast seaward normals resolved by point-in-sea-polygon probes, river
//  shore-truncation intersections, and a full point-in-sea test per settlement. On
//  the first organic map (Windrise) that pushed `plan` past the 16 ms frame budget
//  (27 ms on device) and pushed the coast's per-frame `offsetSeaward` — which
//  probes the ~3,500-vertex sea polygon once per coast vertex — into the hundreds
//  of milliseconds, so pinch/pan visibly lagged.
//
//  This type does that work ONCE, when a scene is handed to a camera surface, as a
//  PURE deterministic derivation of the scene (no wall-clock, no RNG, no threading
//  of the generator — same scene ⇒ identical cache on every launch/device). `plan`
//  then only PROJECTS the cached map-space geometry, culls, LOD-thins, and applies
//  the screen-space size taper / overlap constants. Everything cached is affine-
//  covariant with the camera projection (translate + uniform scale), so projecting
//  the cached map-space geometry is pixel-identical to computing it in screen space
//  — the old behavior, just not re-derived 60 times a second.
//
//  The P1 specimen and P2 tuning-harness aspect-fit path (`TerrainRenderer.render(
//  _:into:size:palette:)`) never touch this — they keep computing their (tiny,
//  non-gesture-driven) geometry inline, unchanged.
//

import CoreGraphics

struct MapSceneGeometry {

    /// Precomputed coast render geometry, in MAP space. `sampledMap` is the smoothed
    /// shore (the curve the renderer strokes/fills); `seawardUnit[i]` is that
    /// vertex's outward-to-open-water unit direction, with the seaward SIDE already
    /// resolved by a point-in-sea probe (done here, once, not per frame). Because the
    /// camera projection is a uniform scale, that unit direction is identical in
    /// screen space, so the depth bands offset each PROJECTED vertex by the fixed
    /// screen offset along it — no per-frame probing.
    struct Coast {
        let controlMap: [CGPoint]     // authored/displaced control points (surf stroke)
        let sampledMap: [CGPoint]     // smoothed shore, dense
        let seawardUnit: [CGVector]   // per-`sampledMap`-vertex seaward unit direction
        let seaCornersMap: [CGPoint]
        let seaward: CGVector
        let arcLenMap: CGFloat        // map-unit arc length of `sampledMap` (LOD stride)
    }

    struct Lake {
        let smoothedMap: [CGPoint]    // Catmull-Rom-smoothed ring (river-mouth containment)
        let boxMap: CGRect            // bbox of the smoothed ring (home-over-water skip)
    }

    /// How a river computes its per-frame melt overlap (`runIn`) — the only part of a
    /// river's mouth handling that stays a function of the live camera; the shore
    /// truncation itself is precomputed into `truncatedMap`.
    enum RunIn {
        case freshwater(mapInradius: CGFloat) // runIn/width derive from projected inradius
        case mouthWidth                       // sea + confluence: min(2.5, tapered mouth width)
        case none                             // inland + offMap: no melt
    }

    struct River {
        let truncatedMap: [CGPoint]   // centerline truncated at its receiver's shore (map)
        let runIn: RunIn
    }

    let coasts: [Coast]
    let lakes: [Lake]
    /// Sea fill polygons (smoothed coastline + seaward corners), one per coast, in
    /// map space — the containment reference for river mouths and shoreside homes.
    let seaPolygonsMap: [[CGPoint]]
    /// Aligned 1:1 with `scene.rivers`.
    let rivers: [River]
    /// Home glyph anchors whose base sits in open sea — precomputed so the altitude
    /// "home spilled into water" skip is an O(1) set lookup instead of a per-frame,
    /// per-home point-in-sea-polygon scan. The lookup in `plan` keys on the glyph's
    /// OWN `base` (`CGPoint`, `Hashable` via Foundation), so it's an exact-bit match —
    /// the base stored here and the base looked up are the identical value copied from
    /// the same immutable scene, never a recomputed/rounded one, so equality holds.
    let homeBasesOverSea: Set<CGPoint>

    // MARK: - Build (once per scene)

    init(_ scene: TerrainScene) {
        // Lakes: smoothed ring + bbox (mirrors the renderer's fill + the plan's
        // river-mouth containment ring).
        let lakeGeos: [Lake] = scene.lakes.map { blob in
            let smoothed = MapGeometry.catmullRomSampledClosed(blob.ring)
            return Lake(smoothedMap: smoothed, boxMap: MapGeometry.boundingRect(smoothed))
        }
        lakes = lakeGeos

        // Coasts: smoothed shore + per-vertex seaward unit (side resolved once) + sea
        // fill polygon.
        var coastGeos: [Coast] = []
        var seaPolys: [[CGPoint]] = []
        for coast in scene.coasts {
            let sampled = MapGeometry.catmullRomSampled(coast.coastline)
            var seaPoly = sampled
            seaPoly.append(contentsOf: coast.seaCorners)
            let seaward = Self.resolveSeawardUnits(sampled: sampled, seaPoly: seaPoly,
                                                   seawardHint: coast.seaward)
            coastGeos.append(Coast(controlMap: coast.coastline, sampledMap: sampled,
                                   seawardUnit: seaward, seaCornersMap: coast.seaCorners,
                                   seaward: coast.seaward,
                                   arcLenMap: MapGeometry.polylineLength(sampled)))
            if seaPoly.count >= 3 { seaPolys.append(seaPoly) }
        }
        coasts = coastGeos
        seaPolygonsMap = seaPolys

        // Rivers: classify the receiver and precompute the shore-truncated centerline
        // and melt basis, in map space (mirrors the old per-frame plan logic exactly,
        // just once). Affine-covariant, so projecting the result is identical.
        var riverGeos: [River] = []
        for river in scene.rivers {
            riverGeos.append(Self.buildRiver(river, lakes: lakeGeos, seaPolygons: seaPolys))
        }
        rivers = riverGeos

        // Homes over sea (altitude skip): precompute the point-in-sea test per home.
        var overSea = Set<CGPoint>()
        for glyph in scene.glyphs where glyph.kind == .home {
            if seaPolys.contains(where: { MapGeometry.polygonContains(glyph.base, $0) }) {
                overSea.insert(glyph.base)
            }
        }
        homeBasesOverSea = overSea
    }

    // MARK: - Coast seaward-unit resolution

    /// The per-vertex seaward unit direction for a sampled coastline — the EXACT
    /// choice `MapGeometry.offsetSeaward` makes, computed once. We call `offsetSeaward`
    /// with a unit offset and read back each vertex's displacement direction, so the
    /// per-vertex normal and its probe-resolved seaward SIDE are bit-identical to the
    /// old per-frame camera path (only WHEN it runs changes — once, not every frame).
    /// The point-in-sea probe genuinely needs the full-resolution sea polygon (the
    /// probe steps a fraction of a map unit off the shore, so a coarser boundary can
    /// flip the side), which is why this is cached rather than repeated per frame.
    static func resolveSeawardUnits(sampled: [CGPoint], seaPoly: [CGPoint],
                                    seawardHint: CGVector) -> [CGVector] {
        let n = sampled.count
        guard n >= 2 else { return Array(repeating: seawardHint.normalizedVector, count: n) }
        let shifted = MapGeometry.offsetSeaward(sampled, seaPoly: seaPoly,
                                                seawardHint: seawardHint, offset: 1)
        var out: [CGVector] = []
        out.reserveCapacity(n)
        for i in 0..<n {
            out.append(CGVector(dx: shifted[i].x - sampled[i].x, dy: shifted[i].y - sampled[i].y))
        }
        return out
    }

    // MARK: - River classification + truncation

    private static func buildRiver(_ river: TerrainRiver,
                                   lakes: [Lake],
                                   seaPolygons: [[CGPoint]]) -> River {
        let centerline = river.centerline
        guard let mouthMap = centerline.last else {
            return River(truncatedMap: centerline, runIn: .none)
        }
        switch river.mouth {
        case .freshwater:
            if let lake = lakes.first(where: { MapGeometry.polygonContains(mouthMap, $0.smoothedMap) }) {
                let shore = lake.smoothedMap
                let inradius = shore.reduce(CGFloat.greatestFiniteMagnitude) {
                    min($0, MapGeometry.dist(mouthMap, $1))
                }
                let truncated = MapGeometry.truncatedAtShore(centerline, inside: shore)
                return River(truncatedMap: truncated, runIn: .freshwater(mapInradius: inradius))
            }
            return River(truncatedMap: centerline, runIn: .none)
        case .sea:
            let sea = seaPolygons.first(where: { MapGeometry.polygonContains(mouthMap, $0) })
                ?? seaPolygons.first
            if let sea {
                return River(truncatedMap: MapGeometry.truncatedAtShore(centerline, inside: sea),
                             runIn: .mouthWidth)
            }
            return River(truncatedMap: centerline, runIn: .none)
        case .confluence:
            return River(truncatedMap: centerline, runIn: .mouthWidth)
        case .inland, .offMap:
            return River(truncatedMap: centerline, runIn: .none)
        }
    }
}
