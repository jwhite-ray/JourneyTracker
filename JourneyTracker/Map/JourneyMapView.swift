//
//  JourneyMapView.swift
//  JourneyTracker
//
//  The "Ink Trail" journey map (KAN-7, Variant A). STRICTLY READ-ONLY over the
//  persisted `Journey` it is opened with — it takes that exact journey and
//  never re-derives "the current journey", makes no HealthKit calls, and never
//  writes Journey or ProgressUpdate. A fresh install or denied permission
//  simply renders the stored 0% state.
//
//  Parchment field, a dot-dash ink trail route in `theme.pathColorToken`,
//  teardrop pins in `theme.accentColorToken`, and Wren positioned by
//  MarkerPositionCalculator (distance-weighted, never snapped). Zero-or-one
//  waypoint journeys degrade gracefully: no route, no marker, no crash.
//
//  Art is procedural today; when real art ships it swaps in via the journey's
//  `theme.backgroundImageName` / `theme.markerImageName` with no model change.
//

import SwiftUI

struct JourneyMapView: View {
    /// The exact persisted journey this screen was opened from — never
    /// re-derived from "the current journey".
    let journey: Journey

    /// Waypoints sorted by order, resolved once.
    private var waypoints: [Waypoint] {
        (journey.waypoints ?? []).sorted { $0.order < $1.order }
    }

    private var states: [(waypoint: Waypoint, state: WaypointState)] {
        MarkerPositionCalculator.waypointStates(
            distanceAccumulated: journey.distanceAccumulated,
            isCompleted: journey.isCompleted,
            waypoints: waypoints
        )
    }

    /// Normalized marker position, or nil when there are < 2 waypoints.
    private var markerPositionNormalized: CGPoint? {
        MarkerPositionCalculator.markerPosition(
            distanceAccumulated: journey.distanceAccumulated,
            isCompleted: journey.isCompleted,
            waypoints: waypoints
        )
    }

    private var finalWaypointName: String? {
        waypoints.last?.name
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(journey.name)
                    .font(.system(size: 24, weight: .bold, design: .serif))
                    .foregroundStyle(Color(token: DesignToken.ink))
                    .accessibilityIdentifier("map.journeyTitle")

                mapField
                    .frame(height: 420)
                    .padding(.horizontal, 4)

                JourneyProgressBar(
                    progress: journey.progress,
                    accentColorToken: journey.theme.accentColorToken,
                    label: DistanceFormatter.progressLabel(
                        accumulated: journey.distanceAccumulated,
                        total: journey.totalDistance
                    ),
                    barIdentifier: "map.progressBar",
                    labelIdentifier: "map.distanceLabel"
                )

                if journey.isCompleted {
                    Text(completedCopy)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(token: DesignToken.ink).opacity(0.75))
                        .accessibilityIdentifier("map.completedBanner")
                } else if waypoints.count < 2 {
                    // Zero-or-one waypoint journeys (e.g. "Around the World"):
                    // no route, no marker — say so instead of showing an empty map.
                    Text("This journey doesn't have a mapped route yet.")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(token: DesignToken.ink).opacity(0.75))
                        .accessibilityIdentifier("map.noRouteNotice")
                }
            }
            .padding(20)
        }
        .background(Color(token: DesignToken.parchment))
    }

    private var completedCopy: String {
        if let name = finalWaypointName {
            return "Journey complete — Wren is resting at \(name)."
        }
        return "Journey complete."
    }

    // MARK: - Map field

    private var mapField: some View {
        GeometryReader { geo in
            ZStack {
                // Background: real art swaps in here automatically once an asset
                // named `theme.backgroundImageName` is bundled; procedural
                // parchment until then.
                mapBackground

                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color(token: DesignToken.ink), lineWidth: 3)

                if waypoints.count >= 2 {
                    routePath(size: geo.size)
                        .stroke(Color(token: journey.theme.pathColorToken),
                                style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [8, 6]))

                    ForEach(states, id: \.waypoint.id) { entry in
                        WaypointPin(state: entry.state,
                                    accentColorToken: journey.theme.accentColorToken)
                            .position(x: entry.waypoint.positionX * geo.size.width,
                                      y: entry.waypoint.positionY * geo.size.height)
                            .accessibilityIdentifier("map.waypoint.\(entry.waypoint.name)")
                    }

                    // The single .next waypoint's name callout, drawn separately
                    // so its own `.fixedSize()` layout — not the pin's fixed
                    // frame — governs its width. Nudged above the pin.
                    if let next = states.first(where: { $0.state == .next }) {
                        WaypointCallout(name: next.waypoint.name)
                            .position(x: next.waypoint.positionX * geo.size.width,
                                      y: next.waypoint.positionY * geo.size.height)
                            .offset(y: -30)
                    }

                    if let normalized = markerPositionNormalized {
                        markerImage
                            .position(x: normalized.x * geo.size.width,
                                      y: normalized.y * geo.size.height)
                            .accessibilityIdentifier("map.marker")
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }

    @ViewBuilder
    private var mapBackground: some View {
        if !journey.theme.backgroundImageName.isEmpty,
           UIImage(named: journey.theme.backgroundImageName) != nil {
            Image(journey.theme.backgroundImageName)
                .resizable()
                .scaledToFill()
        } else {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(token: DesignToken.parchment))
        }
    }

    @ViewBuilder
    private var markerImage: some View {
        if !journey.theme.markerImageName.isEmpty,
           UIImage(named: journey.theme.markerImageName) != nil {
            Image(journey.theme.markerImageName)
                .resizable()
                .frame(width: 32, height: 40)
        } else {
            WrenMarker(resting: journey.isCompleted)
        }
    }

    private func routePath(size: CGSize) -> Path {
        var path = Path()
        guard let first = waypoints.first else { return path }
        path.move(to: CGPoint(x: first.positionX * size.width, y: first.positionY * size.height))
        for wp in waypoints.dropFirst() {
            path.addLine(to: CGPoint(x: wp.positionX * size.width, y: wp.positionY * size.height))
        }
        return path
    }
}
