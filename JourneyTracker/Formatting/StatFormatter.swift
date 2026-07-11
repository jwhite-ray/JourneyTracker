//
//  StatFormatter.swift
//  JourneyTracker
//
//  The single formatting authority for CALENDAR DATES and ELAPSED DURATIONS in
//  the journey-stats feature (KAN-14, Ruling 8) — a sibling to DistanceFormatter
//  (which stays distance-only, including the mi/day pace rate). All date and
//  duration formatting for the feature lives here, so "formatting happens in
//  exactly one place" holds for time exactly as it does for distance.
//
//  Timestamps are stored in UTC (Date is absolute); display is locale-aware and
//  rendered in the user's current calendar/time zone here, at the view boundary.
//

import Foundation

enum StatFormatter {

    // MARK: - Dates

    /// A locale-aware medium date with NO time, e.g. "Jun 3, 2026". Used for the
    /// start date, date-reached, projected finish, and finish date — one shared
    /// style for every calendar date in the feature (Ruling 8).
    static func date(_ date: Date) -> String {
        mediumDateFormatter.string(from: date)
    }

    private static let mediumDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    // MARK: - Durations (Ruling 8)

    /// Formats an elapsed span (SECONDS) with the KAN-14 duration rule. The unit
    /// is chosen from the ROUNDED value (round first, then band) so a boundary
    /// never contradicts its own unit — 59m50s reads "1 hour", not "60 minutes",
    /// and 47.8h reads "2 days", not "48 hours". Singular/plural handled; no
    /// absurd extremes:
    ///
    ///   < 1 minute        → "under a minute"
    ///   rounds to < 60m   → whole minutes  ("1 minute"  / "47 minutes")
    ///   rounds to < 48h   → whole hours    ("1 hour"    / "14 hours")
    ///   rounds to ≥ 48h   → whole days     ("2 days")   — long spans stay in days
    ///
    /// A negative input (clock skew) is treated as zero.
    static func duration(_ seconds: Double) -> String {
        let s = max(0, seconds)

        if s < 60 {
            return "under a minute"
        }
        if s < 3_600 {
            let minutes = Int((s / 60).rounded())
            // Round-up carry: 60 minutes reads as "1 hour", not "60 minutes".
            if minutes >= 60 { return pluralized(minutes / 60, "hour") }
            return pluralized(minutes, "minute")
        }
        if s < 172_800 { // < 48 hours
            let hours = Int((s / 3_600).rounded())
            // Round-up carry: 48 hours reads as "2 days", not "48 hours".
            if hours >= 48 { return pluralized(hours / 24, "day") }
            return pluralized(hours, "hour")
        }
        let days = Int((s / 86_400).rounded())
        return pluralized(days, "day")
    }

    private static func pluralized(_ count: Int, _ unit: String) -> String {
        let n = max(1, count)
        return "\(n) \(unit)\(n == 1 ? "" : "s")"
    }
}
