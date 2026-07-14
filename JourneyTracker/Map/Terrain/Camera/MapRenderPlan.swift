//
//  MapRenderPlan.swift
//  JourneyTracker
//
//  The camera's CPU pass (KAN-20, P3): project a map-unit `TerrainScene` through
//  a `MapCamera` into a SCREEN-space scene, cull it to the viewport, and thin its
//  scatter by the density LOD rule. PURE (CoreGraphics only) — no SwiftUI, no
//  `GraphicsContext` — so it is unit-testable and measurable in isolation, and
//  `TerrainRenderer`'s camera entry point just draws the result with the unchanged
//  §07.6 helpers.
//
//  ON-SCREEN GLYPH SIZE — constant near chapter scale, tapering with a floor at
//  altitude. Glyphs/strokes are drawn at their AUTHORED point size at their
//  PROJECTED position (positions scale with zoom, sizes do not) — so near the
//  design reference scale a glyph's on-screen size is constant while the scatter
//  thins, exactly as the sample look was approved. But at extreme altitude
//  (framing a 250-mile leg or the whole 1,800-mile journey) authored sizes fight
//  real geography — a mountain glyph would render wider than the whole world, a
//  river as a highway. So a deterministic `sizeMultiplier` (a pure function of
//  camera + journey scale) tapers glyph/home/water-stroke sizes from 1.0 at the
//  reference scale down to a floor as the camera climbs. Pins and their Cinzel
//  chips are EXEMPT — labels must stay legible at every altitude. The compat
//  (aspect-fit) path never taper: it renders at the reference by construction.
//
//  DENSITY LOD — deterministic, nested, texture-preserving:
//   • Each scatter glyph gets a stable keep-rank in [0,1) from a hash of its own
//     (kind, base) — a pure function of the glyph, identical on every launch and
//     device (never `String.hashValue`, which Swift salts per process).
//   • We target a constant on-screen scatter COUNT (≈ constant screen density):
//     keepFraction = min(1, targetCount / in-view-scatter-count); a glyph draws
//     iff its rank < keepFraction. Uniform rank thinning preserves the feathered
//     center-dense profile (the generator already made it) AND the relative
//     density between regions (a forest stays denser than plains).
//   • NESTING: zooming out grows the visible rect, grows the in-view pool, lowers
//     keepFraction — so the kept set only ever SHRINKS as you zoom out and never
//     reshuffles (a dropped glyph, its rank now above the lower threshold, cannot
//     reappear until you zoom back in). Masses read as texture at every zoom —
//     never dust, never a few big icons.
//   • Settlements (homes) are clusters, not masses (§07.4) — they are never
//     thinned; water, coast, rivers, paths and pins always draw (culled only).
//

import CoreGraphics

/// LOD tuning. `targetScatterPerPoint` is calibrated so the ~30-mile sample map
/// at chapter framing keeps essentially all of its scatter (matching the approved
/// P1 density), while any larger map shows the same on-screen grain.
struct MapLOD: Equatable {
    /// Target scatter glyphs per screen point² of viewport. Tuned upward from the
    /// first pass so that at altitude — where glyphs are tapered smaller — the
    /// masses still read as texture, not sparse confetti. ~0.0016 ⇒ ≈535 on a
    /// 393×852 phone; the ~30-mi sample scene has far fewer, so it keeps them all.
    var targetScatterPerPoint: CGFloat = 0.0016

    /// Screen points per real mile at the DESIGN REFERENCE scale — the approved
    /// sample look (~470 map units / 30 mi at 1 pt-per-unit ⇒ 15.67 pt/mi). At or
    /// above this, glyphs render at authored size (multiplier 1.0).
    var referencePtPerMile: CGFloat = 15.67

    /// Lower bound on the size taper — glyphs never shrink below 30% of authored,
    /// so a mass stays legible texture rather than dust at full-journey overview.
    var sizeFloor: CGFloat = 0.3

    func targetCount(in viewport: CGSize) -> Int {
        Int((targetScatterPerPoint * viewport.width * viewport.height).rounded())
    }

