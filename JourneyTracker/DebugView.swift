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
        }
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
