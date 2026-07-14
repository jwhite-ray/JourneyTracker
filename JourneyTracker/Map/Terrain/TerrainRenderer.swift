//
//  TerrainRenderer.swift
//  JourneyTracker
//
//  The real faceted-terrain renderer (KAN-16 P1 / KAN-18). Pure drawing: it takes
//  a `TerrainScene` of value types and a resolved `TerrainPalette` and paints them
//  into one `GraphicsContext` in a single Canvas pass — never a view per glyph
//  (§07.7, App Concept doc). The §07.6 back-to-front draw order is enforced HERE,
//  by `render(_:)`, not by the caller.
//
//  Everything below is flat facets only: stacked `Path` fills and strokes, colours
//  resolved from `terrain/*` / `ink` / `surface/card` tokens through the palette.
//  No gradients, no blur, no hex literals — the one "shadow" trick is the mountain
//  hard offset shadow (§07.3.1 / §09), a second solid ink triangle nudged
//  down-right, not a blurred layer.
//
//  In P1 the scene is hand-authored (TerrainSpecimenScene). In P2 the seeded
//  generator emits the identical value types and this renderer is unchanged.
//

import SwiftUI

enum TerrainRenderer {

    // MARK: - Entry point: the fixed draw order (§07.6)

    /// Draws the whole scene in the §07.6 order, aspect-fitting the scene's
    /// authored `bounds` into `size` (the P3 camera's stand-in for now).
    ///
    /// ocean/coast → ground cover (plains → dunes → marsh) → lakes → rivers →
    /// forests → mountains → roads/trek path → settlements → labels/pins.
    static func render(_ scene: TerrainScene,
                       into context: inout GraphicsContext,
                       size: CGSize,
                       palette: TerrainPalette) {
        // Fit the authored bounds into the canvas, centered.
        let b = scene.bounds
        guard b.width > 0, b.height > 0 else { return }
        let scale = min(size.width / b.width, size.height / b.height)
        let drawnW = b.width * scale
        let drawnH = b.height * scale
        context.translateBy(x: (size.width - drawnW) / 2, y: (size.height - drawnH) / 2)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -b.origin.x, y: -b.origin.y)