    /// The glyph/stroke size multiplier for a camera at a given journey scale:
    /// 1.0 at/above the reference pt-per-mile, tapering to `sizeFloor` at altitude.
    /// Pure and deterministic — a function of camera zoom and journey scale only.
    func sizeMultiplier(zoom: CGFloat, milesPerMapUnit: Double) -> CGFloat {
        guard milesPerMapUnit > 0, referencePtPerMile > 0 else { return 1 }
        let ptPerMile = zoom / CGFloat(milesPerMapUnit)
        return min(1, max(sizeFloor, ptPerMile / referencePtPerMile))
    }

    /// Kinds that scatter as a MASS and therefore thin under LOD (§07.4). Homes
    /// are a cluster and never thin.
    static func thins(_ kind: TerrainGlyphKind) -> Bool {
        switch kind {
        case .mountain, .conifer, .grassTuft, .dune: return true
        case .home: return false
        }
    }

    /// A stable, deterministic keep-rank in [0,1) for a glyph — a pure function of
    /// its kind and base, so the same zoom always shows the same subset on every
    /// device and launch. SplitMix64-style finalizer over the glyph's bit pattern.
    static func keepRank(for glyph: TerrainGlyph) -> Double {
        var z: UInt64 = 0x9E37_79B9_7F4A_7C15 &* glyph.kind.rankSalt
        z ^= Double(glyph.base.x).bitPattern &* 0x1000_0001
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z ^= Double(glyph.base.y).bitPattern &* 0x1000_0193
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) * (1.0 / 9_007_199_254_740_992.0) // 53-bit → [0,1)
    }
}

/// What a plan drew vs. dropped — the perf-gate evidence surfaced in the debug
/// overlay and asserted by tests.
struct TerrainRenderStats: Equatable {
    var totalScatter = 0
    var inViewScatter = 0      // survived culling, before LOD thinning
    var drawnScatter = 0       // survived culling AND LOD
    var drawnHomes = 0
    var drawnWaterShapes = 0   // lakes + rivers + plains + marsh + coast
    var drawnPaths = 0
    var drawnPins = 0
    /// The LOD keep-fraction this plan used — monotonic non-increasing as zoom
    /// decreases, which is the nesting guarantee ("zooming out only removes").
    var keepFraction: Double = 1

    var culledScatter: Int { totalScatter - inViewScatter }
    var thinnedScatter: Int { inViewScatter - drawnScatter }
}

enum MapRenderPlanner {

