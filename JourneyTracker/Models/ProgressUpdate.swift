//
//  ProgressUpdate.swift
//  JourneyTracker
//
//  The single shared delta anchor. There is ONE ProgressUpdate record for the
//  whole install. It records the cumulative distanceWalkingRunning that has
//  already been applied to journeys, measured from a fixed anchorStartDate.
//
//  On each HealthKit update: query cumulative distance over
//  [anchorStartDate, now] -> newCumulative; delta = max(0, newCumulative -
//  lastProcessedDistance); add delta to every active, non-completed journey;
//  then set lastProcessedDistance = newCumulative. See ProgressUpdater.
//
//  CloudKit-compatible: inline default on every stored property, no unique
//  constraint. sourceDevice enum stored as its raw String with a default.
//

import Foundation
import SwiftData

/// Which device produced the most recently processed distance reading.
enum SourceDevice: String, Codable, CaseIterable {
    case watch
    case phone
    case unknown
}

@Model
final class ProgressUpdate {
    var id: UUID = UUID()

    /// Fixed UTC reference date the cumulative query runs from. Set once when
    /// the anchor is created; not per-journey.
    var anchorStartDate: Date = Date()

    /// Cumulative meters from `anchorStartDate` already applied to journeys.
    var lastProcessedDistance: Double = 0

    /// UTC timestamp of the last successful delta application.
    var lastUpdated: Date = Date()

    /// Best-effort attribution of the last reading.
    var sourceDevice: SourceDevice = SourceDevice.unknown

    init(
        id: UUID = UUID(),
        anchorStartDate: Date = Date(),
        lastProcessedDistance: Double = 0,
        lastUpdated: Date = Date(),
        sourceDevice: SourceDevice = .unknown
    ) {
        self.id = id
        self.anchorStartDate = anchorStartDate
        self.lastProcessedDistance = lastProcessedDistance
        self.lastUpdated = lastUpdated
        self.sourceDevice = sourceDevice
    }
}
