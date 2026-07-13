//
//  TerrainGlyph.swift
//  JourneyTracker
//
//  The faceted-cartography glyph vocabulary (KAN-16, epic; this file lands in
//  P1 / KAN-18). Value types only — no drawing, no colors, no SwiftUI views.
//  A `TerrainScene` is an unordered bag of typed regions and point-anchored
//  glyphs; `TerrainRenderer` is what imposes the §07.6 fixed back-to-front draw
//  order on it, never the caller.
//
//  In P1 a scene is hand-authored by `TerrainSpecimenScene` to prove the look.
//  In P2 the seeded scatter generator (App Concept doc) produces the exact same
//  value types from region records + a seed — this model is deliberately shaped
//  so that generator can feed the renderer with no renderer change. Everything
//  here is in one flat point space; the P3 camera transform is applied at draw
//  time and is not this model's concern.
//

import CoreGraphics

// MARK: - Point-anchored scatter glyphs

/// The kinds of glyph that are *scattered* as many tiny jittered copies (§07.4)
/// or clustered (settlements). Each is anchored at a single point and sized;
/// path/region shapes (rivers, coast, lakes, ground cover, paths) are modelled
/// separately below because they are not point-anchored.
enum TerrainGlyphKind {
    /// §07.3.1 — bottom-anchored triangle, ridge-split, hard offset shadow.
    case mountain
    /// §07.3.2 — trunk + ridge-split canopy triangle.
    case conifer
    /// §07.3.8 — a single home in a settlement cluster (wall + faceted roof).
    case home
    /// §07.3.6 — a small grass tuft dotting a plains wash.
    case grassTuft
    /// §07.3.6 — a single wind-ridged dune mound.
    case dune
}

/// One scattered/clustered glyph. `base` is the bottom-center anchor point
/// (mountains, conifers, homes, tufts, dunes all grow *up* from their base, so
/// draw-sorting by `base.y` alone gives correct near-over-far layering, §07.4).
struct TerrainGlyph {
    var kind: TerrainGlyphKind
    /// Bottom-center anchor, in scene points.
    var base: CGPoint
    /// Footprint. `height` is the up-extent from `base`; `width` the span.
    var size: CGSize
    /// Snow cap on this peak (§07.3.1 — the exception, not the rule).
    var snowCap: Bool = false
    /// Autumn canopy triad instead of the green one (§07.3.2).
    var autumn: Bool = false
}

// MARK: - Path / region shapes

/// A closed, asymmetric water/land blob — lakes and marsh bodies (§07.3.4 /
/// §07.3.6). `ring` is the control polygon; the renderer smooths it with a
/// Catmull-Rom pass, so a handful of jittered points reads as an organic shore.
struct TerrainBlob {
    var ring: [CGPoint]
}

/// A river centerline, source → mouth (§07.3.3). The renderer strokes it three
/// times (bank / body / highlight ribbon) and tapers from `sourceWidth` at
/// point 0 to `mouthWidth` at the last point, so it reads as flowing downstream.
struct TerrainRiver {
    /// How a river's mouth meets the water it drains into (§07.3.3). `inland`
    /// rivers just taper to a point; `freshwater`/`sea` mouths MELT into the
    /// receiving body — the renderer fades the dark bank out and runs the body
    /// (same water token as the receiver) a short way in, so there's no seam. A
    /// `sea` mouth additionally transitions the body toward the shallow band tone.
    /// A `confluence` mouth is a tributary melting into a MAIN RIVER (KAN-23): it
    /// melts exactly like `freshwater` (bank fades, body runs on at the same water
    /// tone), but there is no lake/sea shore to truncate at — the render plan just
    /// overlaps a short fixed run into the main river so the join is fill-continuous.
    /// An `offMap` mouth exits the authored bounds (KAN-23 "drawing trumps the
    /// rules": a river may drain to an off-map sea/basin). It does NOT melt — there's
    /// no on-screen receiving water; the river runs full-width to/past the bounds
    /// edge and the renderer's bounds clip cuts it there, so it reads as flowing off
    /// the map. The render plan performs no shore truncation for it.
    enum Mouth { case inland, freshwater, sea, confluence, offMap }
    var centerline: [CGPoint]
    var sourceWidth: CGFloat = 9
    var mouthWidth: CGFloat = 13
    var mouth: Mouth = .inland
    /// How far (in the river's own coordinate space) the melting body runs PAST its
    /// authored mouth into the receiving water. Default 12 matches the P1/P2
    /// authored look; the P3 camera path overrides it with a SCALE-AWARE screen
    /// value clamped to the receiver's projected footprint, so a mouth never
    /// overshoots a tiny far-zoom lake (KAN-20 Gate 3).
    var meltRunIn: CGFloat = 12
}

