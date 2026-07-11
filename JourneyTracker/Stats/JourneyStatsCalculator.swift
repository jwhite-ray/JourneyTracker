//
//  JourneyStatsCalculator.swift
//  JourneyTracker
//
//  Pure derivation of a run's journey stats (KAN-14) — sibling to
//  MarkerPositionCalculator. Turns a UserJourney's raw fields + its template's
//  waypoints + its crossings into: days-on-journey, pace (meters/day),
//  projected finish, next-waypoint + distance-to-next, and the reached-waypoint
//  log rows. It owns NONE of the state and imports no SwiftUI / no SwiftData
//  machinery beyond the model types it reads — so it is unit-testable in
//  isolation. Both screens and the formatters render its output; it never
//  formats (StatFormatter / DistanceFormatter do) and never divides meters→miles.
//
//  Truthfulness rules it encodes (App Concept doc, KAN-14):
//   • Ruling 4 — 0-mile origin waypoints are never crossings; the log skips them,
//     and the first reached row's interval starts from the journey `startDate`.
//   • Ruling 5 — a reached waypoint with no crossing row has crossedAt == nil
//     ("date not recorded"); never fabricated.
//   • Ruling 6 — active-elapsed excludes paused time; a legacy instance whose
//     timing anchor is missing (paused with pausedAt == nil, or completed with
//     completedAt == nil — both pre-KAN-14 migrations) can't be computed
//     honestly, so its time-derived stats degrade to "not enough data yet".
//   • Ruling 7 — pace/projection need distance > 0 AND active-elapsed ≥ 1 hour;
//     below that they are nil ("not enough data yet"). Days-on-journey and start
//     date otherwise always show.
//

import Foundation

/// The next not-yet-reached waypoint and the remaining distance to it (METERS).
struct NextWaypointInfo: Equatable {
    let name: String
    let metersUntil: Double
}

/// One reached-waypoint log row. `crossedAt == nil` → "date not recorded".
/// `timeTakenSeconds == nil` → the interval's start or end instant is unknown
/// (cascades honestly; never fabricated).
struct ReachedWaypointRow: Identifiable, Equatable {
    let id: UUID
    let name: String
    let crossedAt: Date?
    let timeTakenSeconds: Double?
}

/// The fully-derived stats for one run. Raw values only — views format.
struct JourneyStats: Equatable {
    let startDate: Date
    let hasWaypoints: Bool
    let isCompleted: Bool
    /// Canonical finish date; `nil` on a migrated completion → "date not recorded".
    let completedAt: Date?

    /// Active-elapsed seconds → the days-on-journey stat (via StatFormatter).
    /// `nil` in either legacy edge (paused or completed with a missing timing
    /// anchor, Ruling 6) → "not enough data yet".
    let daysOnJourneySeconds: Double?

    /// Meters walked per active day. `nil` below the Ruling 7 floor or in
    /// either legacy edge → "not enough data yet". Views render via
    /// DistanceFormatter.milesPerDay.
    let paceMetersPerDay: Double?

    /// Projected finish date. `nil` below the floor / legacy edge, and unused for
    /// a completed run (which shows `completedAt` instead).
    let projectedFinish: Date?

    /// Next waypoint + distance-to-next. `nil` when completed, when there are no
    /// waypoints, or when every waypoint is reached.
    let nextWaypoint: NextWaypointInfo?

    /// Reached waypoints (distanceFromStart > 0), in order. Empty when none.
    let reachedLog: [ReachedWaypointRow]
}

enum JourneyStatsCalculator {

    /// Below this active-elapsed floor, pace/projection are withheld (Ruling 7).
    static let dataFloorSeconds: Double = 3_600 // 1 hour

