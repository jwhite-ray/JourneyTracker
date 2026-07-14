//
//  WrenMarker.swift
//  JourneyTracker
//
//  Wren, the faceted wayfarer marker, drawn PROCEDURALLY in SwiftUI — no binary
//  art is bundled yet (see KAN-7). This is the ACTUAL §04 rig, not a simplified
//  figure: one layered vector stack on a 180×216 design box, scaled uniformly to
//  the marker's on-map size, with fixed proportions and the flat-facet language
//  (base mid-tone + top-left highlight + bottom-right shadow, no gradients, no
//  mouth). Facet colors are DERIVED from the design tokens (char/cloak, char/skin,
//  surface/card, ink) via Color.facetHighlight/facetShadow — never literal.
//
//  When real marker art ships, the journey's `theme.markerImageName` is the swap
//  point — see JourneyMapView, which prefers a bundled image of that name and
//  falls back to this procedural rig when none exists.
//

import SwiftUI

// MARK: - Facet primitives (§04)

/// A shape's flat facet: a top-left highlight or a bottom-right shadow patch,
/// clipped to the parent silhouette (§04). The §04 CSS `clip-path: polygon(0 0,
/// 100% 0, 100% 45%, 0 70%)` becomes a four-point Path in local coordinates —
/// but the literal recipe's highlight and its mirrored shadow OVERLAP, so their
/// union covers the whole silhouette and the base mid-tone never shows. §04 wants
/// three visible tones (base + highlight + shadow, "2–3 flat facets on top of a
/// visible base"), so we pull both facet edges apart to leave a constant ~20% mid
/// band: the highlight's bottom edge and the shadow's top edge run parallel
/// (same −0.25h slope) with the base showing through between them at every x.
private struct FacetPatch: Shape {
    var topLeading: Bool
    func path(in rect: CGRect) -> Path {
        let h = rect.height
        var p = Path()
        if topLeading {
            // Top-left highlight. Bottom edge: 0.58h (left) → 0.33h (right).
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + h * 0.33))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + h * 0.58))
        } else {
            // Bottom-right shadow. Top edge: 0.78h (left) → 0.53h (right), i.e.
            // 0.20h below the highlight's bottom edge at every x — the mid band.
            p.move(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - h * 0.22))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - h * 0.47))
        }
        p.closeSubpath()
        return p
    }
}

/// One faceted body part: base mid-tone fill, a +10% L highlight clipped
/// top-left and a −12% L shadow clipped bottom-right, all clipped to the part's
/// own rounded silhouette. Both facets are DERIVED from `base`, so a re-themed
/// base carries through. No literal colors here (§04).
private struct Faceted<S: Shape>: View {
    var shape: S
    var base: Color
    var body: some View {
        ZStack {
            shape.fill(base)
            FacetPatch(topLeading: true).fill(Color.facetHighlight(of: base)).clipShape(shape)
            FacetPatch(topLeading: false).fill(Color.facetShadow(of: base)).clipShape(shape)
        }
    }
}

/// A thin lower eyelid, filled in skin and clipped to the eye circle: an arc
/// rising from the eye's lower corners across the bottom of the iris. Gives the
/// mid-route "neutral/calm" smize without ever adding a mouth (§01/§04).
private struct LowerLid: Shape {
    func path(in rect: CGRect) -> Path {
        let h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + h * 0.88))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + h * 0.88),
                       control: CGPoint(x: rect.midX, y: rect.minY + h * 0.76))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath(); return p
    }
}

// MARK: - The rig, drawn at native 180×216 design-box coordinates

/// Wren, laid out at the §04 design-box size. WrenMarker scales this down to the
/// on-map marker size. All coordinates below are in the 180×216 box.
private struct WrenRig: View {
    /// true = parked / completed (fresh: raised brows, no lean, resting).
    /// false = mid-route (neutral/calm: soft-raised brows, gaze up-and-forward,
    /// thin lower lid, forward lean).
    var resting: Bool

    // Design box.
    private let box = CGSize(width: 180, height: 216)

