//
//  JourneyMapView.swift
//  JourneyTracker
//
//  The journey view (KAN-7, renamed per Justin's 2026-07-12 two-surface ruling).
//  STRICTLY READ-ONLY over the persisted `UserJourney` it is opened with — it takes
//  that exact instance and never re-derives "the current journey", makes no
//  HealthKit calls, and never writes any model. Content (name, waypoints, theme,
//  total) is read through the instance's `template`. A fresh install or denied
//  permission simply renders the stored 0% state.
//
//  TWO map surfaces, chosen by whether the journey has authored faceted content
//  (KAN-21):
//   • WITH authoring (Road to The Windrise Peaks) — the map card renders the calm,
//     static `StaticJourneyMapView` at chapter framing over the faceted terrain,
//     with an expand button to the gesture-driven `FullScreenMapView`. The marker
//     mileage and the waypoint pin states are derived from REAL progress each
//     render; the heavy scene + geometry cache is built ONCE per appearance.
//   • WITHOUT authoring (Ember Spire / First Journey / Lantern Road / Around the
//     World) — the KAN-7 pin-and-route fallback: parchment field, dot-dash ink
//     route, Wren interpolated by real distance. Its waypoint pins now render the
//     SAME §07 teardrop/chip anatomy the faceted Canvas uses (KAN-21 mid-flight),
//     via the shared `TerrainRenderer.drawPins`, so both surfaces read as one
//     design language. Zero-or-one waypoint journeys degrade gracefully.
//
//  Both surfaces only READ progress — the marker interpolates by real distance and
//  the map never owns or writes it.
//

import Combine
import SwiftUI

struct JourneyMapView: View {
    /// The exact persisted instance this screen was opened from — never
    /// re-derived from "the current journey".
    let journey: UserJourney

    /// For the terrain `TerrainPalette` (Deepdark resolves through tokens).
    @Environment(\.self) private var environment

    /// Builds the faceted presentation once per appearance (nil for a journey with
    /// no authoring). @StateObject so the ~6 ms release / ~0.9 s debug scene +
    /// geometry build runs a SINGLE time, never on a progress-driven re-render.
    @StateObject private var mapModel: JourneyMapModel

    init(journey: UserJourney) {
        self.journey = journey
        _mapModel = StateObject(wrappedValue:
            JourneyMapModel(authoring: MapAuthoringCatalog.authoring(for: journey.template)))
    }

