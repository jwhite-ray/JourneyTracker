//
//  FullScreenMapView.swift
//  JourneyTracker
//
//  The full-screen, gesture-driven map surface (KAN-20, P3). Pinch-zoom / pan
//  live HERE (Justin's ruling), backed by `ScrollableMapSurface`'s UIScrollView
//  for native anchoring, momentum, rubber-banding and double-tap zoom. The map is
//  rendered by a screen-sized, culled + LOD-thinned `Canvas` overlay driven by the
//  scroll view's `MapCamera`. A floating control toggles chapter view ↔
//  full-journey overview (animated), and a debug overlay reports the last render's
//  build time and drawn / culled / thinned counts — the perf-gate evidence.
//

import SwiftUI

struct FullScreenMapView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.self) private var environment

    let presentation: JourneyMapPresentation
    /// Wren's §04 pose (resting when the journey is complete). Passed through from
    /// the journey view so both surfaces show the same marker.
    var markerResting: Bool = false
    var initialFraming: MapFraming = .chapter
    /// Debug entries turn the perf overlay on; a real P4 surface would leave it off.
    var showsPerfOverlay: Bool = false

    @StateObject private var controller: MapCameraController
    @State private var framing: MapFraming
    /// Rolling frame/plan timing for the perf overlay. A reference type held in
    /// `@State` so recording a sample (in `body`, per frame) never itself triggers a
    /// SwiftUI invalidation — the overlay reads it on its own 4 Hz clock (KAN-24).
    @State private var perf = MapPerfTracker()

    init(presentation: JourneyMapPresentation,
         markerResting: Bool = false,
         initialFraming: MapFraming = .chapter,
         showsPerfOverlay: Bool = false) {
        self.presentation = presentation
        self.markerResting = markerResting
        self.initialFraming = initialFraming
        self.showsPerfOverlay = showsPerfOverlay
        _framing = State(initialValue: initialFraming)
        let b = presentation.authoring.bounds
        _controller = StateObject(wrappedValue: MapCameraController(
            camera: MapCamera(center: CGPoint(x: b.midX, y: b.midY), zoom: 1)))
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            // Time the plan ONLY when the perf overlay is on — production builds pay
            // nothing for the timing/recording (KAN-24, Rooster nit 5).
            let t0 = showsPerfOverlay ? CFAbsoluteTimeGetCurrent() : 0
            // Only build a plan once the scroll view has published a real camera —
            // otherwise the placeholder camera flashes an extreme zoom for a frame.
            // The plan uses the presentation's precomputed geometry cache (KAN-24),
            // so it only projects + culls + LOD-thins — no per-frame smoothing or
            // sea-polygon probing.
            let plan = controller.isReady
                ? MapRenderPlanner.plan(presentation.scene,
                                        geometry: presentation.geometry,
                                        camera: controller.camera,
                                        viewport: size,
                                        milesPerMapUnit: presentation.milesPerMapUnit)
                : nil
            // Record plan time + frame interval + the latest stats/zoom into the
            // tracker. `body` re-evaluates once per camera change (≈ once per rendered
            // frame during a gesture), so the delta between records is a rough frame
            // interval. This only mutates the reference tracker (never invalidates the
            // view); the overlay reads a snapshot on its own 4 Hz clock, so its text
            // never depends on per-frame values.
            let _ = (showsPerfOverlay ? plan : nil).map {
                perf.record(planMs: (CFAbsoluteTimeGetCurrent() - t0) * 1000,
                            stats: $0.stats, zoom: controller.camera.zoom, now: t0)
            }

            ZStack(alignment: .top) {
                Color(token: DesignToken.parchment)

                ScrollableMapSurface(presentation: presentation,
                                     controller: controller,
                                     initialFraming: initialFraming)

                Canvas { ctx, sz in
                    guard let plan else { return }
                    let palette = TerrainPalette(environment: environment)
                    TerrainRenderer.drawPlanned(plan.scene, into: &ctx, viewport: sz, palette: palette)
                }
                .allowsHitTesting(false)

                // Wren, projected through the LIVE scroll-view camera so it tracks
                // pinch/pan. `body` re-evaluates on every published camera change, so
                // re-projecting the marker each pass is cheap and keeps it pinned to
                // its point on the trek path as the user moves the map.
                if controller.isReady, presentation.milesPerMapUnit > 0 {
                    WrenMarker(resting: markerResting)
                        .position(controller.camera.project(presentation.markerPosition, in: size))
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("map.marker")
                }

                controls(size: size)

                if showsPerfOverlay, plan != nil {
                    perfOverlay()
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - Controls

    private func controls(size: CGSize) -> some View {
        HStack {
            MapIconButton(systemName: "xmark", role: .recessive) { dismiss() }
                .accessibilityLabel("Close map")
            Spacer()
            MapIconButton(systemName: framing == .chapter
                          ? "arrow.up.left.and.arrow.down.right"
                          : "scope") {
                framing = (framing == .chapter) ? .overview : .chapter
                let target = framing == .chapter
                    ? presentation.chapterCamera(viewport: size)
                    : presentation.overviewCamera(viewport: size)
                controller.frame(target, animated: true)
            }
            .accessibilityLabel(framing == .chapter ? "Show full journey" : "Show current chapter")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private func perfOverlay() -> some View {
        // Refresh the numbers on a 4 Hz clock — NOT once per rendered frame — so the
        // overlay's text layout never becomes part of the gesture's hot path (KAN-24).
        // Everything shown is read from the tracker snapshot (stats/zoom included), so
        // the closure captures no per-frame value.
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let s = perf.snapshot()
            let stats = s.stats
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "plan %.2f ms · frame ~%.1f ms (%.0f fps) · zoom %.3f pt/u",
                            s.planMs, s.frameMs, s.fps, s.zoom))
                Text("scatter: drawn \(stats.drawnScatter) · culled \(stats.culledScatter) · thinned \(stats.thinnedScatter) · pool \(stats.totalScatter)")
                Text("homes \(stats.drawnHomes) · water \(stats.drawnWaterShapes) · paths \(stats.drawnPaths) · pins \(stats.drawnPins)")
            }
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(Color(token: DesignToken.ink))
            .padding(10)
            .background(Color(token: DesignToken.card).opacity(0.92), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(token: DesignToken.ink), lineWidth: 2))
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
            .accessibilityIdentifier("map.perfOverlay")
        }
    }
}

