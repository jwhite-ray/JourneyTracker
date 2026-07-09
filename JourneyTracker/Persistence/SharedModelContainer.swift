//
//  SharedModelContainer.swift
//  JourneyTracker
//
//  Builds the app's SwiftData ModelContainer against a shared App Group
//  container from day one, so a future widget / Live Activity / Watch
//  extension can read the same store without a data migration.
//
//  Placeholder App Group ID below — the real team prefix needs a developer
//  portal entry. See KAN-6 summary.
//

import Foundation
import SwiftData

enum SharedModelContainer {

    /// Placeholder App Group identifier. Must match the entitlement on BOTH
    /// the iOS and Watch targets. Replace with the provisioned group ID once
    /// it exists in the developer portal.
    static let appGroupID = "group.com.justinwhitehead.JourneyTracker.shared"

    static let schema = Schema([
        Journey.self,
        Waypoint.self,
        ProgressUpdate.self,
    ])

    static let shared: ModelContainer = {
        let configuration: ModelConfiguration

        if let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) {
            let storeURL = groupURL.appending(path: "JourneyTracker.store")
            configuration = ModelConfiguration(schema: schema, url: storeURL)
        } else {
            // App Group unavailable (e.g. entitlement not provisioned). Fall
            // back to the default store so the app still runs; the store then
            // lives in the app-private container instead of the group.
            print("[SharedModelContainer] App Group container URL unavailable — falling back to default store.")
            configuration = ModelConfiguration(schema: schema)
        }

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()
}
