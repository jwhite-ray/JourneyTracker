//
//  JourneyTrackerApp.swift
//  JourneyTracker
//
//  Created by Justin Whitehead on 7/8/26.
//

import SwiftUI
import SwiftData

@main
struct JourneyTrackerApp: App {
    @State private var health = HealthKitManager.shared
    // KAN-32: the single notification authority, injected like HealthKitManager.
    @State private var notifications = NotificationManager.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(health)
                .environment(notifications)
        }
        .modelContainer(SharedModelContainer.shared)
    }
}

/// App shell. The journey list is the main screen; DebugView stays reachable as
/// a second tab so KAN-6's HealthKit/persistence proof (and Jeremiah's
/// XCUITest driver) keep working untouched.
///
/// KAN-33: owns the `DeepLinkRouter` and binds it to the TabView selection, so a
/// milestone-notification tap can bring the Journeys tab forward and push the
/// resolved journey's map (JourneyListView drives the path-based NavigationStack).
private struct RootView: View {
    @Environment(HealthKitManager.self) private var health
    @Environment(NotificationManager.self) private var notifications

    /// The single deep-link router, injected into the environment and bound to the
    /// tab selection. The notification delegate (owned by NotificationManager)
    /// drives it on a tap.
    @State private var router = DeepLinkRouter()

    var body: some View {
        TabView(selection: $router.selectedTab) {
            // The Journeys tab owns its own path-based NavigationStack (moved into
            // JourneyListView per KAN-33 Ruling 8) so a tap can push onto its path.
            JourneyListView()
                .tag(DeepLinkRouter.Tab.journeys)
                .tabItem {
                    Label("Journeys", systemImage: "map")
                }

            DebugView()
                .tag(DeepLinkRouter.Tab.debug)
                .tabItem {
                    Label("Debug", systemImage: "stethoscope")
                }
        }
        .environment(router)
        .task {
            // KAN-32: declare notification categories and read the current
            // authorization at launch — NEVER a permission prompt here (the
            // contextual request lives in the start-journey flow). registerCategories
            // is prompt-free and synchronous, so it runs before health.start()'s
            // await — a first launch suspended at the HealthKit sheet must not
            // delay category registration (Rooster, KAN-32 finding 4).
            notifications.registerCategories()

            // KAN-33 Ruling 8: assign the tap/foreground delegate at launch (beside
            // registerCategories, prompt-free) so a cold-launch tap's `didReceive`
            // is caught and routed through this router.
            notifications.assignDelegate(router: router)

            // Owns launch: seeds the store and starts HealthKit once, so the
            // journey list has data even if the user never opens the Debug tab.
            // This is app-lifecycle work, not a map-screen read.
            await health.start()

            // Prompt-free read of the system authorization state.
            await notifications.refreshAuthorizationStatus()
        }
    }
}
