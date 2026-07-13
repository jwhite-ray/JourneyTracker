//
//  StaticJourneyMapView.swift
//  JourneyTracker
//
//  The calm "journey view" surface (KAN-20, P3). A STATIC map (Justin's ruling):
//  no gestures, framed at chapter view (last-reached → next waypoint, marker
//  centered), with a floating expand button that presents the gesture-driven
//  `FullScreenMapView`. This is the surface the P4 journey tab will host; today
//  the debug entries drive it with sample / fixture data.
//
//  It renders the same culled + LOD-thinned plan as the full-screen map, just at a
//  fixed chapter camera and without a scroll view — so a day's progress is legible
//  (the whole point of chapter framing, App Concept doc) with zero interaction.
//

import SwiftUI

struct StaticJourneyMapView: View {
    @Environment(\.self) private var environment

    let presentation: JourneyMapPresentation
    /// Surfaced through to the full-screen map so its perf overlay can be enabled
    /// from a debug entry.
    var fullScreenPerfOverlay: Bool = false

    @State private var showFullScreen = false

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let camera = presentation.chapterCamera(viewport: size)
            // On a long journey the fixed chapter zoom is itself high-altitude, so
            // the size taper applies here too (item 8).
            let plan = MapRenderPlanner.plan(presentation.scene, geometry: presentation.geometry,
                                             camera: camera, viewport: size,
                                             milesPerMapUnit: presentation.milesPerMapUnit)

            ZStack(alignment: .bottomTrailing) {
                Color(token: DesignToken.parchment)

                Canvas { ctx, sz in
                    let palette = TerrainPalette(environment: environment)
                    TerrainRenderer.drawPlanned(plan.scene, into: &ctx, viewport: sz, palette: palette)
                }
                .allowsHitTesting(false)

                MapIconButton(systemName: "arrow.up.left.and.arrow.down.right") {
                    showFullScreen = true
                }
                .accessibilityLabel("Expand map")
                .accessibilityIdentifier("map.expandButton")
                .padding(.trailing, 16)
                .padding(.bottom, 20)
            }
            .frame(width: size.width, height: size.height)
        }
        .fullScreenCover(isPresented: $showFullScreen) {
            FullScreenMapView(presentation: presentation,
                              initialFraming: .chapter,
                              showsPerfOverlay: fullScreenPerfOverlay)
        }
    }
}
