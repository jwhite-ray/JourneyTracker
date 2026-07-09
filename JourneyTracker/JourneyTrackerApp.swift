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
            DebugView()
                .environment(health)
        }
        .modelContainer(SharedModelContainer.shared)
    }
}
