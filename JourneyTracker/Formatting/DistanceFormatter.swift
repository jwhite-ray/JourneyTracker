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

enum DistanceFormatter {

    /// Meters in one statute mile.
    static let metersPerMile: Double = 1609.344

    /// Formats a meters value as a miles string, e.g. "3.2 mi".
    static func formattedMiles(_ meters: Double) -> String {
        return "\(milesNumber(meters)) mi"
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