    /// Projects `scene` through `camera` into a screen-space scene, culled to
    /// `viewport` and LOD-thinned. The returned scene is drawn as-is by
    /// `TerrainRenderer.drawScene` (identity transform).
    ///
    /// `geometry` is the scene's precomputed geometry cache (KAN-24) — smoothed sea
    /// polygons, coast seaward normals, river shore truncations, and the per-home
    /// sea test, all derived ONCE. It is a pure derivation of `scene` and MUST have
    /// been built from this exact `scene` (`MapSceneGeometry(scene)`); it is required
    /// (not optional) so a caller can never accidentally rebuild the cache per frame.
    /// `plan` stays a pure function of `(scene, geometry, camera, viewport, lod)`.
    static func plan(_ scene: TerrainScene,
                     geometry geo: MapSceneGeometry,
                     camera: MapCamera,
                     viewport: CGSize,
                     milesPerMapUnit: Double = 0,
                     lod: MapLOD = MapLOD()) -> (scene: TerrainScene, stats: TerrainRenderStats) {
        var out = TerrainScene()
        var stats = TerrainRenderStats()
        // Contract: the cache is a derivation of THIS scene. A mismatch (wrong cache
        // passed) would silently render a wrong map, so fail fast in debug.
        assert(geo.coasts.count == scene.coasts.count
               && geo.rivers.count == scene.rivers.count
               && geo.lakes.count == scene.lakes.count,
               "MapSceneGeometry does not match the scene it is being planned against")

        func P(_ p: CGPoint) -> CGPoint { camera.project(p, in: viewport) }

        // Clip region: the authored bounds, PROJECTED, so off-bounds terrain
        // (ranges past the map edge, sea corners) can't bleed into the letterbox
        // (App Concept doc: "the renderer clips" authored overflow). Projection is
        // translate+scale, so two opposite corners give the axis-aligned rect.
        let b0 = P(scene.bounds.origin)
        let b1 = P(CGPoint(x: scene.bounds.maxX, y: scene.bounds.maxY))
        out.bounds = CGRect(x: min(b0.x, b1.x), y: min(b0.y, b1.y),
                            width: abs(b1.x - b0.x), height: abs(b1.y - b0.y))

        // The altitude size taper (constant near chapter scale, floored at altitude).
        let sizeMul = lod.sizeMultiplier(zoom: camera.zoom, milesPerMapUnit: milesPerMapUnit)

        // Screen-space viewport and a padded version for shape culling.
        let screen = CGRect(origin: .zero, size: viewport)
        let shapePad = screen.insetBy(dx: -12, dy: -12)

        // --- Water & ground shapes: project rings/lines, cull by bounding box ---
        for coastGeo in geo.coasts {
            // Coast fills the whole sea side — always keep it. Project the cached
            // smoothed shore and its precomputed seaward units, detail-LOD decimated
            // by projected spacing so the renderer strokes a screen-appropriate number
            // of segments (a few hundred), not the full ~3,500 sub-pixel ones — and
            // never re-derives the seaward normals (KAN-24).
            let stride = detailStride(count: coastGeo.sampledMap.count,
                                      mapArc: coastGeo.arcLenMap, zoom: camera.zoom)
            var sampled: [CGPoint] = []
            var seaward: [CGVector] = []
            sampled.reserveCapacity(coastGeo.sampledMap.count / stride + 2)
            var i = 0
            while i < coastGeo.sampledMap.count {
                sampled.append(P(coastGeo.sampledMap[i]))
                seaward.append(coastGeo.seawardUnit[i]) // uniform-scale ⇒ same screen dir
                i += stride
            }
            // Always anchor the last vertex so the shore reaches its true end.
            if i - stride != coastGeo.sampledMap.count - 1 {
                sampled.append(P(coastGeo.sampledMap[coastGeo.sampledMap.count - 1]))
                seaward.append(coastGeo.seawardUnit[coastGeo.sampledMap.count - 1])
            }
            out.coasts.append(TerrainCoast(coastline: coastGeo.controlMap.map(P),
                                           seaward: coastGeo.seaward,
                                           seaCorners: coastGeo.seaCornersMap.map(P),
                                           sampled: sampled,
                                           bandSeaward: seaward))
            stats.drawnWaterShapes += 1
        }
        for plains in scene.plains {
            let ring = plains.wash.ring.map(P)
            if boundingBox(ring).intersects(shapePad) {
                out.plains.append(TerrainPlains(wash: TerrainBlob(ring: ring)))
                stats.drawnWaterShapes += 1
            }
        }
        for marsh in scene.marshes {
            let ring = marsh.body.ring.map(P)
            if boundingBox(ring).intersects(shapePad) {
                out.marshes.append(TerrainMarsh(body: TerrainBlob(ring: ring),
                                                glints: marsh.glints.map(P),
                                                reeds: marsh.reeds.map { .init(base: P($0.base), tip: P($0.tip)) }))
                stats.drawnWaterShapes += 1
            }
        }
        // Lakes: project the authored ring/bbox for the culled blob; the map-space
        // smoothed ring + bbox used for river-mouth containment and the altitude
        // home-over-water skip live in the geometry cache (KAN-24).
        for lake in scene.lakes {
            let projRing = lake.ring.map(P)
            if boundingBox(projRing).intersects(shapePad) {
                out.lakes.append(TerrainBlob(ring: projRing))
                stats.drawnWaterShapes += 1
            }
        }
        // Rivers: the shore truncation is precomputed in MAP space (cache), so per
        // frame we only PROJECT the already-truncated centerline and apply the
        // screen-space melt overlap / width taper (KAN-24). Affine-covariant, so the
        // projected result is identical to the old per-frame screen-space truncation.
        for (idx, river) in scene.rivers.enumerated() {
            let rgeo = geo.rivers[idx]
            let line = rgeo.truncatedMap.map(P)
            // Widths taper with altitude so a river never becomes a highway band.
            var mw = river.mouthWidth * sizeMul
            let sw = river.sourceWidth * sizeMul
            var runIn: CGFloat = 0
            switch rgeo.runIn {
            case .freshwater(let mapInradius):
                // Inradius is a projected distance ⇒ map inradius × zoom. Clamp the
                // mouth width and overlap so the cap can't cross a tiny far-zoom lake.
                let inradius = mapInradius * camera.zoom
                mw = min(mw, max(1.0, 1.2 * inradius))
                runIn = min(2.5, 0.7 * inradius)
            case .mouthWidth:
                // Sea + confluence mouths: overlap a short fixed run past the shore /
                // junction so the same-tone body reads fill-continuous.
                runIn = min(2.5, mw)
            case .none:
                // inland / offMap: no melt. offMap runs to the bounds edge and the
                // `drawPlanned` bounds clip cuts it there.
                break
            }
            if boundingBox(line).insetBy(dx: -mw - runIn, dy: -mw - runIn).intersects(shapePad) {
                out.rivers.append(TerrainRiver(centerline: line, sourceWidth: min(sw, mw),
                                               mouthWidth: mw, mouth: river.mouth, meltRunIn: runIn))
                stats.drawnWaterShapes += 1
            }
        }
        for path in scene.paths {
            let pts = path.points.map(P)
            if boundingBox(pts).insetBy(dx: -6, dy: -6).intersects(shapePad) {
                out.paths.append(TerrainPath(points: pts, style: path.style))
                stats.drawnPaths += 1
            }
        }

        // --- Scatter glyphs: cull, then LOD-thin the masses ---
        //
        // keepFraction is VISIBLE-AREA based, so it targets a constant on-screen
        // scatter density (grain) at every zoom and map scale:
        //   keepFraction = target / (sceneDensity · visibleArea∩bounds)
        // • Pan-stable: while the view stays inside the map, the visible area is a
        //   pure function of zoom, so panning only translates glyphs — it never
        //   pops individual glyphs in/out (unlike an in-view-COUNT basis).
        // • Bounds-capped: at full-journey overview the visible area saturates at
        //   the map's own area, so keepFraction → target/pool — never dust.
        // • Zoom-nested: as zoom decreases the (clamped) visible area only grows,
        //   so keepFraction only falls — the kept set can only shrink.
        let target = Double(lod.targetCount(in: viewport))
        let pool = Double(scene.glyphs.reduce(0) { $0 + (MapLOD.thins($1.kind) ? 1 : 0) })
        let bounds = scene.bounds
        let boundsArea = Double(max(bounds.width, 0) * max(bounds.height, 0))
        let visible = camera.visibleRect(in: viewport)
        let clamped = visible.intersection(bounds)
        let clampedArea = clamped.isNull ? 0 : Double(clamped.width * clamped.height)
        let sceneDensity = boundsArea > 0 ? pool / boundsArea : 0
        let keepFraction: Double = (pool <= 0 || sceneDensity <= 0 || clampedArea <= 0)
            ? 1
            : min(1, target / (sceneDensity * clampedArea))
        stats.keepFraction = keepFraction

        // At altitude (taper active) a home's projected footprint can visually spill
        // into a tiny lake/sea even though the generator kept its base dry in map
        // space — so drop such a home. Deterministic (pure function of camera).
        // • SEA test: precomputed per home in the geometry cache (a home's map base
        //   and the sea polygons are both scene-invariant), so it's an O(1) set
        //   lookup instead of a per-frame per-home point-in-sea scan (KAN-24).
        // • LAKE test: the tapered footprint is zoom-dependent, but the test is done
        //   in MAP space against the cached lake bboxes — affine-covariant with the
        //   old projected test, and only a couple of cheap bbox intersects.
        let taperActive = sizeMul < 0.999
        let invZoom = camera.zoom > 0 ? 1 / camera.zoom : 0
        func homeOverWater(mapBase: CGPoint, w: CGFloat, h: CGFloat) -> Bool {
            if geo.homeBasesOverSea.contains(mapBase) { return true }
            // Screen footprint (base.x - w/2, base.y - h, w, h) mapped back to map units.
            let mapFootprint = CGRect(x: mapBase.x - (w / 2) * invZoom,
                                      y: mapBase.y - h * invZoom,
                                      width: w * invZoom, height: h * invZoom)
            return geo.lakes.contains { $0.boxMap.intersects(mapFootprint) }
        }

        var inViewHomes: [TerrainGlyph] = []
        for glyph in scene.glyphs {
            let mass = MapLOD.thins(glyph.kind)
            if mass { stats.totalScatter += 1 }
            let base = P(glyph.base)
            // Tapered on-screen size; footprint (and cull margin) use the tapered size.
            let w = glyph.size.width * sizeMul
            let h = glyph.size.height * sizeMul
            let m = h + w
            let inView = base.x > -m && base.x < viewport.width + m
                && base.y > -m && base.y < viewport.height + h + m
            if mass, inView { stats.inViewScatter += 1 }
            guard inView else { continue }
            var projected = glyph
            projected.base = base
            projected.size = CGSize(width: w, height: h)
            if mass {
                // Keep-rank is from the ORIGINAL map-space glyph, so the subset is
                // stable across zoom/pan (the taper changes size, never membership).
                if MapLOD.keepRank(for: glyph) < keepFraction { out.glyphs.append(projected) }
            } else {
                if taperActive, homeOverWater(mapBase: glyph.base, w: w, h: h) { continue }
                inViewHomes.append(projected)
            }
        }
        stats.drawnScatter = out.glyphs.count
        out.glyphs.append(contentsOf: inViewHomes)
        stats.drawnHomes = inViewHomes.count

        // --- Pins: always draw, culled with a generous chip margin ---
        for pin in scene.pins {
            let pos = P(pin.position)
            let m: CGFloat = 90 // teardrop + Cinzel chip headroom
            guard pos.x > -m, pos.x < viewport.width + m,
                  pos.y > -m, pos.y < viewport.height + m else { continue }
            var moved = pin
            moved.position = pos
            out.pins.append(moved)
        }
        stats.drawnPins = out.pins.count

        return (out, stats)
    }

