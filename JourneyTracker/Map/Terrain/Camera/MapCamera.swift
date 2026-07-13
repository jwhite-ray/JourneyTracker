//
//  MapCamera.swift
//  JourneyTracker
//
//  The map camera (KAN-20, P3 of epic KAN-16). A PURE value type — the single
//  camera transform the App Concept doc calls for ("each fantasy journey has a
//  fixed logical map-unit coordinate space; rendering applies one camera
//  transform"). It replaces `TerrainRenderer`'s P1 aspect-fit stand-in.
//
//  A camera is just a `center` (map units) and a `zoom` (screen POINTS per map
//  unit). Everything else — the map→screen projection, the visible rect, and the
//  two framings the App Concept doc names (chapter view and full-journey
//  overview) — derives from those two numbers. No SwiftUI, no wall-clock, no
//  gesture state here: this is a pure value type, unit-testable in isolation.
//
//  Coordinate model: a map point `p` projects to screen as
//      screen = (p - center) * zoom + viewport/2
//  so `center` sits at the middle of the viewport and `zoom` scales map units up
//  to points. The visible rect is the pre-image of the viewport under that map.
//

import CoreGraphics

struct MapCamera: Equatable {
    /// The map-unit point held at the center of the viewport.
    var center: CGPoint
    /// Screen points per map unit. Larger = more zoomed in (fewer map units on
    /// screen). Always > 0.
    var zoom: CGFloat

    init(center: CGPoint, zoom: CGFloat) {
        self.center = center
        self.zoom = max(zoom, 0.0000001)
    }

    // MARK: - Projection

    /// Map units → screen points, for a given viewport.
    func project(_ p: CGPoint, in viewport: CGSize) -> CGPoint {
        CGPoint(x: (p.x - center.x) * zoom + viewport.width / 2,
                y: (p.y - center.y) * zoom + viewport.height / 2)
    }

    /// Screen points → map units (the inverse of `project`).
    func unproject(_ s: CGPoint, in viewport: CGSize) -> CGPoint {
        CGPoint(x: (s.x - viewport.width / 2) / zoom + center.x,
                y: (s.y - viewport.height / 2) / zoom + center.y)
    }

    /// The map-unit rectangle currently visible in `viewport` — the pre-image of
    /// the screen. The renderer culls to this (App Concept doc: "single-pass
    /// Canvas, visible-rect culled").
    func visibleRect(in viewport: CGSize) -> CGRect {
        let w = viewport.width / zoom
        let h = viewport.height / zoom
        return CGRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)
    }

    // MARK: - Zoom clamping

    /// Returns a copy with `zoom` clamped into `[min, max]`, holding `center`.
    func clampingZoom(min lo: CGFloat, max hi: CGFloat) -> MapCamera {
        MapCamera(center: center, zoom: Swift.min(Swift.max(zoom, lo), hi))
    }

    // MARK: - Framing

    /// A camera that fits `rect` (map units) into `viewport`, honoring an inset of
    /// `padding` screen points on every side. `center` lands at the rect's middle.
    static func fitting(_ rect: CGRect, in viewport: CGSize, padding: CGFloat = 24) -> MapCamera {
        let availW = max(viewport.width - padding * 2, 1)
        let availH = max(viewport.height - padding * 2, 1)
        let w = max(rect.width, 0.0001)
        let h = max(rect.height, 0.0001)
        let zoom = min(availW / w, availH / h)
        return MapCamera(center: CGPoint(x: rect.midX, y: rect.midY), zoom: zoom)
    }

    /// Full-journey overview: fit the authored `bounds` into the viewport. This is
    /// the map's minimum zoom (the whole journey on one screen) and the toggle's
    /// "overview" state.
    static func fullJourney(bounds: CGRect, in viewport: CGSize, padding: CGFloat = 28) -> MapCamera {
        fitting(bounds, in: viewport, padding: padding)
    }

    /// Chapter view: frame the current leg (last-reached waypoint → next waypoint)
    /// with the marker centered (Justin's KAN-20 ruling). Zoom is chosen so BOTH
    /// leg endpoints stay on screen even though the camera centers on the marker
    /// — we size to the larger of (marker→lastReached) and (marker→next) on each
    /// axis, so a marker part-way along its leg never pushes an endpoint off.
    ///
    /// `extraPoints` lets a caller include the leg's intermediate trek vertices so
    /// a meander that bows outside the endpoint box still fits.
    static func chapter(lastReached: CGPoint,
                        next: CGPoint,
                        marker: CGPoint,
                        extraPoints: [CGPoint] = [],
                        in viewport: CGSize,
                        padding: CGFloat = 40) -> MapCamera {
        var halfW: CGFloat = 1
        var halfH: CGFloat = 1
        for p in [lastReached, next] + extraPoints {
            halfW = max(halfW, abs(p.x - marker.x))
            halfH = max(halfH, abs(p.y - marker.y))
        }
        let availW = max(viewport.width - padding * 2, 1)
        let availH = max(viewport.height - padding * 2, 1)
        // Each half-extent must fit in half the available viewport.
        let zoom = min((availW / 2) / halfW, (availH / 2) / halfH)
        return MapCamera(center: marker, zoom: zoom)
    }
}