    static func stats(
        distanceAccumulated: Double,
        totalDistance: Double,
        startDate: Date,
        status: JourneyStatus,
        completedAt: Date?,
        pausedAt: Date?,
        accumulatedPausedSeconds: Double,
        waypoints: [Waypoint],
        crossings: [WaypointCrossing],
        now: Date = Date()
    ) -> JourneyStats {
        let sorted = waypoints.sorted { $0.order < $1.order }
        let isCompleted = status == .completed

        // MARK: - The reference instant & active elapsed (Ruling 6)
        //
        // `reference` is the instant time STOPS advancing for this run — the one
        // shared anchor for days-on-journey AND projected finish, so a paused
        // run's projection can't slide forward one day per day of pause (a frozen
        // pace beside a drifting date):
        //   • completed → completedAt (the canonical finish)
        //   • paused    → pausedAt  (freezes days/pace/projection at the pause
        //                 moment; composes with the frozen elapsed)
        //   • active    → now
        // active-elapsed = reference − startDate − accumulatedPausedSeconds (the
        // sum of COMPLETED pause windows; the open window is already handled by
        // pinning `reference` to pausedAt while paused).
        //
        // Two states can't be computed honestly and degrade ALL time-derived
        // stats (days / pace / projection) to "not enough data yet":
        //   • a legacy PAUSED instance (paused before KAN-14) — pausedAt == nil,
        //   • a legacy COMPLETED instance (completed before KAN-14) — completedAt
        //     == nil; otherwise days would grow and pace decay forever on an
        //     already-finished run. Its finish tile still reads "date not
        //     recorded" (never fabricated). Distance stats are unaffected.
        let legacyPausedEdge = (status == .paused && pausedAt == nil)
        let legacyCompletedEdge = (isCompleted && completedAt == nil)
        let timeStatsUnavailable = legacyPausedEdge || legacyCompletedEdge

        let reference: Date
        if isCompleted {
            reference = completedAt ?? now // non-nil unless degraded below
        } else if let pausedAt {
            reference = pausedAt
        } else {
            reference = now
        }

        let daysOnJourneySeconds: Double?
        if timeStatsUnavailable {
            daysOnJourneySeconds = nil
        } else {
            let elapsed = reference.timeIntervalSince(startDate) - accumulatedPausedSeconds
            daysOnJourneySeconds = max(0, elapsed)
        }

        // MARK: - Pace & projection (Ruling 7)
        var paceMetersPerDay: Double? = nil
        var projectedFinish: Date? = nil
        if let elapsed = daysOnJourneySeconds,
           distanceAccumulated > 0,
           elapsed >= dataFloorSeconds {
            let elapsedDays = elapsed / 86_400
            let pace = distanceAccumulated / elapsedDays // meters/day
            paceMetersPerDay = pace
            let remaining = max(0, totalDistance - distanceAccumulated)
            if pace > 0 {
                // Same `reference` as elapsed — frozen while paused/completed.
                let daysToFinish = remaining / pace
                projectedFinish = reference.addingTimeInterval(daysToFinish * 86_400)
            }
        }

        // MARK: - Next waypoint (card "X mi until [next]") — first waypoint
        // strictly beyond current distance; none when completed / all reached.
        var nextWaypoint: NextWaypointInfo? = nil
        if !isCompleted,
           let next = sorted.first(where: { $0.distanceFromStart > distanceAccumulated }) {
            nextWaypoint = NextWaypointInfo(
                name: next.name,
                metersUntil: max(0, next.distanceFromStart - distanceAccumulated)
            )
        }

        // MARK: - Reached log (Ruling 4 & 5) — skip 0-mile origin waypoints.
        let crossedAtByWaypoint: [UUID: Date] = Dictionary(
            crossings.map { ($0.waypointID, $0.crossedAt) },
            uniquingKeysWith: { first, _ in first }
        )
        let reachedWaypoints = sorted.filter {
            $0.distanceFromStart > 0 && $0.distanceFromStart <= distanceAccumulated
        }
        var reachedLog: [ReachedWaypointRow] = []
        // The first reached row's interval starts from the journey start (there
        // is no origin crossing). Thereafter it starts from the PREVIOUS reached
        // waypoint's crossedAt — unknown if that was never recorded, cascading.
        var intervalStart: Date? = startDate
        for waypoint in reachedWaypoints {
            let crossedAt = crossedAtByWaypoint[waypoint.id]
            let timeTaken: Double?
            if let start = intervalStart, let crossed = crossedAt {
                timeTaken = max(0, crossed.timeIntervalSince(start))
            } else {
                timeTaken = nil
            }
            reachedLog.append(ReachedWaypointRow(
                id: waypoint.id,
                name: waypoint.name,
                crossedAt: crossedAt,
                timeTakenSeconds: timeTaken
            ))
            intervalStart = crossedAt // cascades to nil if unrecorded
        }

        return JourneyStats(
            startDate: startDate,
            hasWaypoints: !sorted.isEmpty,
            isCompleted: isCompleted,
            completedAt: completedAt,
            daysOnJourneySeconds: daysOnJourneySeconds,
            paceMetersPerDay: paceMetersPerDay,
            projectedFinish: projectedFinish,
            nextWaypoint: nextWaypoint,
            reachedLog: reachedLog
        )
    }

    // MARK: - Convenience over a live instance

    /// Builds stats straight from a persisted instance (reads its template's
    /// waypoints and its crossings). A thin wrapper over the pure entry point.
    static func stats(for journey: UserJourney, now: Date = Date()) -> JourneyStats {
        stats(
            distanceAccumulated: journey.distanceAccumulated,
            totalDistance: journey.totalDistance,
            startDate: journey.startDate,
            status: journey.status,
            completedAt: journey.completedAt,
            pausedAt: journey.pausedAt,
            accumulatedPausedSeconds: journey.accumulatedPausedSeconds,
            waypoints: journey.template?.waypoints ?? [],
            crossings: journey.crossings ?? [],
            now: now
        )
    }
}