    // MARK: - Helpers

    /// Detail-LOD stride for a long projected polyline: a keep-every-nth step chosen
    /// so the projected samples land ≈`targetScreenSpacing` points apart, rounded
    /// DOWN to a power of two so successive levels NEST (every level is a subset of a
    /// denser one) — the same stability rule the scatter LOD uses, so a stride change
    /// during a gesture drops/re-adds a whole nested layer rather than reshuffling
    /// vertices. Deterministic: a pure function of the count, map arc length, and
    /// zoom (KAN-24).
    private static func detailStride(count: Int, mapArc: CGFloat, zoom: CGFloat,
                                     targetScreenSpacing: CGFloat = 1.2) -> Int {
        guard count > 2, mapArc > 0, zoom > 0, targetScreenSpacing > 0 else { return 1 }
        let screenArc = mapArc * zoom
        let desiredCount = max(2, Int((screenArc / targetScreenSpacing).rounded(.up)))
        let rawStride = max(1, count / desiredCount)
        var s = 1
        while s * 2 <= rawStride { s *= 2 }
        return s
    }

    private static func boundingBox(_ pts: [CGPoint]) -> CGRect {
        guard let first = pts.first else { return .null }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for p in pts {
            minX = min(minX, p.x); minY = min(minY, p.y)
            maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

private extension TerrainGlyphKind {
    /// A small distinct salt per kind so two kinds sharing a base still get
    /// independent keep-ranks.
    var rankSalt: UInt64 {
        switch self {
        case .mountain: return 1
        case .conifer: return 2
        case .home: return 3
        case .grassTuft: return 4
        case .dune: return 5
        }
    }
}
