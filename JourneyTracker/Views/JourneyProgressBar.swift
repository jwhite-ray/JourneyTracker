//
//  JourneyProgressBar.swift
//  JourneyTracker
//
//  The Design System §07 progress bar, shared by the journey card and the map
//  screen. Height 22, 3pt ink border, radius 999 (Capsule), fill = the
//  journey's accent token. The label is produced by DistanceFormatter — the
//  only place meters become miles.
//

import SwiftUI

struct JourneyProgressBar: View {
    /// 0...1, already capped upstream by `Journey.progress`.
    let progress: Double
    /// Design-token NAME for the fill (from `journey.theme.accentColorToken`).
    let accentColorToken: String
    /// Preformatted "730 / 1,800 mi" label (from DistanceFormatter).
    let label: String
    /// Leaf accessibility identifiers supplied by the caller.
    let barIdentifier: String
    let labelIdentifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(token: DesignToken.card))
                    Capsule()
                        .fill(Color(token: accentColorToken))
                        .frame(width: geo.size.width * max(0, min(1, progress)))
                    Capsule().stroke(Color(token: DesignToken.ink), lineWidth: 3)
                }
            }
            .frame(height: 22)
            .accessibilityIdentifier(barIdentifier)

            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(token: DesignToken.ink))
                .accessibilityIdentifier(labelIdentifier)
        }
    }
}
