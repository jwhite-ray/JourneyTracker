//
//  MapTuningHarnessView.swift
//  JourneyTracker
//
//  The PERSISTENT map-tuning harness (KAN-19, P2 of epic KAN-16). This is the
//  future map-authoring surface — NOT a throwaway like a `Mockups/` variant (App
//  Concept doc: "The harness stays in the repo as the map-authoring surface").
//  It renders the seeded generator's output full-screen through the unchanged
//  `TerrainRenderer`, with live knobs for seed, density, jitter, and feather, and
//  a validation status line.
//
//  Determinism is asserted visibly: every regeneration runs the generator TWICE
//  with the same inputs and confirms identical glyph counts + positions (App
//  Concept doc's hard determinism requirement).
//

import SwiftUI

struct MapTuningHarnessView: View {
    @Environment(\.self) private var environment

    /// Authored once — the generator is a pure function of it (§07.7 static terrain).
    private let authoring = SampleJourneyMap.make()

    @State private var seed: UInt64 = SampleJourneyMap.make().seed
    @State private var seedText: String = String(SampleJourneyMap.make().seed)
    @State private var densityMultiplier: Double = 1
    @State private var jitterMultiplier: Double = 1
    @State private var featherMultiplier: Double = 1
    @State private var showControls = true

    private var tuning: MapGenerator.Tuning {
        MapGenerator.Tuning(seed: seed,
                            densityMultiplier: densityMultiplier,
                            jitterMultiplier: jitterMultiplier,
                            featherMultiplier: featherMultiplier)
    }

    private var violations: [MapViolation] { MapValidator.validate(authoring) }

    var body: some View {
        // Generate the live scene (cheap — a few hundred value types). Regenerated
        // on every knob change because `tuning` feeds it.
        let scene = MapGenerator.generateUnchecked(authoring, tuning: tuning)
        // Determinism check: a second identical generation must match exactly.
        let deterministic = scenesMatch(scene, MapGenerator.generateUnchecked(authoring, tuning: tuning))

        ZStack(alignment: .bottom) {
            Canvas { context, size in
                let palette = TerrainPalette(environment: environment)
                TerrainRenderer.render(scene, into: &context, size: size, palette: palette)
            }
            .background(Color(token: DesignToken.parchment))
            .ignoresSafeArea()

            controlsToggle
        }
        .navigationTitle("Map tuning harness (KAN-19)")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showControls) {
            controlsDrawer(glyphCount: scene.glyphs.count, deterministic: deterministic)
                .presentationDetents([.height(360), .large])
                .presentationBackgroundInteraction(.enabled)
        }
    }

    // MARK: - Controls

    private var controlsToggle: some View {
        Button {
            showControls = true
        } label: {
            Label("Tuning", systemImage: "slider.horizontal.3")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Color(token: DesignToken.card), in: Capsule())
                .foregroundStyle(Color(token: DesignToken.ink))
        }
        .padding(.bottom, 24)
        .opacity(showControls ? 0 : 1)
    }

    private func controlsDrawer(glyphCount: Int, deterministic: Bool) -> some View {
        NavigationStack {
            Form {
                validationSection
                seedSection(deterministic: deterministic, glyphCount: glyphCount)
                knobsSection
            }
            .navigationTitle("Tuning")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showControls = false }
                }
            }
        }
    }

    private var validationSection: some View {
        Section("Validation") {
            if violations.isEmpty {
                Label("Passes all validators", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(Color(token: DesignToken.reward))
            } else {
                Label("\(violations.count) violation\(violations.count == 1 ? "" : "s")",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color(token: DesignToken.alert))
                ForEach(violations) { v in
                    Text(v.message)
                        .font(.footnote)
                        .foregroundStyle(Color(token: DesignToken.alert))
                }
            }
        }
    }

    private func seedSection(deterministic: Bool, glyphCount: Int) -> some View {
        Section("Seed") {
            HStack {
                TextField("Seed", text: $seedText)
                    .keyboardType(.numberPad)
                    .onSubmit(applySeedText)
                Button("Apply", action: applySeedText)
                    .buttonStyle(.bordered)
            }
            Button {
                seed = UInt64.random(in: UInt64.min...UInt64.max)
                seedText = String(seed)
            } label: {
                Label("Reroll seed", systemImage: "die.face.5")
            }
            LabeledContent("Glyphs generated", value: "\(glyphCount)")
            HStack {
                Text("Determinism")
                Spacer()
                Label(deterministic ? "stable" : "MISMATCH",
                      systemImage: deterministic ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .foregroundStyle(Color(token: deterministic ? DesignToken.reward : DesignToken.alert))
                    .labelStyle(.titleAndIcon)
            }
            .font(.footnote)
        }
    }

    private var knobsSection: some View {
        Section("Global multipliers (over authored per-region params)") {
            knob("Density", value: $densityMultiplier)
            knob("Jitter", value: $jitterMultiplier)
            knob("Feather", value: $featherMultiplier)
            Button("Reset knobs") {
                densityMultiplier = 1; jitterMultiplier = 1; featherMultiplier = 1
            }
        }
    }

    private func knob(_ label: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                Spacer()
                Text(String(format: "×%.2f", value.wrappedValue))
                    .foregroundStyle(.secondary).monospacedDigit()
            }
            Slider(value: value, in: 0...2)
        }
    }

    private func applySeedText() {
        if let parsed = UInt64(seedText.trimmingCharacters(in: .whitespaces)) {
            seed = parsed
        } else {
            seedText = String(seed) // reject bad input, restore
        }
    }

    // MARK: - Determinism comparison

    /// Two scenes match iff their glyphs (kind, base, size, snow cap) and pins are
    /// identical in order — the concrete assertion that generation is deterministic.
    private func scenesMatch(_ a: TerrainScene, _ b: TerrainScene) -> Bool {
        guard a.glyphs.count == b.glyphs.count, a.pins.count == b.pins.count else { return false }
        for (g1, g2) in zip(a.glyphs, b.glyphs) {
            if g1.kind != g2.kind || g1.base != g2.base || g1.size != g2.size || g1.snowCap != g2.snowCap {
                return false
            }
        }
        for (p1, p2) in zip(a.pins, b.pins) where p1.position != p2.position { return false }
        return true
    }
}

#Preview("Map tuning harness — light") {
    NavigationStack { MapTuningHarnessView() }
        .preferredColorScheme(.light)
}

#Preview("Map tuning harness — Deepdark") {
    NavigationStack { MapTuningHarnessView() }
        .preferredColorScheme(.dark)
}
