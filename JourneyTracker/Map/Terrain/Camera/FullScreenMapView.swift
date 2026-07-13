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
    var initialFraming: MapFraming = .chapter
    /// Debug entries turn the perf overlay on; a real P4 surface would leave it off.
    var showsPerfOverlay: Bool = false

    @StateObject private var controller: MapCameraController
    @State private var framing: MapFraming

    init(presentation: JourneyMapPresentation,
         initialFraming: MapFraming = .chapter,
         showsPerfOverlay: Bool = false) {
        self.presentation = presentation
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
            let t0 = CFAbsoluteTimeGetCurrent()
            // Only build a plan once the scroll view has published a real camera —
            // otherwise the placeholder camera flashes an extreme zoom for a frame.
            let plan = controller.isReady
                ? MapRenderPlanner.plan(presentation.scene,
                                        camera: controller.camera,
                                        viewport: size,
                                        milesPerMapUnit: presentation.milesPerMapUnit)
                : nil
            let buildMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000

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

                controls(size: size)

                if showsPerfOverlay, let plan {
                    perfOverlay(stats: plan.stats, buildMs: buildMs)
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

    private func perfOverlay(stats: TerrainRenderStats, buildMs: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(format: "build %.2f ms · zoom %.3f pt/u", buildMs, controller.camera.zoom))
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