    /// Waypoints (content) sorted by order, read through the template.
    private var waypoints: [Waypoint] {
        (journey.template?.waypoints ?? []).sorted { $0.order < $1.order }
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

    /// True when this journey renders the faceted surface (has authored content).
    private var hasFacetedMap: Bool { mapModel.base != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(journey.name)
                    .font(.system(size: 24, weight: .bold, design: .serif))
                    .foregroundStyle(Color(token: DesignToken.ink))
                    .accessibilityIdentifier("map.journeyTitle")

                mapArea
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
                    // The KAN-7 completed banner is UNCHANGED and coexists with
                    // the KAN-14 finish-date stat below (Ruling 5).
                    Text(completedCopy)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(token: DesignToken.ink).opacity(0.75))
                        .accessibilityIdentifier("map.completedBanner")
                } else if !hasFacetedMap && waypoints.count < 2 {
                    // Zero-or-one waypoint journeys with no faceted map (e.g. "Around
                    // the World"): no route, no marker — say so instead of showing an
                    // empty map. An authored journey always has a route, so it never
                    // shows this notice regardless of its stored waypoint count.
                    Text("This journey doesn't have a mapped route yet.")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(token: DesignToken.ink).opacity(0.75))
                        .accessibilityIdentifier("map.noRouteNotice")
                }

                // KAN-14 journey stats — below the progress bar, scrolling with
                // the screen. The map frame above keeps its shipped size.
                JourneyStatsSection(
                    stats: JourneyStatsCalculator.stats(for: journey),
                    accentColorToken: journey.theme.accentColorToken
                )
            }
            .padding(20)
        }
        .background(Color(token: DesignToken.parchment))
    }

    private var completedCopy: String {
        if let name = finalWaypointName {
            // KAN-33 Ruling 5 & 10: the character name reads from the ONE seam so
            // the banner and the journey_complete notification never diverge and
            // both swap in one place when character selection ships.
            return "Journey complete — \(JourneyCharacter.currentName) is resting at \(name)."
        }
        return "Journey complete."
    }

    // MARK: - Map area (faceted vs. fallback)

    @ViewBuilder
    private var mapArea: some View {
        if let presentation = mapModel.presentation(distanceAccumulated: journey.distanceAccumulated) {
            // Faceted surface. The card border/clip matches the fallback so both
            // read as the same map card; the terrain's own world-edge line sits
            // inside it.
            StaticJourneyMapView(presentation: presentation,
                                 markerResting: journey.isCompleted)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18)
                    .stroke(Color(token: DesignToken.ink), lineWidth: 3))
                .accessibilityIdentifier("map.faceted")
        } else {
            mapField
        }
    }

    // MARK: - Fallback map field (pin-and-route)

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

                    // §07 terrain pin anatomy on the fallback too (KAN-21 mid-flight
                    // ruling): the SAME teardrop / hard-offset shadow / next-ring /
                    // Cinzel chip recipe the faceted Canvas draws, built here as
                    // screen-space `TerrainPin`s from the live waypoint states and
                    // rendered via the shared `TerrainRenderer.drawPins` — no
                    // reimplementation. Destination-always-labeled now applies here.
                    Canvas { ctx, sz in
                        var pinScene = TerrainScene()
                        pinScene.pins = fallbackPins(size: sz)
                        TerrainRenderer.drawPins(pinScene, into: &ctx,
                                                 palette: TerrainPalette(environment: environment))
                    }
                    .allowsHitTesting(false)

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

    /// The fallback's waypoint pins as screen-space `TerrainPin`s (KAN-21). The
    /// teardrop tip anchors to the waypoint's position on the route; state maps
    /// from the live `WaypointState`, and the final waypoint carries the
    /// always-labeled destination flag. All pins use the journey's accent token.
    private func fallbackPins(size: CGSize) -> [TerrainPin] {
        let entries = states
        let lastIndex = entries.count - 1
        return entries.enumerated().map { index, entry in
            let pinState: TerrainPin.State
            // §08 completed-final row: the finished destination fills reward gold,
            // NOT the journey's theme accent (the faceted path gets this from its
            // authored `reward` token). Every other pin uses the theme accent.
            var accentToken = journey.theme.accentColorToken
            switch entry.state {
            case .reached: pinState = .reached
            case .completedFinal:
                pinState = .reached
                accentToken = DesignToken.reward
            case .next: pinState = .next
            case .upcoming: pinState = .upcoming
            }
            return TerrainPin(
                position: CGPoint(x: entry.waypoint.positionX * size.width,
                                  y: entry.waypoint.positionY * size.height),
                name: entry.waypoint.name,
                accentToken: accentToken,
                state: pinState,
                isDestination: index == lastIndex)
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

/// Builds and holds the faceted `JourneyMapPresentation` for a journey view. The
/// heavy generator + `MapSceneGeometry` cache build happens ONCE, in `init` (run a
/// single time via the view's @StateObject), so the per-render `presentation(_:)`
/// only restyles the marker + pins from live progress — never a scene rebuild.
@MainActor
final class JourneyMapModel: ObservableObject {
    /// The presentation built from authored content, or nil when the journey has
    /// no faceted map (→ the pin-and-route fallback).
    let base: JourneyMapPresentation?

    init(authoring: MapAuthoring?) {
        if let authoring, authoring.waypoints.count >= 2 {
            base = JourneyMapPresentation(
                authoring: authoring,
                scene: MapGenerator.generateUnchecked(authoring),
                markerMiles: 0)
        } else {
            base = nil
        }
    }

    /// The presentation reflecting current progress, or nil when there's no faceted
    /// map. Cheap — reuses the cached scene/geometry, restyling only marker + pins.
    func presentation(distanceAccumulated meters: Double) -> JourneyMapPresentation? {
        base?.applyingProgress(markerMiles: DistanceFormatter.miles(meters))
    }
}

// MARK: - Previews

/// A standalone (uninserted) Windrise instance for previewing the faceted journey
/// view without a live store. The catalog keys on the template NAME, so this is all
/// the faceted surface needs.
private func previewWindriseJourney(miles: Double) -> UserJourney {
    let template = JourneyTemplate(
        name: "Road to The Windrise Peaks",
        type: .fantasy,
        totalDistance: 302.4 * DistanceFormatter.metersPerMile,
        backgroundImageName: "windrise_peaks_bg",
        markerImageName: "marker_wren",
        accentColorToken: "accent/primary",
        pathColorToken: "ink")
    return UserJourney(
        startDate: Date(timeIntervalSince1970: 1_720_000_000),
        distanceAccumulated: miles * DistanceFormatter.metersPerMile,
        status: .active,
        template: template)
}

#Preview("Journey view — faceted (light)") {
    NavigationStack {
        JourneyMapView(journey: previewWindriseJourney(miles: 60))
    }
}

#Preview("Journey view — faceted (Deepdark)") {
    NavigationStack {
        JourneyMapView(journey: previewWindriseJourney(miles: 60))
    }
    .preferredColorScheme(.dark)
}
