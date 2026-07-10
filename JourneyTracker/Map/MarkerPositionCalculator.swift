//
//  MarkerPositionCalculator.swift
//  JourneyTracker
//
//  Pure functions that turn a journey's cumulative distance (METERS) into a
//  marker position and per-waypoint states along the waypoint polyline.
//
//  Intentionally free of SwiftUI, SwiftData writes, and HealthKit so it can be
//  unit-tested in isolation. It only READS progress — it never owns or mutates
//  it (see App Concept, "Fantasy map + marker").
//
//  CRITICAL: interpolation is weighted by REAL distanceFromStart in meters, not
//  by an even split across waypoint indices. An even split was the retired
//  prototype's bug.
//

import CoreGraphics

/// The progress state of a single waypoint relative to current distance.
enum WaypointState {
    /// Distance has reached or passed this waypoint.
    case reached
    /// The first not-yet-reached waypoint (at most one per journey).
    case next
    /// A further, not-yet-reached waypoint.
    case upcoming
    /// The final waypoint when the journey is completed.
    case completedFinal
}

enum MarkerPositionCalculator {

    /// Normalized (0...1) marker position for the given cumulative distance.
    ///
    /// - Parameters:
    ///   - distanceAccumulated: cumulative distance since journey start, METERS.
    ///   - isCompleted: whether the journey is completed.
    ///   - waypoints: the journey's waypoints (any order; sorted internally).
    /// - Returns: a normalized CGPoint (x, y in 0...1), or nil when there are
    ///   fewer than two waypoints (e.g. "Around the World"). The view degrades
    ///   gracefully: no marker, no route, no crash.
    static func markerPosition(
        distanceAccumulated: Double,
        isCompleted: Bool,
        waypoints: [Waypoint]
    ) -> CGPoint? {
        let sorted = waypoints.sorted { $0.order < $1.order }
        guard sorted.count >= 2 else { return nil }

        let d = distanceAccumulated
        let first = sorted[0]
        let last = sorted[sorted.count - 1]

        // At or before the start.
        if d <= first.distanceFromStart {
            return point(for: first)
        }

        // Completed, or at/past the final waypoint.
        if isCompleted || d >= last.distanceFromStart {
            return point(for: last)
        }

        // Find the bracketing segment [i, i+1] where d[i] <= d < d[i+1].
        for i in 0..<(sorted.count - 1) {
            let a = sorted[i]
            let b = sorted[i + 1]
            if d >= a.distanceFromStart && d < b.distanceFromStart {
                let span = b.distanceFromStart - a.distanceFromStart
                // Guard divide-by-zero when two waypoints share a distance.
                let t = span > 0 ? (d - a.distanceFromStart) / span : 0
                let x = a.positionX + (b.positionX - a.positionX) * t
                let y = a.positionY + (b.positionY - a.positionY) * t
                return CGPoint(x: x, y: y)
            }
        }

        // Unreachable given the guards above, but fail safe to the last point.
        return point(for: last)
    }

    /// Classifies every waypoint's state for the given cumulative distance.
    ///
    /// - Returns: states aligned to the waypoints sorted by `order`.
    static func waypointStates(
        distanceAccumulated: Double,
        isCompleted: Bool,
        waypoints: [Waypoint]
    ) -> [(waypoint: Waypoint, state: WaypointState)] {
        let sorted = waypoints.sorted { $0.order < $1.order }
        var assignedNext = false

        return sorted.enumerated().map { index, waypoint in
            let isFinal = index == sorted.count - 1
            if isCompleted && isFinal {
                return (waypoint, .completedFinal)
            }
            if distanceAccumulated >= waypoint.distanceFromStart {
                return (waypoint, .reached)
            }
            // First not-reached waypoint is `.next`; the rest are `.upcoming`.
            if !assignedNext {
                assignedNext = true
                return (waypoint, .next)
            }
            return (waypoint, .upcoming)
        }
    }

    private static func point(for waypoint: Waypoint) -> CGPoint {
        CGPoint(x: waypoint.positionX, y: waypoint.positionY)
    }
}
