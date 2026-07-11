//
//  JourneyStatsSection.swift
//  JourneyTracker
//
//  The KAN-14 journey-stats block on the map screen (chosen direction: Variant A
//  "Stat Tiles", with the user's amendments). It sits BELOW the progress bar; the
//  map field keeps its shipped size and the screen scrolls (amendment 2).
//
//  Two parts:
//   • A 2×2 grid of §07 stat tiles — STARTED / DAYS ON JOURNEY / AVG. PACE /
//     PROJECTED FINISH (→ FINISHED when completed). AMENDMENT 1: every tile's
//     value renders at ONE uniform size, matching the date value — the mockup's
//     larger serif numerals on the day-count / pace tiles are rejected.
//   • A "WAYPOINTS REACHED" timeline log with a tick rail + checkmarks, one row
//     per reached waypoint. Omitted entirely for a zero-waypoint journey.
//
//  Reads a pure `JourneyStats` (from JourneyStatsCalculator) and formats via
//  StatFormatter / DistanceFormatter — this view never divides or fabricates.
//  All color/type via design tokens + the journey's accent token.
//

import SwiftUI

struct JourneyStatsSection: View {
    let stats: JourneyStats
    /// The journey's accent token (from `journey.theme.accentColorToken`) — the
    /// reached-dot fill.
    let accentColorToken: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            tileGrid

            if stats.hasWaypoints {
                waypointLog
            }
            // Zero-waypoint journeys: the waypoint section is omitted outright —
            // no header, no empty state.
        }
    }

    // MARK: - 2×2 stat tile grid

    private var tileGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
            spacing: 10
        ) {
            StatTile(
                eyebrow: "STARTED",
                value: StatFormatter.date(stats.startDate),
                caption: nil,
                identifier: "map.stat.started"
            )

            StatTile(
                eyebrow: timeOnJourneyEyebrow,
                value: stats.daysOnJourneySeconds.map(StatFormatter.duration) ?? placeholderValue,
                caption: stats.daysOnJourneySeconds == nil ? notEnoughDataCaption : nil,
                identifier: "map.stat.daysOnJourney"
            )

            StatTile(
                eyebrow: "AVG. PACE",
                value: stats.paceMetersPerDay.map(DistanceFormatter.milesPerDay) ?? placeholderValue,
                caption: stats.paceMetersPerDay == nil ? notEnoughDataCaption : nil,
                identifier: "map.stat.pace"
            )

            if stats.isCompleted {
                StatTile(
                    eyebrow: "FINISHED",
                    value: stats.completedAt.map(StatFormatter.date) ?? "date not recorded",
                    caption: nil,
                    identifier: "map.stat.finished"
                )
            } else {
                StatTile(
                    eyebrow: "PROJECTED FINISH",
                    value: stats.projectedFinish.map(StatFormatter.date) ?? placeholderValue,
                    caption: stats.projectedFinish == nil ? notEnoughDataCaption : nil,
                    identifier: "map.stat.projectedFinish"
                )
            }
        }
    }

    private var placeholderValue: String { "—" }

    /// KAN-15: the header names the unit the value actually shows — never
    /// "DAYS ON JOURNEY" over an hours (or minutes) value.
    private var timeOnJourneyEyebrow: String {
        guard let seconds = stats.daysOnJourneySeconds else { return "DAYS ON JOURNEY" }
        switch StatFormatter.durationUnit(seconds) {
        case .days: return "DAYS ON JOURNEY"
        case .hours: return "HOURS ON JOURNEY"
        case .minutes: return "TIME ON JOURNEY"
        }
    }
    private var notEnoughDataCaption: String { "Not enough data yet" }

    // MARK: - Waypoints-reached timeline log

    private var waypointLog: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WAYPOINTS REACHED")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .kerning(11 * 0.14)
                .foregroundStyle(Color(token: DesignToken.ink).opacity(0.6))

            if stats.reachedLog.isEmpty {
                Text("No waypoints reached yet.")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(token: DesignToken.ink).opacity(0.6))
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(stats.reachedLog.enumerated()), id: \.element.id) { index, row in
                        TimelineRow(
                            row: row,
                            accentColorToken: accentColorToken,
                            isFirst: index == 0,
                            isLast: index == stats.reachedLog.count - 1
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(token: DesignToken.card), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(Color(token: DesignToken.ink), lineWidth: 2))
        .accessibilityIdentifier("map.crossingLog")
    }
}

// MARK: - Stat tile (§07 stat card — radius 14, 2pt border; UNIFORM value size)

private struct StatTile: View {
    let eyebrow: String
    let value: String
    let caption: String?
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .kerning(11 * 0.14)
                .foregroundStyle(Color(token: DesignToken.ink).opacity(0.6))

            // AMENDMENT 1: one uniform value size across all four tiles, matching
            // the date value — the mockup's larger serif numerals are rejected.
            // No minimumScaleFactor: a long value ("date not recorded") must NOT
            // shrink below its neighbors (that would soft-break the uniform size),
            // so it wraps to a second line at the same size and the tile grows.
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .serif))
                .foregroundStyle(Color(token: DesignToken.ink))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(identifier)

            if let caption {
                Text(caption)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(token: DesignToken.ink).opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(token: DesignToken.card), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(Color(token: DesignToken.ink), lineWidth: 2))
    }
}

// MARK: - Timeline row (tick rail + checkmark)

private struct TimelineRow: View {
    let row: ReachedWaypointRow
    let accentColorToken: String
    let isFirst: Bool
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Tick rail: every row is a REACHED waypoint, so every dot is filled
            // and checked (an empty dot under a "reached" header would read as
            // not-reached). An unrecorded crossing carries its signal in the
            // "date not recorded" text below, not by emptying the tick.
            VStack(spacing: 0) {
                Circle()
                    .fill(Color(token: accentColorToken))
                    .frame(width: 16, height: 16)
                    .overlay(Circle().stroke(Color(token: DesignToken.ink), lineWidth: 2))
                    .overlay {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .black))
                            .foregroundStyle(Color(token: DesignToken.ink))
                    }
                if !isLast {
                    Rectangle()
                        .fill(Color(token: DesignToken.ink).opacity(0.3))
                        .frame(width: 2)
                        .frame(minHeight: 24)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(token: DesignToken.ink))
                Text(row.crossedAt.map(StatFormatter.date) ?? "date not recorded")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(token: DesignToken.ink).opacity(0.7))
                    .accessibilityIdentifier("map.crossing.\(row.name)")
                Text(timeTakenText)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(token: DesignToken.ink).opacity(0.5))
            }
            .padding(.bottom, isLast ? 0 : 10)

            Spacer(minLength: 0)
        }
    }

    private var timeTakenText: String {
        guard let seconds = row.timeTakenSeconds else { return "\u{2014}" }
        // The first row's interval is measured from the journey startDate
        // (Ruling 4: no origin crossing exists), so its label says so.
        return "\(StatFormatter.duration(seconds)) since \(isFirst ? "start" : "previous")"
    }
}