/// Rolling plan-time / frame-interval tracker for the perf overlay (KAN-24). A
/// reference type: `record` is called from `body` per frame but mutates only this
/// object, so it never invalidates SwiftUI; the overlay samples it on a 4 Hz clock.
/// `frameMs` is an exponential moving average of the interval between successive
/// records (≈ the rendered frame interval during a gesture), so a smooth gesture
/// reads near the display's frame time and a stalling one reads high.
final class MapPerfTracker {
    private var lastRecord: CFAbsoluteTime = 0
    private var emaFrameMs: Double = 0
    private var lastPlanMs: Double = 0
    private var lastStats = TerrainRenderStats()
    private var lastZoom: CGFloat = 0

    struct Snapshot { var planMs: Double; var frameMs: Double; var fps: Double
                      var zoom: CGFloat; var stats: TerrainRenderStats }

    func record(planMs: Double, stats: TerrainRenderStats, zoom: CGFloat, now: CFAbsoluteTime) {
        lastPlanMs = planMs
        lastStats = stats
        lastZoom = zoom
        if lastRecord > 0 {
            let dt = (now - lastRecord) * 1000
            // Ignore long idle gaps (no gesture) so the average reflects active frames.
            if dt > 0, dt < 250 {
                emaFrameMs = emaFrameMs == 0 ? dt : emaFrameMs * 0.8 + dt * 0.2
            }
        }
        lastRecord = now
    }

    func snapshot() -> Snapshot {
        let fps = emaFrameMs > 0 ? min(120, 1000 / emaFrameMs) : 0
        return Snapshot(planMs: lastPlanMs, frameMs: emaFrameMs, fps: fps,
                        zoom: lastZoom, stats: lastStats)
    }
}

/// A calm floating map control, per §08's button rules (radius 12, 3pt ink
/// stroke, token fill, no shadow). `recessive` uses the surface fill (close);
/// otherwise the primary accent (framing toggle).
struct MapIconButton: View {
    enum Role { case primary, recessive }
    let systemName: String
    var role: Role = .primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(token: DesignToken.ink))
                .frame(width: 44, height: 44)
                .background(Color(token: role == .primary ? DesignToken.accentPrimary : DesignToken.card),
                            in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(token: DesignToken.ink), lineWidth: 3))
        }
        .buttonStyle(PressDownButtonStyle())
    }
}

/// §08 button press state: translate down 2pt on press, no shadow to collapse.
private struct PressDownButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(y: configuration.isPressed ? 2 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
