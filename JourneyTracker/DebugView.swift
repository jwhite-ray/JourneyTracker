//
//  DebugView.swift
//  JourneyTracker
//
//  Developer-only debug display for KAN-6. No journey UI, no themed art — this
//  screen exists to prove HealthKit authorization, the delta anchor, and
//  SwiftData persistence work honestly. Raw numbers are intentional here.
//

import SwiftUI
import SwiftData

struct DebugView: View {
    @Environment(HealthKitManager.self) private var health
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \UserJourney.startDate) private var journeys: [UserJourney]
    @Query private var anchors: [ProgressUpdate]

    var body: some View {
        NavigationStack {
            List {
                authorizationSection
                advisorySection
                journeysSection
                anchorSection
                mapFixtureValidationSection
                actionsSection
            }
            .navigationTitle("HealthKit Debug")
        }
        // The app shell (RootView) owns the single `health.start()` at launch —
        // seeding, authorization, and the observer install happen once there, so
        // this screen no longer kicks off its own duplicate start.
    }

    // MARK: Authorization lifecycle

    private var authorizationSection: some View {
        Section("Authorization") {
            labeledRow("Request phase", health.authorizationPhase.rawValue, identifier: "debug.requestPhase")
            labeledRow("getRequestStatusForAuthorization", health.requestStatusDescription, identifier: "debug.requestStatus")
            labeledRow("Last query", health.lastQueryOutcome, identifier: "debug.lastQuery")
            if health.healthDataUnavailable {
                Text("HealthKit is unavailable on this device.")
                    .foregroundStyle(.secondary)
            }
            Text("Read grants for these types are never exposed by HealthKit, so no Authorized/Denied label is shown.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var advisorySection: some View {
        if health.showNoDataAdvisory {
            Section {
                Text("No data received — Health access may be off. Check Settings > Privacy & Security > Health.")
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("debug.advisory")
            }
        }
    }

    // MARK: Journeys

    @ViewBuilder
    private var journeysSection: some View {
        if journeys.isEmpty {
            Section("Journeys (all instances)") {
                Text("No journey instances. A fresh install has a seeded catalog but no runs yet.")
                    .foregroundStyle(.secondary)
            }
        } else {
            Section("Journeys (all instances)") {
                ForEach(journeys) { journey in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(journey.name)
                            .font(.headline)
                            .accessibilityIdentifier("debug.journey.name.\(journey.name)")
                        // Per-instance lifecycle status string (replaces the old
                        // Active/Completed booleans).
                        labeledRow("Status", journey.status.rawValue,
                                   identifier: "debug.journey.status.\(journey.name)")
                        labeledRow("Accumulated (m)", "\(journey.distanceAccumulated)",
                                   identifier: "debug.journey.accumulated.\(journey.name)")
                        labeledRow("Total (m)", "\(journey.totalDistance)",
                                   identifier: "debug.journey.total.\(journey.name)")
                        labeledRow("Progress", String(format: "%.4f", journey.progress),
                                   identifier: "debug.journey.progress.\(journey.name)")
                        Text("Since \(journey.startDate.formatted())")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: Secondary step stat + anchor

    private var anchorSection: some View {
        Section("Health readings (shared anchor)") {
            labeledRow("Cumulative distance (m)", "\(health.latestCumulativeDistance)",
                       identifier: "debug.cumulativeDistance")
            // AC4: steps are a clearly separate secondary stat, never merged
            // into or driving the distance number.
            labeledRow("Steps (display only)", "\(Int(health.latestStepCount))",
                       identifier: "debug.steps")
            if let anchor = anchors.first {
                labeledRow("Anchor start", anchor.anchorStartDate.formatted())
                labeledRow("Last processed (m)", "\(anchor.lastProcessedDistance)")
                labeledRow("Last updated", anchor.lastUpdated.formatted())
                labeledRow("Source device", anchor.sourceDevice.rawValue)
            } else {
                Text("No anchor yet.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actionsSection: some View {
        Section {
            Button("Re-run query now") {
                Task { await health.refresh() }
            }
            .accessibilityIdentifier("debug.rerunButton")

            // KAN-18 (P1) faceted-terrain look-proof. Dev-only entry — the real
            // terrain lands under KAN-7's map at P4, not here.
            NavigationLink("Terrain specimen (KAN-18)") {
                TerrainSpecimenView()
            }
            .accessibilityIdentifier("debug.terrainSpecimen")

            // KAN-19 (P2) seeded map generator + persistent tuning harness. This
            // is the map-authoring surface, not a throwaway dev screen.
            NavigationLink("Map tuning harness (KAN-19)") {
                MapTuningHarnessView()
            }
            .accessibilityIdentifier("debug.mapTuningHarness")

            // KAN-20 (P3) camera / LOD / culling. The calm static "journey view"
            // at chapter framing, with an expand button to the gesture surface.
            NavigationLink("Journey view (static, KAN-20)") {
                StaticJourneyMapView(presentation: Self.samplePresentation,
                                     fullScreenPerfOverlay: true)
                    .navigationTitle("Journey view")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .accessibilityIdentifier("debug.journeyViewStatic")

            // KAN-20 (P3) Ember Spire-scale (1,800 mi) stress fixture, opened
            // straight into the full-screen gesture surface with the perf overlay.
            NavigationLink("Ember Spire scale test (KAN-20)") {
                FullScreenMapView(presentation: Self.stressPresentation,
                                  initialFraming: .overview,
                                  showsPerfOverlay: true)
                    .toolbar(.hidden, for: .navigationBar)
            }
            .accessibilityIdentifier("debug.emberSpireScale")
        }
    }

    // MARK: KAN-20 debug map presentations (generated + VALIDATED once)

    /// The ~30-mile P2 sample map, marker part-way along the first leg.
    private static let sampleAuthoring = SampleJourneyMap.make()
    private static let sampleViolations = MapValidator.validate(sampleAuthoring)
    private static let samplePresentation = JourneyMapPresentation(
        authoring: sampleAuthoring,
        scene: MapGenerator.generateUnchecked(sampleAuthoring),
        markerMiles: 5.0)

    /// The 1,800-mile debug stress fixture (not shipping content).
    private static let stressAuthoring = EmberSpireScaleFixture.make()
    private static let stressViolations = MapValidator.validate(stressAuthoring)
    private static let stressPresentation = JourneyMapPresentation(
        authoring: stressAuthoring,
        scene: MapGenerator.generateUnchecked(stressAuthoring),
        markerMiles: EmberSpireScaleFixture.defaultMarkerMiles)

    /// The KAN-20 fixtures build via `generateUnchecked`, so this section makes the
    /// "passes validators" claim REAL: a red row (and a debug assertion) surfaces
    /// any regression instead of silently shipping a broken map.
    @ViewBuilder
    private var mapFixtureValidationSection: some View {
        Section("Map fixtures (KAN-20)") {
            fixtureValidationRow("Sample leg (~30 mi)", Self.sampleViolations,
                                 identifier: "debug.mapFixture.sample")
            fixtureValidationRow("Ember Spire scale (1,800 mi)", Self.stressViolations,
                                 identifier: "debug.mapFixture.stress")
        }
    }

    @ViewBuilder
    private func fixtureValidationRow(_ name: String, _ violations: [MapViolation],
                                      identifier: String) -> some View {
        let ok = violations.isEmpty
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(name)
                Spacer()
                Label(ok ? "PASS" : "\(violations.count) FAIL",
                      systemImage: ok ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(Color(token: ok ? DesignToken.reward : DesignToken.alert))
                    .accessibilityIdentifier(identifier)
            }
            .font(.subheadline)
            ForEach(violations) { v in
                Text(v.message)
                    .font(.footnote)
                    .foregroundStyle(Color(token: DesignToken.alert))
            }
        }
        .onAppear { assert(ok, "\(name) failed map validators: \(violations.map(\.message))") }
    }

    // MARK: Helpers

    private func labeledRow(_ label: String, _ value: String, identifier: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .accessibilityIdentifier(identifier ?? "")
        }
        .font(.subheadline)
    }
}

#Preview {
    DebugView()
        .environment(HealthKitManager.shared)
        .modelContainer(SharedModelContainer.shared)
}