    // Token-derived bases (facets come from these via the §04 helpers).
    private var cloak: Color { Color(token: DesignToken.charCloak) }
    private var skin: Color { Color(token: DesignToken.charSkin) }
    private var hair: Color { Color(token: DesignToken.charHair) }
    private var ink: Color { Color(token: DesignToken.ink) }
    private var eyeWhite: Color { Color(token: DesignToken.card) }

    var body: some View {
        ZStack {
            // 0 · Ground contact shadow (stays on the ground — not leaned).
            Ellipse()
                .fill(ink.opacity(0.18))
                .frame(width: 74, height: 18)
                .position(x: 90, y: 200)

            // Completion reward ring, parked "fresh" only (§07). Behind the
            // figure so the rig reads in front of it.
            if resting {
                // Fits inside the 180-wide box (⌀172) so a map-edge clipShape
                // won't slice it, and a 16pt box stroke reads ~3pt at marker
                // scale — matching the §07 emphasis-ring weight.
                Circle()
                    .stroke(Color(token: DesignToken.reward), lineWidth: 16)
                    .frame(width: 172, height: 172)
                    .position(x: 90, y: 104)
            }

            // The character, leaned forward when walking (§04 "neutral/calm").
            figure
                .rotationEffect(.degrees(resting ? 0 : 6), anchor: .bottom)
        }
        .frame(width: box.width, height: box.height)
    }

    /// Construction order (back → front): feet → back arm → staff → pack →
    /// body (cloak) → belt → ears → face circle → hair → eye whites → pupils →
    /// lower lids → eyebrows. (The ground shadow — step 0 of §04 — lives outside
    /// the lean.)
    private var figure: some View {
        ZStack {
            // 1 · Feet (big, no visible hands = the small-folk read).
            faceted(RoundedRectangle(cornerRadius: 11), base: skin,
                    w: 24, h: 38, x: 76, y: 183)
            faceted(RoundedRectangle(cornerRadius: 11), base: skin,
                    w: 24, h: 38, x: 104, y: 183)

            // 2 · Back arm (peeks out behind the cloak on the far side).
            faceted(RoundedRectangle(cornerRadius: 13), base: cloak,
                    w: 26, h: 56, x: 48, y: 128, rotation: 8)

            // 3 · Staff (behind the body: pokes above the shoulder and below the
            //     hem). char/cloak = neutral prop tone.
            faceted(RoundedRectangle(cornerRadius: 4), base: cloak,
                    w: 8, h: 150, x: 131, y: 116, rotation: -4)
            faceted(Circle(), base: cloak, w: 15, h: 15, x: 134, y: 44)   // staff knob

            // 4 · Pack (slung on the back, peeks above/left of the cloak).
            faceted(RoundedRectangle(cornerRadius: 12), base: cloak,
                    w: 34, h: 42, x: 56, y: 104)

            // 5 · Body (cloak).
            faceted(RoundedRectangle(cornerRadius: 20), base: cloak,
                    w: 90, h: 68, x: 90, y: 138)

            // 6 · Belt (thin ink band across the cloak). Subpixel at marker scale.
            Capsule()
                .fill(ink)
                .frame(width: 90, height: 8)
                .position(x: 90, y: 148)

            // 7 · Ears (skin), at the sides of the head, below the hairline.
            faceted(Circle(), base: skin, w: 16, h: 16, x: 60, y: 86)
            faceted(Circle(), base: skin, w: 16, h: 16, x: 120, y: 86)

            // 8 · Face circle (head ⌀60).
            faceted(Circle(), base: skin, w: 60, h: 60, x: 90, y: 82)

            // 9 · Hair (bare curly crown) — faceted circles hugging the crown
            //     with a fringe at the hairline, replacing the old hood.
            hairCurls

            // 10 · Eyes: each a 16×16 clipped ZStack of {eye-white, pupil ⌀7 ink,
            //     skin lower lid}. Pupils gaze up-and-forward when walking.
            let pupilDY: CGFloat = resting ? -1 : -2
            eye(x: 78, y: 90, pupilDY: pupilDY)
            eye(x: 102, y: 90, pupilDY: pupilDY)

            // 11 · Eyebrows (ink) — emotion lives here, never a mouth (§01/§04).
            //  Neutral/calm: soft-raised. Fresh: raised, arched out.
            eyebrows
        }
        .frame(width: box.width, height: box.height)
    }