/// A coastline (§07.3.5). `coastline` is the true shore polyline; `seaward` is
/// the unit-ish vector pointing from land toward open water — the renderer
/// offsets depth-band copies along it and closes each band's fill out to the
/// two `seaCorners` (the far, open-water corners of the scene edge).
struct TerrainCoast {
    var coastline: [CGPoint]
    var seaward: CGVector
    var seaCorners: [CGPoint]
}

/// Plains ground cover (§07.3.6): a low-opacity wash blob. Tufts that dot it are
/// separate `.grassTuft` glyphs so they draw with the scatter, not the fill.
struct TerrainPlains {
    var wash: TerrainBlob
}

/// Marsh ground cover (§07.3.6): a muted blob plus pill glints and leaning reeds.
struct TerrainMarsh {
    var body: TerrainBlob
    /// Centers of small pill-shaped water glints.
    var glints: [CGPoint]
    /// Reed strokes as (base, tip) leaning segments.
    var reeds: [Reed]
    struct Reed { var base: CGPoint; var tip: CGPoint }
}

/// Trek path & roads (§07.3.7) — all share the ink token, differ only in stroke.
struct TerrainPath {
    enum Style {
        /// Dot-dash trek path (§06 stroke): lineWidth 3, dash [8,6], round caps.
        case trek
        /// One solid 3pt ink stroke.
        case road
        /// Two parallel 3pt ink strokes.
        case majorRoad
    }
    var points: [CGPoint]
    var style: Style
}

/// A waypoint pin + Cinzel name chip (§06). Pins are UI, not terrain, and always
/// draw last (§07.6); the specimen draws them in the same Canvas so the look-proof
/// is self-contained. `accentToken` is a design-token name, never a literal.
struct TerrainPin {
    enum State { case reached, next, upcoming }
    var position: CGPoint
    var name: String
    var accentToken: String
    var state: State
    /// The journey's end destination. Its Cinzel name chip ALWAYS renders (§08
    /// destination rule), regardless of reached/next/upcoming — while its pin
    /// body still follows `state` (an unreached destination keeps the dashed 60%
    /// outline, but with its chip above it). Used by the renderer only.
    var isDestination: Bool = false
}

// MARK: - The scene

/// An authored map, as typed buckets. The renderer walks these in §07.6 order;
/// the caller never sequences draws. Scatter glyphs of every kind share one
/// `glyphs` array (the generator's natural output) and the renderer buckets them
/// by kind into their correct draw stage.
struct TerrainScene {
    /// The scene's authored coordinate space (its "map-unit bounds", App Concept
    /// doc). The renderer aspect-fits this into whatever `Canvas` size it gets —
    /// a stand-in for the P3 camera transform, which is not built here.
    var bounds: CGRect = CGRect(x: 0, y: 0, width: 390, height: 700)
    /// Coasts (§07.3.5). An ARRAY so a map can author more than one coast (a wrapped
    /// L-shaped sea authored as two arms, an inland sea plus an ocean, …) — KAN-23.
    /// The §07.6 draw order treats them as one stage (drawn first, back to front).
    var coasts: [TerrainCoast] = []
    var plains: [TerrainPlains] = []
    var marshes: [TerrainMarsh] = []
    var lakes: [TerrainBlob] = []
    var rivers: [TerrainRiver] = []
    var glyphs: [TerrainGlyph] = []
    var paths: [TerrainPath] = []
    var pins: [TerrainPin] = []

    /// Glyphs of one kind, sorted so nearer (lower on screen) draws last / on top
    /// (§07.4 draw order within a scatter).
    func glyphs(_ kind: TerrainGlyphKind) -> [TerrainGlyph] {
        glyphs.filter { $0.kind == kind }.sorted { $0.base.y < $1.base.y }
    }
}
