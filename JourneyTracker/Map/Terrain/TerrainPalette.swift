//
//  TerrainPalette.swift
//  JourneyTracker
//
//  The single place terrain `terrain/*` tokens (§02) become concrete facet
//  triads. Each material carries its base mid-tone plus a highlight and shadow
//  derived at build time by the §07.1 facet rule (highlight +9% L, shadow −12% L,
//  shifted in HSB so a re-themed base carries through both facets — same trick as
//  the character rig, JourneyDesignTokens.facetHighlight/Shadow).
//
//  Tokens are resolved against the live `EnvironmentValues`, so light and
//  Deepdark both come out correct even though the resolution happens inside a
//  `Canvas` renderer rather than a normal view tree. No hex literals here or in
//  the renderer — only token names and derivations of them.
//

import SwiftUI

/// A resolved terrain material: the token's mid-tone and its two facet tones.
struct TerrainMaterial {
    let base: Color
    let highlight: Color
    let shadow: Color
    /// A darker-than-shadow tone for river banks and the like.
    let deep: Color
}

/// Every terrain token resolved for one appearance, plus the two ink/card tokens
/// the renderer needs (mountain hard shadow = ink per §07.3.1 / §09; home walls =
/// surface/card per §07.3.8).
struct TerrainPalette {
    let water: TerrainMaterial
    let forest: TerrainMaterial
    let stone: TerrainMaterial
    let snow: TerrainMaterial
    let sand: TerrainMaterial
    let grass: TerrainMaterial
    let marsh: TerrainMaterial
    let roof: TerrainMaterial

    let ink: Color
    let card: Color

    /// An always-dark tone for the mountain and pin hard offset shadows
    /// (§07.3.1). It must NOT invert with appearance — the plain `ink` token
    /// resolves to cream in Deepdark, which would turn every peak's shadow into a
    /// pale halo. This is the ink token resolved in the LIGHT appearance (the dark
    /// brown), pinned so a shadow always reads as a shadow in both modes.
    let hardShadow: Color

    /// A pale, desaturated near-snow tone derived from `terrain/water`, for the
    /// coast surf stroke and lake shoreline rim (§07.3.4/5 "pale" foam) — the
    /// plain water highlight was invisible sitting on the water-highlight band.
    let surf: Color

    /// The environment used to resolve tokens — kept so pins can resolve their
    /// per-waypoint accent tokens through the same appearance.
    let environment: EnvironmentValues

    init(environment: EnvironmentValues) {
        self.environment = environment
        func material(_ token: String) -> TerrainMaterial {
            TerrainPalette.material(named: token, in: environment)
        }
        water = material("terrain/water")
        forest = material("terrain/forest")
        stone = material("terrain/stone")
        snow = material("terrain/snow")
        sand = material("terrain/sand")
        grass = material("terrain/grass")
        marsh = material("terrain/marsh")
        roof = material("terrain/roof")
        ink = Color(token: DesignToken.ink)
        card = Color(token: DesignToken.card)

        var lightEnv = environment
        lightEnv.colorScheme = .light
        hardShadow = Color(Color(token: DesignToken.ink).resolve(in: lightEnv))
        surf = TerrainPalette.pale(named: "terrain/water", in: environment)
    }

    /// Resolves an accent design-token (a pin's `journey.theme` accent) through
    /// the same appearance the terrain was resolved for.
    func accent(_ token: String) -> Color { Color(token: token) }

    // MARK: - Facet derivation

    private static func material(named token: String, in env: EnvironmentValues) -> TerrainMaterial {
        let base = Color(token: token)
        let resolved = base.resolve(in: env)
        return TerrainMaterial(
            base: base,
            highlight: shiftBrightness(resolved, by: 0.09),
            shadow: shiftBrightness(resolved, by: -0.12),
            deep: shiftBrightness(resolved, by: -0.22)
        )
    }

    /// A pale, lower-saturation, higher-brightness derivation of a token — foam /
    /// shallows that reads distinctly against the water bands (§07.3.4/5).
    private static func pale(named token: String, in env: EnvironmentValues) -> Color {
        let resolved = Color(token: token).resolve(in: env)
        let ui = UIColor(red: CGFloat(resolved.red),
                         green: CGFloat(resolved.green),
                         blue: CGFloat(resolved.blue),
                         alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getHue(&h, saturation: &s, brightness: &b, alpha: &a) else {
            return Color(red: Double(resolved.red), green: Double(resolved.green), blue: Double(resolved.blue))
        }
        return Color(hue: Double(h),
                     saturation: Double(s * 0.45),
                     brightness: Double(min(b + 0.28, 1)),
                     opacity: 1)
    }

    /// §07.1 facet derivation: shift HSB brightness by `delta`, preserving hue,
    /// saturation and alpha. Operates on the already-appearance-resolved concrete
    /// components, so no dynamic-color / trait ambiguity inside the Canvas pass.
    private static func shiftBrightness(_ resolved: Color.Resolved, by delta: CGFloat) -> Color {
        let ui = UIColor(red: CGFloat(resolved.red),
                         green: CGFloat(resolved.green),
                         blue: CGFloat(resolved.blue),
                         alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getHue(&h, saturation: &s, brightness: &b, alpha: &a) else {
            return Color(red: Double(resolved.red), green: Double(resolved.green), blue: Double(resolved.blue))
        }
        let shifted = min(max(b + delta, 0), 1)
        return Color(hue: Double(h), saturation: Double(s), brightness: Double(shifted), opacity: Double(a))
    }
}
