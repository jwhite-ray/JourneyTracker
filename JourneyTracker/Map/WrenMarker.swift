//
//  WrenMarker.swift
//  JourneyTracker
//
//  Wren, the wayfarer marker, drawn PROCEDURALLY in SwiftUI — no binary art is
//  bundled yet (see KAN-7). The rig follows Design System §04's flat-facet
//  language (base + top-left highlight + bottom-right shadow, no gradients, no
//  mouth). Facet colors come from design tokens (char/cloak, char/skin, ink).
//
//  When real marker art ships, the journey's `theme.markerImageName` is the
//  swap point — see JourneyMapView, which prefers a bundled image of that name
//  and falls back to this procedural rig when none exists.
//

import SwiftUI

/// A shape's flat facet: a top-left highlight or a bottom-right shadow patch,
/// clipped to the parent silhouette (§04). Never a gradient.
private struct FacetPatch: Shape {
    var topLeading: Bool
    func path(in rect: CGRect) -> Path {
        var p = Path()
        if topLeading {
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.45))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.7))
        } else {
            p.move(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - rect.height * 0.45))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - rect.height * 0.7))
        }
        p.closeSubpath()
        return p
    }
}

private struct Faceted<S: Shape>: View {
    var shape: S
    var base: Color
    var body: some View {
        ZStack {
            shape.fill(base)
            FacetPatch(topLeading: true).fill(Color.white.opacity(0.16)).clipShape(shape)
            FacetPatch(topLeading: false).fill(Color.black.opacity(0.16)).clipShape(shape)
        }
    }
}

struct WrenMarker: View {
    /// true = parked / completed (fresh, raised brows); false = walking
    /// (determined, forward lean). Drives the §04 emotional state.
    var resting: Bool

    var body: some View {
        ZStack {
            // Contact shadow.
            Ellipse().fill(Color(token: DesignToken.ink).opacity(0.18))
                .frame(width: 26, height: 8).offset(y: 17)
            // Body (cloak).
            Faceted(shape: RoundedRectangle(cornerRadius: 6), base: Color(token: DesignToken.charCloak))
                .frame(width: 20, height: 16).offset(y: 10)
            // Hood.
            Faceted(shape: Capsule(), base: Color(token: DesignToken.charCloak))
                .frame(width: 18, height: 12).offset(y: -6)
            // Face circle.
            Faceted(shape: Circle(), base: Color(token: DesignToken.charSkin))
                .frame(width: 16, height: 16)
            // Pupils — no mouth (§01).
            HStack(spacing: 4) {
                Circle().fill(Color(token: DesignToken.ink)).frame(width: 2.5, height: 2.5)
                Circle().fill(Color(token: DesignToken.ink)).frame(width: 2.5, height: 2.5)
            }
            // Eyebrows: raised (fresh) when resting, angled-in (determined) when walking.
            HStack(spacing: 6) {
                Capsule().fill(Color(token: DesignToken.ink)).frame(width: 4, height: 1.5)
                    .rotationEffect(.degrees(resting ? 8 : -8))
                Capsule().fill(Color(token: DesignToken.ink)).frame(width: 4, height: 1.5)
                    .rotationEffect(.degrees(resting ? -8 : 8))
            }
            .offset(y: -4)
            // Parked-at-the-summit reward ring.
            if resting {
                Circle()
                    .stroke(Color(token: DesignToken.reward), lineWidth: 2)
                    .frame(width: 30, height: 30)
            }
        }
    }
}