    /// Bare curly hair: faceted circles (base `hair`) hugging the crown with a
    /// fringe at the hairline, drawn in the same §04 flat-facet language.
    private var hairCurls: some View {
        ZStack {
            faceted(Circle(), base: hair, w: 22, h: 22, x: 90, y: 46)
            faceted(Circle(), base: hair, w: 20, h: 20, x: 72, y: 48)
            faceted(Circle(), base: hair, w: 20, h: 20, x: 108, y: 48)
            faceted(Circle(), base: hair, w: 19, h: 19, x: 58, y: 58)
            faceted(Circle(), base: hair, w: 19, h: 19, x: 122, y: 58)
            faceted(Circle(), base: hair, w: 18, h: 18, x: 82, y: 56)
            faceted(Circle(), base: hair, w: 18, h: 18, x: 98, y: 56)
            faceted(Circle(), base: hair, w: 17, h: 17, x: 90, y: 60)
            faceted(Circle(), base: hair, w: 15, h: 15, x: 66, y: 66)
            faceted(Circle(), base: hair, w: 15, h: 15, x: 80, y: 66)
            faceted(Circle(), base: hair, w: 15, h: 15, x: 94, y: 66)
            faceted(Circle(), base: hair, w: 15, h: 15, x: 108, y: 66)
        }
    }

    /// One eye: a 16×16 clipped ZStack of eye-white, ink pupil (⌀7, offset by
    /// `pupilDY`), and a thin skin lower lid, positioned at (x, y) in the box.
    private func eye(x: CGFloat, y: CGFloat, pupilDY: CGFloat) -> some View {
        ZStack {
            Circle().fill(eyeWhite)
            Circle().fill(ink).frame(width: 7, height: 7).position(x: 8, y: 8 + pupilDY)
            LowerLid().fill(skin)
        }
        .frame(width: 16, height: 16).clipShape(Circle()).position(x: x, y: y)
    }

    private var eyebrows: some View {
        // Neutral/calm: soft-raised. Fresh: raised, arched out.
        let leftAngle: Double = resting ? -12 : -6
        let rightAngle: Double = resting ? 12 : 6
        let browY: CGFloat = resting ? 74 : 78
        return Group {
            Capsule().fill(ink).frame(width: 20, height: 5)
                .rotationEffect(.degrees(leftAngle))
                .position(x: 78, y: browY)
            Capsule().fill(ink).frame(width: 20, height: 5)
                .rotationEffect(.degrees(rightAngle))
                .position(x: 102, y: browY)
        }
    }

    /// Places a faceted part centered at (x, y) in the design box.
    private func faceted<S: Shape>(_ shape: S, base: Color,
                                   w: CGFloat, h: CGFloat,
                                   x: CGFloat, y: CGFloat,
                                   rotation: Double = 0) -> some View {
        Faceted(shape: shape, base: base)
            .frame(width: w, height: h)
            .rotationEffect(.degrees(rotation))
            .position(x: x, y: y)
    }
}

// MARK: - The on-map marker

struct WrenMarker: View {
    /// true = parked / completed (fresh, raised brows); false = walking
    /// (neutral/calm, forward lean). Drives the §04 emotional state.
    var resting: Bool

    /// Uniform down-scale of the 180×216 rig to the on-map marker size. Keeps
    /// the rig ~34pt wide, matching the bundled-image branch (32×40) in
    /// JourneyMapView while preserving §04 proportions exactly.
    private let scale: CGFloat = 0.19

    var body: some View {
        WrenRig(resting: resting)
            .frame(width: 180, height: 216)
            .scaleEffect(scale, anchor: .center)
            .frame(width: 180 * scale, height: 216 * scale)
    }
}

#Preview("Wren — poses") {
    HStack(spacing: 40) {
        WrenMarker(resting: false)   // walking (neutral)
        WrenMarker(resting: true)    // resting (fresh)
    }
    .scaleEffect(6)
    .padding(120)
    .background(Color(token: DesignToken.parchment))
}
