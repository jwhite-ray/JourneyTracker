//
//  NotificationPrimingView.swift
//  JourneyTracker
//
//  The pre-permission priming screen (KAN-42), a half-sheet presented over
//  "Available Journeys" right after the user's FIRST successful journey start —
//  BEFORE the system permission API is ever called. It fronts the KAN-32
//  Ruling-1 request so the OS one-shot is only spent on a user who already said
//  yes to ours.
//
//  This view knows NOTHING about UserNotifications / UNUserNotificationCenter —
//  it imports no such thing and holds no authorization logic (KAN-42 Ruling 1).
//  It only calls back out through `onEnable` / `onNotNow`; the caller
//  (AvailableJourneysView) is what invokes the existing
//  `NotificationManager.shared.requestAuthorizationOnFirstJourney()` on Enable,
//  and NOTHING on any other exit (Not now button OR swipe-dismiss), so
//  `authorization` stays `.notDetermined` and the re-offer gate is preserved.
//
//  Copy is player-voice (NOT the `{character}` seam) and lives verbatim in the
//  `Text(_:)` literals so it is extracted to the String Catalog and never
//  truncates (every block wraps via `fixedSize`). All colors resolve through
//  design tokens — no literals, no OS-alert impersonation (§07 button spec).
//

import SwiftUI

/// Variant A — the "Compact Bottom Sheet" priming card, hardened from
/// `Mockups/PrimingVariantA_BottomSheet.swift`. Half-sheet: a small pin /
/// posted-notice motif, headline, body, a full-width primary "Turn On
/// Notifications" button (§07), and a quiet "Not now" text link.
struct NotificationPrimingView: View {
    /// Invoked by the primary CTA. The caller runs the real system request here;
    /// this view never touches authorization state itself.
    var onEnable: () -> Void
    /// Invoked by the quiet "Not now" link. The caller does NOTHING to
    /// authorization on this path (a true no-op), identical to a swipe-dismiss.
    var onNotNow: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            // We draw our own drag indicator (the system one is hidden) so the
            // card reads as ours, not an OS surface.
            Capsule()
                .fill(Color(token: DesignToken.ink).opacity(0.25))
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            WaybillMotif()
                .padding(.top, 4)

            VStack(spacing: 10) {
                Text("Stay in the loop as you journey")
                    .font(.system(size: 22, weight: .bold, design: .serif))
                    .foregroundStyle(Color(token: DesignToken.ink))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("priming.headline")

                Text("We'll tell you the moment you reach waypoints or finish journeys. Make sure to select allow notifications on the next screen")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(token: DesignToken.ink).opacity(0.8))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("priming.body")
            }
            .padding(.horizontal, 28)

            VStack(spacing: 10) {
                Button(action: onEnable) {
                    Text("Turn On Notifications")
                }
                .buttonStyle(PrimingPrimaryButtonStyle(fillToken: DesignToken.accentPrimary))
                .accessibilityIdentifier("priming.enable")

                Button(action: onNotNow) {
                    Text("Not now")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(token: DesignToken.ink).opacity(0.55))
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("priming.notNow")
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 8)
        }
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(Color(token: DesignToken.parchment))
    }
}

// MARK: - Primary CTA button style (§07: radius 12, filled accent, 3pt ink
// stroke, no shadow, 2pt press-translate)

private struct PrimingPrimaryButtonStyle: ButtonStyle {
    let fillToken: String
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundStyle(Color(token: DesignToken.ink))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(token: fillToken))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(token: DesignToken.ink), lineWidth: 3)
                    )
            }
            .offset(y: configuration.isPressed ? 2 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

// MARK: - Illustration slot: a small pinned posted-notice motif

/// A tiny "posted notice" — a card corner-tucked with a small accent pin —
/// evoking the parchment-and-pin world without drawing a full map or character.
/// Deliberately small and quiet, matching Variant A's low density.
private struct WaybillMotif: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(token: DesignToken.card))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(token: DesignToken.ink), lineWidth: 2.5)
                )
                .frame(width: 52, height: 44)
                .rotationEffect(.degrees(-4))

            // The "pin" — a small teardrop echoing the §07.8 waypoint pin
            // anatomy, reached-state fill, at the note's top corner.
            PinTeardrop()
                .fill(Color(token: DesignToken.reward))
                .overlay(PinTeardrop().stroke(Color(token: DesignToken.ink), lineWidth: 2))
                .frame(width: 16, height: 20)
                .rotationEffect(.degrees(-4))
                .offset(x: 16, y: -22)
        }
        .frame(width: 60, height: 60)
        .accessibilityHidden(true)
    }
}

private struct PinTeardrop: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = rect.width / 2
        p.addArc(center: CGPoint(x: rect.midX, y: rect.minY + r),
                 radius: r, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + r * 1.15))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + r * 1.15))
        p.closeSubpath()
        return p
    }
}

#Preview("Priming — Bottom Sheet") {
    Color(token: DesignToken.parchment)
        .sheet(isPresented: .constant(true)) {
            NotificationPrimingView(onEnable: {}, onNotNow: {})
                .presentationDetents([.height(360), .medium])
                .presentationDragIndicator(.hidden)
        }
}