        // Clip to the fitted scene rect so authored overflow (coastline off the
        // top/bottom, sea corners past the right edge) can't bleed into the
        // letterbox on a canvas whose aspect isn't the authored one.
        context.clip(to: Path(b))
        drawScene(scene, into: &context, palette: palette)
    }

    /// Draws an ALREADY-POSITIONED scene in the §07.6 back-to-front order, with no
    /// transform of its own. The P1/P2 `render` above calls this after its
    /// aspect-fit transform; the P3 camera entry calls it after projecting the
    /// scene into screen space (`MapRenderPlanner`). One draw-order authority, two
    /// coordinate sources.
    ///
    /// ocean/coast → ground cover (plains → dunes → marsh) → lakes → rivers →
    /// forests → mountains → roads/trek path → settlements → labels/pins.
    static func drawScene(_ scene: TerrainScene,
                          into context: inout GraphicsContext,
                          palette: TerrainPalette) {
        drawTerrain(scene, into: &context, palette: palette)
        drawPins(scene, into: &context, palette: palette)
    }

    /// Stages 1–8 (everything BELOW the labels/pins): the terrain proper. Split out
    /// so the camera path can clip terrain to the authored bounds while drawing pins
    /// (stage 9) under a different, viewport-only clip.
    static func drawTerrain(_ scene: TerrainScene,
                            into context: inout GraphicsContext,
                            palette: TerrainPalette) {
        // 1 · Ocean / coast (may be several — a wrapped/L-shaped sea, an inland sea)
        for coast in scene.coasts { drawCoast(coast, into: &context, palette: palette) }

        // 2 · Ground cover — plains wash + tufts, then dunes, then marsh
        for plains in scene.plains { drawPlains(plains, into: &context, palette: palette) }
        for tuft in scene.glyphs(.grassTuft) { drawGrassTuft(tuft, into: &context, palette: palette) }
        for dune in scene.glyphs(.dune) { drawDune(dune, into: &context, palette: palette) }
        for marsh in scene.marshes { drawMarsh(marsh, into: &context, palette: palette) }

        // 3 · Lakes
        for lake in scene.lakes { drawLake(lake, into: &context, palette: palette) }

        // 4 · Rivers
        for river in scene.rivers { drawRiver(river, into: &context, palette: palette) }

        // 5 · Forests (conifers)
        for tree in scene.glyphs(.conifer) { drawConifer(tree, into: &context, palette: palette) }

        // 6 · Mountains
        for peak in scene.glyphs(.mountain) { drawMountain(peak, into: &context, palette: palette) }

        // 7 · Roads / trek path
        for path in scene.paths { drawPath(path, into: &context, palette: palette) }

        // 8 · Settlements
        for home in scene.glyphs(.home) { drawHome(home, into: &context, palette: palette) }
    }

    /// Stage 9 (labels / pins). UI drawn ABOVE all terrain (§07.6) — in the camera
    /// path this runs OUTSIDE the terrain bounds clip so a destination chip near
    /// the map edge is never clipped away (Justin's "destination always labeled").
    static func drawPins(_ scene: TerrainScene,
                         into context: inout GraphicsContext,
                         palette: TerrainPalette) {
        for pin in scene.pins { drawPin(pin, into: &context, palette: palette) }
    }

    // MARK: - Camera entry (P3, KAN-20)

    /// Draws `scene` through `camera` into `viewport`: projects + culls + LOD-thins
    /// via `MapRenderPlanner`, then draws the screen-space result. Returns the
    /// plan's stats (drawn / culled / thinned counts) for the perf overlay. This
    /// is the entry the P3 surfaces use; the P1 specimen / P2 harness keep calling
    /// the aspect-fit `render(_:into:size:palette:)` above, unchanged.
    /// ⚠️ CONVENIENCE / TEST ENTRY ONLY. This BUILDS the per-scene geometry cache on
    /// every call (`MapSceneGeometry(scene)` — the ~ms one-time work KAN-24 hoisted
    /// out of the frame), so it must NOT be driven from a gesture loop. The shipping
    /// surfaces build the cache once (in `JourneyMapPresentation`) and call
    /// `MapRenderPlanner.plan(_:geometry:…)` + `drawPlanned` directly; a per-frame
    /// caller must do the same.
    @discardableResult
    static func render(_ scene: TerrainScene,
                       into context: inout GraphicsContext,
                       viewport: CGSize,
                       camera: MapCamera,
                       milesPerMapUnit: Double = 0,
                       palette: TerrainPalette,
                       lod: MapLOD = MapLOD()) -> TerrainRenderStats {
        let geometry = MapSceneGeometry(scene)
        let (projected, stats) = MapRenderPlanner.plan(scene, geometry: geometry, camera: camera,
                                                       viewport: viewport,
                                                       milesPerMapUnit: milesPerMapUnit, lod: lod)
        drawPlanned(projected, into: &context, viewport: viewport, palette: palette)
        return stats
    }

    /// Draws an already-planned (screen-space) scene — lets a view compute the
    /// plan once (to read its stats) and hand the result straight to the Canvas.
    /// TERRAIN is clipped to the projected authored bounds so off-map overflow
    /// can't bleed into the letterbox; PINS/labels then draw over it clipped to the
    /// viewport ONLY, so a destination chip near the map edge is never a victim of
    /// the terrain clip (§07.6: pins are UI above all terrain).
    static func drawPlanned(_ projected: TerrainScene,
                            into context: inout GraphicsContext,
                            viewport: CGSize,
                            palette: TerrainPalette) {
        let viewportRect = CGRect(origin: .zero, size: viewport)
        let boundsClip = projected.bounds.intersection(viewportRect)
        context.drawLayer { layer in
            layer.clip(to: Path(boundsClip.isNull ? viewportRect : boundsClip))
            drawTerrain(projected, into: &layer, palette: palette)
        }
        // Map-edge border (KAN-20 Gate 3 / §07 map-frame): a 3pt ink stroke tracing
        // the authored world edge, ABOVE terrain and BELOW pins, visible wherever
        // the edge is on screen. Ink token ⇒ inverts in Deepdark; bare parchment
        // sits outside it. Drawn clipped to the viewport so off-screen edges cost
        // nothing. (Corner treatment is a plain miter pending Jeff's §07 line.)
        context.drawLayer { layer in
            layer.clip(to: Path(viewportRect))
            layer.stroke(Path(projected.bounds), with: .color(palette.ink),
                         style: StrokeStyle(lineWidth: 3, lineJoin: .miter))
        }
        context.drawLayer { layer in
            layer.clip(to: Path(viewportRect))
            drawPins(projected, into: &layer, palette: palette)
        }
    }

    // MARK: - Mountains (§07.3.1)

    private static func drawMountain(_ g: TerrainGlyph,
                                     into ctx: inout GraphicsContext,
                                     palette: TerrainPalette) {
        let w = g.size.width, h = g.size.height
        let apex = CGPoint(x: g.base.x, y: g.base.y - h)
        let left = CGPoint(x: g.base.x - w / 2, y: g.base.y)
        let right = CGPoint(x: g.base.x + w / 2, y: g.base.y)
        let mid = g.base

        // Hard offset shadow: a second, solid ink copy nudged down-right (§07.3.1,
        // the §09 hard-drop-shadow token — no blur).
        let off = CGVector(dx: max(2, w * 0.10), dy: 4)
        var shadow = Path()
        shadow.move(to: apex.offset(off))
        shadow.addLine(to: right.offset(off))
        shadow.addLine(to: left.offset(off))
        shadow.closeSubpath()
        ctx.fill(shadow, with: .color(palette.hardShadow))

        // Ridge split: light half toward top-left, dark half away.
        ctx.fill(triangle(apex, left, mid), with: .color(palette.stone.highlight))
        ctx.fill(triangle(apex, right, mid), with: .color(palette.stone.shadow))

        // Snow cap on the tallest few only (§07.3.1).
        if g.snowCap {
            let capW = w * 0.46
            let capH = h * 0.32
            let capBaseY = apex.y + capH
            let capLeft = CGPoint(x: apex.x - capW / 2, y: capBaseY)
            let capRight = CGPoint(x: apex.x + capW / 2, y: capBaseY)
            let capMid = CGPoint(x: apex.x, y: capBaseY)
            ctx.fill(triangle(apex, capLeft, capMid), with: .color(palette.snow.highlight))
            ctx.fill(triangle(apex, capRight, capMid), with: .color(palette.snow.shadow))
        }
    }

    // MARK: - Conifers (§07.3.2)

    private static func drawConifer(_ g: TerrainGlyph,
                                    into ctx: inout GraphicsContext,
                                    palette: TerrainPalette) {
        let w = g.size.width, h = g.size.height
        let trunkW = max(1.5, w * 0.16)
        let trunkH = h * 0.20
        let trunk = CGRect(x: g.base.x - trunkW / 2, y: g.base.y - trunkH, width: trunkW, height: trunkH)
        ctx.fill(Path(trunk), with: .color(palette.ink))

        let canopyBaseY = g.base.y - trunkH * 0.6
        let apex = CGPoint(x: g.base.x, y: g.base.y - h)
        let left = CGPoint(x: g.base.x - w / 2, y: canopyBaseY)
        let right = CGPoint(x: g.base.x + w / 2, y: canopyBaseY)
        let mid = CGPoint(x: g.base.x, y: canopyBaseY)
        // Autumn reskin swaps the green triad for a rust one (§07.3.2) — same
        // geometry, a different token.
        let canopy = g.autumn ? palette.roof : palette.forest
        ctx.fill(triangle(apex, left, mid), with: .color(canopy.highlight))
        ctx.fill(triangle(apex, right, mid), with: .color(canopy.shadow))
    }

    // MARK: - Grass tufts (§07.3.6)

    private static func drawGrassTuft(_ g: TerrainGlyph,
                                      into ctx: inout GraphicsContext,
                                      palette: TerrainPalette) {
        let w = g.size.width, h = g.size.height
        let apex = CGPoint(x: g.base.x, y: g.base.y - h)
        let left = CGPoint(x: g.base.x - w / 2, y: g.base.y)
        let right = CGPoint(x: g.base.x + w / 2, y: g.base.y)
        ctx.fill(triangle(apex, left, g.base), with: .color(palette.grass.highlight))
        ctx.fill(triangle(apex, right, g.base), with: .color(palette.grass.shadow))
    }

    // MARK: - Dunes (§07.3.6)

    private static func drawDune(_ g: TerrainGlyph,
                                 into ctx: inout GraphicsContext,
                                 palette: TerrainPalette) {
        let w = g.size.width, h = g.size.height
        let left = CGPoint(x: g.base.x - w / 2, y: g.base.y)
        let right = CGPoint(x: g.base.x + w / 2, y: g.base.y)
        var dome = Path()
        dome.move(to: left)
        dome.addQuadCurve(to: right, control: CGPoint(x: g.base.x, y: g.base.y - h * 2))
        dome.closeSubpath()
        ctx.fill(dome, with: .color(palette.sand.base))
        // Ridge split: windward (left) highlight, lee (right) shadow.
        let bb = dome.boundingRect
        ctx.drawLayer { layer in
            layer.clip(to: dome)
            layer.fill(Path(CGRect(x: bb.minX, y: bb.minY, width: bb.width / 2, height: bb.height)),
                       with: .color(palette.sand.highlight))
            layer.fill(Path(CGRect(x: bb.midX, y: bb.minY, width: bb.width / 2, height: bb.height)),
                       with: .color(palette.sand.shadow))
        }
    }

    // MARK: - Plains (§07.3.6)

    private static func drawPlains(_ plains: TerrainPlains,
                                   into ctx: inout GraphicsContext,
                                   palette: TerrainPalette) {
        // A low-opacity grass wash — texture under the tufts, not a solid fill.
        let path = smoothedPath(plains.wash.ring, closed: true)
        ctx.fill(path, with: .color(palette.grass.base.opacity(0.35)))
    }

    // MARK: - Marsh (§07.3.6)

    private static func drawMarsh(_ marsh: TerrainMarsh,
                                  into ctx: inout GraphicsContext,
                                  palette: TerrainPalette) {
        let path = smoothedPath(marsh.body.ring, closed: true)
        ctx.fill(path, with: .color(palette.marsh.base))
        cornerClipFacets(path, into: &ctx, highlight: palette.marsh.highlight, shadow: palette.marsh.shadow)
        // Small pill-shaped water glints.
        for glint in marsh.glints {
            let pill = Path(roundedRect: CGRect(x: glint.x - 3, y: glint.y - 1.2, width: 6, height: 2.4),
                            cornerRadius: 1.2)
            ctx.fill(pill, with: .color(palette.water.highlight))
        }
        // Leaning reed strokes in the marsh shadow tone.
        for reed in marsh.reeds {
            var r = Path()
            r.move(to: reed.base)
            r.addLine(to: reed.tip)
            ctx.stroke(r, with: .color(palette.marsh.shadow),
                       style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        }
    }

    // MARK: - Lakes (§07.3.4)

    private static func drawLake(_ blob: TerrainBlob,
                                 into ctx: inout GraphicsContext,
                                 palette: TerrainPalette) {
        let path = smoothedPath(blob.ring, closed: true)
        ctx.fill(path, with: .color(palette.water.base))
        cornerClipFacets(path, into: &ctx, highlight: palette.water.highlight, shadow: palette.water.shadow)
        // Pale shoreline rim (foam / shallows) — a dedicated near-snow tone, not
        // the water highlight (which is invisible on the highlight facet).
        ctx.stroke(path, with: .color(palette.surf),
                   style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
    }

    // MARK: - Rivers (§07.3.3)

    private static func drawRiver(_ river: TerrainRiver,
                                  into ctx: inout GraphicsContext,
                                  palette: TerrainPalette) {
        // A melting mouth runs a short way PAST its authored end into the
        // receiving water, so the body (same water token as the receiver's fill)
        // overlaps it and fill continuity — not an edge — makes the join. Rivers
        // draw after lakes/ocean (§07.6), so this overlap sits on top and, being
        // the same tone, reads seamless.
        // Freshwater / sea / confluence mouths MELT into receiving water; inland and
        // offMap mouths do not (offMap runs full-width to the bounds edge and the
        // clip cuts it — §07.3.3, KAN-23).
        let melts = river.mouth == .freshwater || river.mouth == .sea || river.mouth == .confluence
        var line = river.centerline
        if melts, line.count >= 2 {
            let a = line[line.count - 2], b = line[line.count - 1]
            let dir = CGVector(dx: b.x - a.x, dy: b.y - a.y).normalized
            let runIn = river.meltRunIn
            line.append(CGPoint(x: b.x + dir.dx * runIn, y: b.y + dir.dy * runIn))
        }
        let pts = sampledCurve(line)
        guard pts.count >= 2 else { return }
        let n = pts.count

        func t(_ i: Int) -> CGFloat { CGFloat(i) / CGFloat(n - 1) }
        func bodyWidth(at i: Int) -> CGFloat {
            river.sourceWidth + (river.mouthWidth - river.sourceWidth) * t(i)
        }
        // Bank (dark) margin fades to the body width over the last stretch of a
        // melting river, so the dark bank never caps across the receiving water.
        func bankWidth(at i: Int) -> CGFloat {
            let full = bodyWidth(at: i) * (13.0 / 9.0)
            guard melts else { return full }
            return full + (bodyWidth(at: i) - full) * smoothFade(t(i), from: 0.68)
        }
        // Highlight ribbon fades to nothing at a melting mouth — no bright stub
        // left floating on the receiving water.
        func ribbonWidth(at i: Int) -> CGFloat {
            let base = bodyWidth(at: i) * (3.0 / 9.0)
            guard melts else { return base }
            return base * (1 - smoothFade(t(i), from: 0.78))
        }
        // At a SEA mouth the shallowest band the body meets is the pale shallows,
        // so the body transitions base → shallow-band tone at the very end; a
        // freshwater (lake) mouth meets the lake's own base fill and needs none.
        func bodyColor(at i: Int) -> Color {
            guard river.mouth == .sea else { return palette.water.base }
            return palette.mix(palette.water.base, palette.water.highlight,
                               smoothFade(t(i), from: 0.72))
        }

        // Three passes, thickest→thinnest. Bank (dark), body (base), highlight
        // ribbon (light, nudged up-left).
        strokeTapered(pts, into: &ctx, colorAt: { _ in palette.water.deep },
                      widthAt: bankWidth, offset: .zero)
        strokeTapered(pts, into: &ctx, colorAt: bodyColor,
                      widthAt: bodyWidth, offset: .zero)
        strokeTapered(pts, into: &ctx, colorAt: { _ in palette.water.highlight },
                      widthAt: ribbonWidth, offset: CGVector(dx: -1.5, dy: -1.5))
    }

    /// Smoothstep ramp from 0 (at/below `start`) up to 1 at t = 1 — used to fade a
    /// river's bank/ribbon out and blend its body tone toward a melting mouth.
    private static func smoothFade(_ t: CGFloat, from start: CGFloat) -> CGFloat {
        guard t > start, start < 1 else { return t >= 1 ? 1 : 0 }
        let k = min((t - start) / (1 - start), 1)
        return k * k * (3 - 2 * k)
    }

    /// Strokes a polyline segment-by-segment with a per-segment width and colour,
    /// giving a genuine source→mouth taper and letting the mouth fade its bank /
    /// blend its body tone (a single Path stroke can't vary either). Round caps
    /// overlap to hide the seams.
    private static func strokeTapered(_ pts: [CGPoint],
                                      into ctx: inout GraphicsContext,
                                      colorAt: (Int) -> Color,
                                      widthAt: (Int) -> CGFloat,
                                      offset: CGVector) {
        for i in 0..<(pts.count - 1) {
            let w = (widthAt(i) + widthAt(i + 1)) / 2
            guard w > 0 else { continue }
            var seg = Path()
            seg.move(to: pts[i].offset(offset))
            seg.addLine(to: pts[i + 1].offset(offset))
            ctx.stroke(seg, with: .color(colorAt(i)), style: StrokeStyle(lineWidth: w, lineCap: .round))
        }
    }

    // MARK: - Ocean / coast (§07.3.5)

    private static func drawCoast(_ coast: TerrainCoast,
                                  into ctx: inout GraphicsContext,
                                  palette: TerrainPalette) {
        guard coast.coastline.count >= 2 else { return }

        // CAMERA PATH (KAN-24): the smoothed shore and its per-vertex seaward units
        // arrive precomputed and projected (`sampled` / `bandSeaward`), so the depth
        // bands are just `sampled[i] + bandSeaward[i] * offset` — no per-frame
        // re-sampling and no point-in-sea probing (which on the organic Windrise
        // coast cost hundreds of ms per frame). The band OFFSET stays in screen points
        // (10 / 22), so the bands are the same fixed width at every zoom, identical to
        // the authored path below.
        if coast.sampled.count >= 2, coast.bandSeaward.count == coast.sampled.count {
            let sampled = coast.sampled
            seaBandFromUnits(sampled, seawardUnit: coast.bandSeaward, seaCorners: coast.seaCorners,
                             offset: 0, color: palette.water.highlight, into: &ctx)
            seaBandFromUnits(sampled, seawardUnit: coast.bandSeaward, seaCorners: coast.seaCorners,
                             offset: 10, color: palette.water.base, into: &ctx)
            seaBandFromUnits(sampled, seawardUnit: coast.bandSeaward, seaCorners: coast.seaCorners,
                             offset: 22, color: palette.water.shadow, into: &ctx)
            let shore = smoothedPath(coast.coastline, closed: false)
            ctx.stroke(shore, with: .color(palette.surf),
                       style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            return
        }

        // AUTHORED PATH (P1 specimen / P2 harness, aspect-fit): compute the sampled
        // shore + its fill polygon and resolve the seaward side per vertex here.
        // Depth bands offset each shore SAMPLE along its own per-vertex seaward
        // normal — so on a wrapped/L-shaped sea the bands follow the coast around
        // the corner instead of shearing into self-intersecting shards (KAN-23).
        let sampled = sampledCurve(coast.coastline)
        var seaPoly = sampled
        seaPoly.append(contentsOf: coast.seaCorners)

        // Three flat depth bands: fill the whole sea lightest first, then two copies
        // offset seaward and progressively darker, so near-shore strips reveal the
        // lighter bands (shallow → deep, no blend).
        seaBand(sampled: sampled, seaPoly: seaPoly, seaCorners: coast.seaCorners,
                seaward: coast.seaward, offset: 0, color: palette.water.highlight, into: &ctx)
        seaBand(sampled: sampled, seaPoly: seaPoly, seaCorners: coast.seaCorners,
                seaward: coast.seaward, offset: 10, color: palette.water.base, into: &ctx)
        seaBand(sampled: sampled, seaPoly: seaPoly, seaCorners: coast.seaCorners,
                seaward: coast.seaward, offset: 22, color: palette.water.shadow, into: &ctx)

        // Pale surf stroke on the true coastline (matches the lake shoreline rim).
        let shore = smoothedPath(coast.coastline, closed: false)
        ctx.stroke(shore, with: .color(palette.surf),
                   style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
    }

    private static func seaBand(sampled: [CGPoint],
                                seaPoly: [CGPoint],
                                seaCorners: [CGPoint],
                                seaward: CGVector,
                                offset: CGFloat,
                                color: Color,
                                into ctx: inout GraphicsContext) {
        let shifted = offset == 0
            ? sampled
            : MapGeometry.offsetSeaward(sampled, seaPoly: seaPoly, seawardHint: seaward, offset: offset)
        fillSeaBand(shifted, seaCorners: seaCorners, color: color, into: &ctx)
    }

    /// A depth band from precomputed per-vertex seaward units (KAN-24 camera path):
    /// each vertex is offset seaward by the fixed screen `offset`, then the strip is
    /// closed out to the two sea corners and filled.
    private static func seaBandFromUnits(_ sampled: [CGPoint],
                                         seawardUnit: [CGVector],
                                         seaCorners: [CGPoint],
                                         offset: CGFloat,
                                         color: Color,
                                         into ctx: inout GraphicsContext) {
        if offset == 0 {
            fillSeaBand(sampled, seaCorners: seaCorners, color: color, into: &ctx)
            return
        }
        var shifted: [CGPoint] = []
        shifted.reserveCapacity(sampled.count)
        for i in 0..<sampled.count {
            shifted.append(CGPoint(x: sampled[i].x + seawardUnit[i].dx * offset,
                                   y: sampled[i].y + seawardUnit[i].dy * offset))
        }
        fillSeaBand(shifted, seaCorners: seaCorners, color: color, into: &ctx)
    }

    private static func fillSeaBand(_ shifted: [CGPoint],
                                    seaCorners: [CGPoint],
                                    color: Color,
                                    into ctx: inout GraphicsContext) {
        var path = Path()
        guard let first = shifted.first else { return }
        path.move(to: first)
        for p in shifted.dropFirst() { path.addLine(to: p) }
        for corner in seaCorners { path.addLine(to: corner) }
        path.closeSubpath()
        ctx.fill(path, with: .color(color))
    }

    // MARK: - Roads & trek path (§07.3.7)

    private static func drawPath(_ path: TerrainPath,
                                 into ctx: inout GraphicsContext,
                                 palette: TerrainPalette) {
        switch path.style {
        case .trek:
            let curve = smoothedPath(path.points, closed: false)
            ctx.stroke(curve, with: .color(palette.ink),
                       style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [8, 6]))
        case .road:
            let curve = smoothedPath(path.points, closed: false)
            ctx.stroke(curve, with: .color(palette.ink),
                       style: StrokeStyle(lineWidth: 3, lineCap: .round))
        case .majorRoad:
            for side in [CGFloat(2.5), CGFloat(-2.5)] {
                let curve = smoothedPath(offsetPolyline(path.points, by: side), closed: false)
                ctx.stroke(curve, with: .color(palette.ink),
                           style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
        }
    }

    // MARK: - Settlements (§07.3.8)

    private static func drawHome(_ g: TerrainGlyph,
                                 into ctx: inout GraphicsContext,
                                 palette: TerrainPalette) {
        let w = g.size.width, h = g.size.height
        let wallH = h * 0.55
        let wall = CGRect(x: g.base.x - w / 2, y: g.base.y - wallH, width: w, height: wallH)
        ctx.fill(Path(wall), with: .color(palette.card))
        ctx.stroke(Path(wall), with: .color(palette.ink), lineWidth: 1.5)

        let roofBaseY = g.base.y - wallH
        let apex = CGPoint(x: g.base.x, y: g.base.y - h)
        let left = CGPoint(x: g.base.x - w / 2 - 1, y: roofBaseY)
        let right = CGPoint(x: g.base.x + w / 2 + 1, y: roofBaseY)
        let mid = CGPoint(x: g.base.x, y: roofBaseY)
        ctx.fill(triangle(apex, left, mid), with: .color(palette.roof.highlight))
        ctx.fill(triangle(apex, right, mid), with: .color(palette.roof.shadow))
        var roofOutline = Path()
        roofOutline.move(to: left)
        roofOutline.addLine(to: apex)
        roofOutline.addLine(to: right)
        ctx.stroke(roofOutline, with: .color(palette.ink),
                   style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
    }

    // MARK: - Pins & Cinzel chips (§06 / §07.6 — always last)

    private static func drawPin(_ pin: TerrainPin,
                                into ctx: inout GraphicsContext,
                                palette: TerrainPalette) {
        let accent = palette.accent(pin.accentToken)
        let r: CGFloat = pin.state == .next ? 9 : 7
        // Head sits above the tip by more than a radius so the tip is a real point
        // below the round head (a teardrop, not a bare circle).
        let head = CGPoint(x: pin.position.x, y: pin.position.y - r * 1.7)
        let teardrop = teardropPath(tip: pin.position, headCenter: head, radius: r)

        // §08 destination rule: the end destination's name chip ALWAYS shows,
        // whatever its state; otherwise only the single "next" is statically
        // labelled (reached labels appear on tap).
        let showsChip = pin.state == .next || pin.isDestination

        // §08 "Waypoint & marker states": a further-unreached waypoint is outline
        // only — 2pt dashed ink at 60%, no fill, no dot. But if it's the
        // destination, its chip still renders above the dashed outline.
        if pin.state == .upcoming {
            ctx.stroke(teardrop, with: .color(palette.ink.opacity(0.6)),
                       style: StrokeStyle(lineWidth: 2, lineJoin: .round, dash: [3, 3]))
            if showsChip {
                drawChip(pin.name, above: head, headRadius: r, into: &ctx, palette: palette)
            }
            return
        }

        // Hard offset shadow (§06 "2px offset shadow"): a solid, always-dark copy,
        // no blur — the same tone as the mountain shadow so it never inverts.
        ctx.fill(teardrop.offsetBy(dx: 1.5, dy: 2), with: .color(palette.hardShadow))

        // The single "next" waypoint gets an accent/reward emphasis ring (§08).
        if pin.state == .next {
            let ring = Path(ellipseIn: CGRect(x: head.x - r - 3, y: head.y - r - 3,
                                              width: (r + 3) * 2, height: (r + 3) * 2))
            ctx.stroke(ring, with: .color(palette.accent(DesignToken.reward)), lineWidth: 3)
        }

        // Reached / next both fill solid at 100% (§08).
        ctx.fill(teardrop, with: .color(accent))
        ctx.stroke(teardrop, with: .color(palette.ink), lineWidth: 3)

        // Center dot in the head.
        let dot = Path(ellipseIn: CGRect(x: head.x - r * 0.32, y: head.y - r * 0.32,
                                         width: r * 0.64, height: r * 0.64))
        ctx.fill(dot, with: .color(palette.card))

        // The "next" waypoint and the end destination both carry a static chip.
        if showsChip {
            drawChip(pin.name, above: head, headRadius: r, into: &ctx, palette: palette)
        }
    }

    private static func drawChip(_ name: String,
                                 above head: CGPoint,
                                 headRadius r: CGFloat,
                                 into ctx: inout GraphicsContext,
                                 palette: TerrainPalette) {
        // Cinzel-register display face for a milestone name (§03).
        let text = Text(name)
            .font(.system(size: 11, weight: .bold, design: .serif))
            .foregroundStyle(palette.ink)
        let resolved = ctx.resolve(text)
        let textSize = resolved.measure(in: CGSize(width: 240, height: 60))
        let padH: CGFloat = 8, padV: CGFloat = 4
        let chipW = textSize.width + padH * 2
        let chipH = textSize.height + padV * 2
        let chipRect = CGRect(x: head.x - chipW / 2,
                              y: head.y - r - 8 - chipH,
                              width: chipW, height: chipH)
        let chip = Path(roundedRect: chipRect, cornerRadius: 7)
        ctx.fill(chip, with: .color(palette.card))
        ctx.stroke(chip, with: .color(palette.ink), lineWidth: 2)
        ctx.draw(resolved, at: CGPoint(x: chipRect.midX, y: chipRect.midY), anchor: .center)
    }

    // MARK: - Shared facet & geometry helpers

    /// Corner-clip facets for soft shapes (§07.1): a top highlight facet and a
    /// bottom shadow facet clipped to the silhouette, leaving a base mid band —
    /// the same three-tone read as the character rig's FacetPatch. The two
    /// facets' inner edges are NOT parallel full-width lines: the highlight's
    /// lower edge and the shadow's upper edge cross near the right, so the visible
    /// mid-tone seam is a thin band that TAPERS and pinches out before reaching
    /// the shape's ends (the original kit's clip recipe), never a hard diagonal
    /// running the whole length. Bounding-box fractions match the design PDF:
    ///   highlight  polygon(0 0, 100% 0, 100% 42%, 0 66%)
    ///   shadow     polygon(100% 38%, 100% 100%, 18% 100%, 0 74%)
    private static func cornerClipFacets(_ path: Path,
                                         into ctx: inout GraphicsContext,
                                         highlight: Color,
                                         shadow: Color) {
        let b = path.boundingRect
        func p(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint {
            CGPoint(x: b.minX + b.width * fx, y: b.minY + b.height * fy)
        }
        ctx.drawLayer { layer in
            layer.clip(to: path)
            var hl = Path()
            hl.move(to: p(0, 0))
            hl.addLine(to: p(1, 0))
            hl.addLine(to: p(1, 0.42))
            hl.addLine(to: p(0, 0.66))
            hl.closeSubpath()
            layer.fill(hl, with: .color(highlight))

            var sh = Path()
            sh.move(to: p(1, 0.38))
            sh.addLine(to: p(1, 1))
            sh.addLine(to: p(0.18, 1))
            sh.addLine(to: p(0, 0.74))
            sh.closeSubpath()
            layer.fill(sh, with: .color(shadow))
        }
    }

    private static func triangle(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Path {
        var p = Path()
        p.move(to: a)
        p.addLine(to: b)
        p.addLine(to: c)
        p.closeSubpath()
        return p
    }

    private static func teardropPath(tip: CGPoint, headCenter: CGPoint, radius r: CGFloat) -> Path {
        // A round head with two straight sides tapering to the tip below it. The
        // sides are the tangents from the (external) tip to the head circle; the
        // arc is the MAJOR arc over the top of the head.
        //
        // Canvas y is flipped, so `clockwise: false` sweeps visually clockwise —
        // starting at the lower-left tangent (baseAngle + α) and going up over the
        // top to the lower-right tangent (baseAngle − α) is that clockwise sweep,
        // i.e. the dome, not the minor arc under the head.
        var p = Path()
        let d = hypot(tip.x - headCenter.x, tip.y - headCenter.y)
        guard d > r else {
            return Path(ellipseIn: CGRect(x: headCenter.x - r, y: headCenter.y - r,
                                          width: r * 2, height: r * 2))
        }
        let alpha = acos(r / d)                                       // tangent half-angle
        let baseAngle = atan2(tip.y - headCenter.y, tip.x - headCenter.x) // toward the tip
        p.move(to: tip)
        p.addArc(center: headCenter, radius: r,
                 startAngle: .radians(baseAngle + alpha),
                 endAngle: .radians(baseAngle - alpha),
                 clockwise: false)
        p.addLine(to: tip)
        p.closeSubpath()
        return p
    }

    // MARK: - Curve smoothing (Catmull-Rom)

    /// A smoothed `Path` through control points via Catmull-Rom → cubic Bézier.
    /// A few jittered points read as an organic shore / meander.
    private static func smoothedPath(_ pts: [CGPoint], closed: Bool) -> Path {
        var path = Path()
        guard pts.count > 1 else {
            if let p = pts.first { path.move(to: p) }
            return path
        }
        guard pts.count > 2 else {
            path.move(to: pts[0]); path.addLine(to: pts[1])
            if closed { path.closeSubpath() }
            return path
        }
        path.move(to: pts[0])
        let n = pts.count
        let last = closed ? n : n - 1
        for i in 0..<last {
            let p0 = pts[(i - 1 + n) % n]
            let p1 = pts[i % n]
            let p2 = pts[(i + 1) % n]
            let p3 = pts[(i + 2) % n]
            // Open curves clamp the phantom endpoints to the real ends.
            let a = (closed || i > 0) ? p0 : p1
            let d = (closed || i + 2 < n) ? p3 : p2
            let c1 = CGPoint(x: p1.x + (p2.x - a.x) / 6, y: p1.y + (p2.y - a.y) / 6)
            let c2 = CGPoint(x: p2.x - (d.x - p1.x) / 6, y: p2.y - (d.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        if closed { path.closeSubpath() }
        return path
    }

    /// Samples the smoothed curve into many points (for width-tapered strokes and
    /// offset coastline bands).
    private static func sampledCurve(_ pts: [CGPoint], perSegment: Int = 10) -> [CGPoint] {
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

    private static func cubic(_ p0: CGPoint, _ c1: CGPoint, _ c2: CGPoint, _ p1: CGPoint, _ t: CGFloat) -> CGPoint {
        let mt = 1 - t
        let a = mt * mt * mt
        let b = 3 * mt * mt * t
        let c = 3 * mt * t * t
        let d = t * t * t
        return CGPoint(x: a * p0.x + b * c1.x + c * c2.x + d * p1.x,
                       y: a * p0.y + b * c1.y + c * c2.y + d * p1.y)
    }

    private static func offsetPolyline(_ pts: [CGPoint], by dist: CGFloat) -> [CGPoint] {
        guard pts.count > 1 else { return pts }
        return pts.indices.map { i in
            let prev = pts[max(i - 1, 0)]
            let next = pts[min(i + 1, pts.count - 1)]
            let dir = CGVector(dx: next.x - prev.x, dy: next.y - prev.y).normalized
            let normal = CGVector(dx: -dir.dy, dy: dir.dx)
            return pts[i].offset(CGVector(dx: normal.dx * dist, dy: normal.dy * dist))
        }
    }
}

// MARK: - Small point/vector conveniences (private to terrain rendering)

private extension CGPoint {
    func offset(_ v: CGVector) -> CGPoint { CGPoint(x: x + v.dx, y: y + v.dy) }
    func offsetBy(dx: CGFloat, dy: CGFloat) -> CGPoint { CGPoint(x: x + dx, y: y + dy) }
}

private extension CGVector {
    var normalized: CGVector {
        let len = (dx * dx + dy * dy).squareRoot()
        return len == 0 ? CGVector(dx: 0, dy: 0) : CGVector(dx: dx / len, dy: dy / len)
    }
}

private extension Path {
    func offsetBy(dx: CGFloat, dy: CGFloat) -> Path {
        applying(CGAffineTransform(translationX: dx, y: dy))
    }
}
