//
//  DistanceFormatter.swift
//  JourneyTracker
//
//  The single place where stored meters become a human-readable distance
//  string. Distances are stored in METERS everywhere; formatting to miles
//  happens ONLY here. Do not scatter `/ 1609.344` across the codebase — views
//  call this and nothing else.
//
//  (Locale-aware km/mi selection is a future concern; the App Concept doc's
//  units row keeps that door open. For now this formats to miles in one place,
//  so switching later is a one-file change.)
//

import Foundation

/// `nonisolated` (opting out of the project's MainActor default isolation) so the
/// single meters→miles formatting authority is callable off the main actor — the
/// notification content provider fills `{miles_*}` placeholders on the ProgressStore
/// actor's context during `apply` (KAN-33 Rulings 4 & 6). The `NumberFormatter`
/// statics are `Sendable` (and read-only), so they stay plain `let`s.
nonisolated enum DistanceFormatter {

    /// Meters in one statute mile.
    static let metersPerMile: Double = 1609.344

    /// Formats a meters value as a miles string, e.g. "3.2 mi".
    static func formattedMiles(_ meters: Double) -> String {
        return "\(milesNumber(meters)) mi"
    }

    /// The single meters→miles conversion for NUMERIC consumers (e.g. the map's
    /// marker mileage along the trek path). Keeps every `/ metersPerMile` inside
    /// this one authority — a caller that needs a number, not a string, uses this
    /// rather than dividing in a view (KAN-21).
    static func miles(_ meters: Double) -> Double {
        meters / metersPerMile
    }

    /// A bare miles numeral (no unit), e.g. "730" or "1,800".
    static func milesNumber(_ meters: Double) -> String {
        let miles = meters / metersPerMile
        return milesNumberFormatter.string(from: NSNumber(value: miles)) ?? "0"
    }

    /// A journey-progress label pairing walked distance with the total, e.g.
    /// "730 / 1,800 mi". The unit is shown once. Keeps every `/ metersPerMile`
    /// division inside this single formatting authority — views never divide.
    static func progressLabel(accumulated: Double, total: Double) -> String {
        return "\(milesNumber(accumulated)) / \(milesNumber(total)) mi"
    }

    /// A pace rate, e.g. "4.2 mi/day", from a meters-per-day figure. Kept HERE
    /// (not in StatFormatter) so every meters→miles division stays inside the
    /// distance authority — the calculator hands over meters/day, views never
    /// divide (App Concept doc, KAN-14 Ruling 8).
    static func milesPerDay(_ metersPerDay: Double) -> String {
        let miles = metersPerDay / metersPerMile
        let number = paceNumberFormatter.string(from: NSNumber(value: miles)) ?? "0"
        return "\(number) mi/day"
    }

    private static let milesNumberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter
    }()

    /// Pace always shows one decimal ("4.2 mi/day", "0.2 mi/day") so a slow pace
    /// never rounds to a bare "0 mi/day".
    private static let paceNumberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return formatter
    }()
}
