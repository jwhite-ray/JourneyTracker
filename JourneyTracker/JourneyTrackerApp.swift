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

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(health)
        }
        .modelContainer(SharedModelContainer.shared)
    }
}

/// App shell. The journey list is the main screen; DebugView stays reachable as
/// a second tab so KAN-6's HealthKit/persistence proof (and Jeremiah's
/// XCUITest driver) keep working untouched.
private struct RootView: View {
    @Environment(HealthKitManager.self) private var health

    var body: some View {
        TabView {
            NavigationStack {
                JourneyListView()
            }
            .tabItem {
                Label("Journeys", systemImage: "map")
            }

            DebugView()
                .tabItem {
                    Label("Debug", systemImage: "stethoscope")
                }
        }
        .task {
            // Owns launch: seeds the store and starts HealthKit once, so the
            // journey list has data even if the user never opens the Debug tab.
            // This is app-lifecycle work, not a map-screen read.
            await health.start()
        }
    }
}
