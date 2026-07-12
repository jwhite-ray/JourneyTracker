//
//  TerrainSpecimenView.swift
//  JourneyTracker
//
//  The KAN-18 (P1) viewer: parchment ground + the faceted-terrain specimen drawn
//  in ONE `Canvas` pass, nothing else. This is the look-proof surface the team
//  reviews; it is not wired into the main journey UI (the real terrain lands
//  under KAN-7's map at P4). It is reachable behind the existing Debug tab as an
//  unobtrusive dev entry, and both previews render it offscreen for review.
//

import SwiftUI

struct TerrainSpecimenView: View {
    /// Resolve `terrain/*` tokens against the live appearance so light / Deepdark
    /// both come out correct inside the Canvas pass.
    @Environment(\.self) private var environment

    /// Authored once — the specimen is static (§07.7). Rebuilt only if the view
    /// is recreated, never per frame.
    private let scene = TerrainSpecimenScene.make()

    var body: some View {
        Canvas { context, size in
            let palette = TerrainPalette(environment: environment)
            TerrainRenderer.render(scene, into: &context, size: size, palette: palette)
        }
        .background(Color(token: DesignToken.parchment))
        .ignoresSafeArea()
        .navigationTitle("Terrain specimen")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Terrain specimen — light") {
    TerrainSpecimenView()
        .preferredColorScheme(.light)
}

#Preview("Terrain specimen — Deepdark") {
    TerrainSpecimenView()
        .preferredColorScheme(.dark)
}
