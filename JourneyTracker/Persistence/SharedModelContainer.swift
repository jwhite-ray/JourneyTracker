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

    /// The live (V3) schema — KAN-14 adds `WaypointCrossing` and the additive
    /// `UserJourney` fields on top of KAN-10's catalog/instance split. The V1/V2
    /// shapes and the migration stages (custom V1→V2, lightweight V2→V3) live in
    /// JourneyMigration.swift.
    static let schema = Schema(JourneySchemaV3.models)

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
            // The migration plan carries an existing V1 store (the shipped
            // combined-Journey shape) forward through the KAN-10 split (V2) and
            // the KAN-14 additive stage (V3); a fresh install simply creates V3
            // directly.
            return try ModelContainer(
                for: schema,
                migrationPlan: JourneyMigrationPlan.self,
                configurations: [configuration]
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()
}
