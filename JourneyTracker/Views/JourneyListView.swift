//
//  JourneyListView.swift
//  JourneyTracker
//
//  The app's main screen: one Card Cream card per journey (Design System §07),
//  each showing the journey name, the shared progress bar, its distance label,
//  and a "View Map" affordance that navigates to that journey's map. Reads
//  persisted journeys via @Query — READ-ONLY, no HealthKit, no writes.
//

import SwiftUI
import SwiftData

struct JourneyListView: View {
    @Query(sort: \Journey.startDate) private var journeys: [Journey]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(journeys) { journey in
                    NavigationLink {
                        JourneyMapView(journey: journey)
                    } label: {
                        JourneyCard(journey: journey)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
        .background(Color(token: DesignToken.parchment))
        .navigationTitle("Your Journeys")
    }
}

private struct JourneyCard: View {
    let journey: Journey

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(journey.name)
                .font(.system(size: 18, weight: .bold, design: .serif))
                .foregroundStyle(Color(token: DesignToken.ink))
                .accessibilityIdentifier("list.journeyName.\(journey.name)")

            JourneyProgressBar(
                progress: journey.progress,
                accentColorToken: journey.theme.accentColorToken,
                label: DistanceFormatter.progressLabel(
                    accumulated: journey.distanceAccumulated,
                    total: journey.totalDistance
                ),
                barIdentifier: "list.progressBar.\(journey.name)",
                labelIdentifier: "list.distanceLabel.\(journey.name)"
            )

            Text("View Map")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Color(token: DesignToken.card))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background {
                    // Shadow lives on the background shape only, so the §08 hard
                    // drop shadow never ghosts the label text.
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(token: journey.theme.accentColorToken))
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(token: DesignToken.ink), lineWidth: 3))
                        .shadow(color: Color(token: DesignToken.ink), radius: 0, x: 0, y: 4)
                }
                .accessibilityIdentifier("list.viewMapButton.\(journey.name)")
        }
        .padding(16)
        .background(Color(token: DesignToken.card), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(Color(token: DesignToken.ink), lineWidth: 2))
    }
}
