//
//  WaypointPin.swift
//  JourneyTracker
//
//  Teardrop milestone pins for the journey map, rendering the four
//  WaypointState treatments from Design System §07 (reached / next / upcoming /
//  completedFinal). Fill = the journey's accent token; 3pt ink stroke; a 2pt
//  hard offset shadow (no blur, §08). Colors are design tokens only.
//
//  The next-waypoint NAME callout is a SEPARATE view (WaypointCallout), not a
//  child of the fixed-size pin — that fixed frame is exactly what clipped the
//  name to "Th"/"Fir" in the mockup. Rendered on its own with `.fixedSize()`,
//  the full name always lays out.
//

import SwiftUI

/// The pin teardrop silhouette: a circle head over a short tail.
struct PinShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = min(rect.width, rect.height) / 2 * 0.62
        let center = CGPoint(x: rect.midX, y: rect.midY - rect.height * 0.14)
        p.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        p.move(to: CGPoint(x: center.x - r * 0.5, y: center.y + r * 0.75))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: center.x + r * 0.5, y: center.y + r * 0.75))
        p.closeSubpath()
        return p
    }
}

struct WaypointPin: View {
    let state: WaypointState
    /// Design-token NAME for the fill (from `journey.theme.accentColorToken`).
    let accentColorToken: String

    var body: some View {
        ZStack {
            switch state {
            case .reached:
                PinShape().fill(Color(token: accentColorToken))
                PinShape().stroke(Color(token: DesignToken.ink), lineWidth: 3)
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(Color(token: DesignToken.card))
                    .offset(y: -6)
            case .next:
                PinShape().fill(Color(token: accentColorToken))
                PinShape().stroke(Color(token: DesignToken.ink), lineWidth: 3)
                PinShape().stroke(Color(token: DesignToken.reward), lineWidth: 2)
                    .scaleEffect(1.28)
            case .upcoming:
                PinShape()
                    .stroke(Color(token: DesignToken.ink).opacity(0.6),
                            style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                    .opacity(0.6)
            case .completedFinal:
                PinShape().fill(Color(token: DesignToken.reward))
                PinShape().stroke(Color(token: DesignToken.ink), lineWidth: 3)
                Image(systemName: "star.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(Color(token: DesignToken.ink))
                    .offset(y: -6)
            }
        }
        .frame(width: 24, height: 30)
        .shadow(color: Color(token: DesignToken.ink), radius: 0, x: 0,
                y: state == .upcoming ? 0 : 2)
    }
}

/// The always-visible name label for the single `.next` waypoint (§07). Sized
/// to its content via `.fixedSize()` so the full name renders — never clipped
/// to a fixed pin-width frame.
struct WaypointCallout: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(Color(token: DesignToken.ink))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color(token: DesignToken.card), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5)
                .stroke(Color(token: DesignToken.ink), lineWidth: 1.5))
    }
}
