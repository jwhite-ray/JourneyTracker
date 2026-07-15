//
//  AvailableJourneysView.swift
//  JourneyTracker
//
//  "Available Journeys" — the catalog / store page and the start flow (KAN-11,
//  mockup Variant B "Compact Manifest" hardened). Pushed onto the existing
//  "Your Journeys" NavigationStack (the same stack that pushes JourneyMapView);
//  on a successful start it pops back, and because "Your Journeys" reads
//  instances via @Query the new active card appears with no manual refresh.
//
//  Lists every JourneyTemplate as a dense single-height row: a leading
//  theme-accent chip, the name, the DistanceFormatter total, a waypoint count
//  ONLY when the template has waypoints, and a trailing affordance:
//    - startable      → an enabled "Start" pill (§07 button rules)
//    - active-blocked → an inline "ACTIVE" caption
//    - paused-blocked → a "PAUSED" caption plus a full, never-truncated
//                       directive line pointing back to Your Journeys
//
//  Startability is decided by ProgressStore's serialized predicate; the row
//  state here is a display mirror of it (no active AND no paused instance =>
//  startable; completed never blocks). The row BODY is inert on every row
//  (Jake's ruling); the only controls are the trailing Start pill (startable)
//  or the quiet labeled ACTIVE/PAUSED marker (blocked), which is a real Button
//  that pops back to Your Journeys, where that template's card and its lifecycle
//  actions live. The start mutation and its double-tap guard live in ProgressStore.
//
//  All colors resolve through design tokens or `template.theme`; no literals.
//

import SwiftUI
import SwiftData

struct AvailableJourneysView: View {
    @Environment(\.dismiss) private var dismiss

    /// The full catalog, one row each, stable-sorted by name.
    @Query(sort: \JourneyTemplate.name) private var templates: [JourneyTemplate]
    /// All instances — used only to derive each template's blocked/startable
    /// display state. The authoritative predicate is re-checked in ProgressStore.
    @Query private var instances: [UserJourney]

    var body: some View {
        content
            .background(Color(token: DesignToken.parchment))
            .navigationTitle("Available Journeys")
    }

    @ViewBuilder
    private var content: some View {
        if templates.isEmpty {
            ZeroTemplatesState()
        } else {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(templates) { template in
                        ManifestRow(
                            template: template,
                            state: state(for: template),
                            onStart: { start(template) },
                            onManage: manageBlocked
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
    }

    // MARK: - Row state (display mirror of the startable predicate)

    /// Active wins the display over paused (matching the one-card precedence on
    /// Your Journeys); either one blocks a store-start. Completed never blocks.
    private func state(for template: JourneyTemplate) -> RowState {
        let mine = instances.filter {
            $0.template?.persistentModelID == template.persistentModelID
        }
        if mine.contains(where: { $0.status == .active }) { return .activeBlocked }
        if mine.contains(where: { $0.status == .paused }) { return .pausedBlocked }
        return .startable
    }

    // MARK: - Actions

    /// Enqueues the serialized start on the shared actor, then pops back ONLY on
    /// success — or on `.notStartable`, which means the template is already
    /// active/paused (e.g. a double-tap's second call): popping back lands the
    /// user right on that blocked card, so it reads as success. Any OTHER error
    /// (save failure, template not found, guard fetch failure) must NOT dismiss
    /// — faking success by popping would hide the failure. We stay on the store
    /// page; surfacing an alert is a later refinement.
    private func start(_ template: JourneyTemplate) {
        let id = template.persistentModelID
        Task {
            do {
                try await ProgressStore.shared.startJourney(templateID: id)
                // KAN-32 Ruling 1: contextual notification permission, requested
                // ONLY after a SUCCESSFUL start — self-gated on `.notDetermined`,
                // so the first journey ever prompts exactly once and every later
                // start/restart no-ops. A `.notStartable` failure (below) is NOT a
                // first journey, so it never reaches here.
                await NotificationManager.shared.requestAuthorizationOnFirstJourney()
                dismiss()
            } catch ProgressStore.LifecycleError.notStartable {
                dismiss()
            } catch {
                // Real failure — leave the user on the store page.
            }
        }
    }

    /// Manage-blocked navigation: pop back to Your Journeys, where the blocked
    /// template's card and its lifecycle actions live. A real labeled control
    /// (not a row gesture) so VoiceOver discovers it.
    private func manageBlocked() {
        dismiss()
    }
}

// MARK: - Row state

private enum RowState {
    case startable
    case activeBlocked
    case pausedBlocked
}

// MARK: - Compact manifest row

private struct ManifestRow: View {
    let template: JourneyTemplate
    let state: RowState
    let onStart: () -> Void
    let onManage: () -> Void

    private var accentToken: String { template.theme.accentColorToken }
    private var waypointCount: Int { template.waypoints?.count ?? 0 }

    var body: some View {
        HStack(spacing: 12) {
            // Leading theme-accent chip. Also the reserved structural slot for a
            // future premium-lock badge / isFeatured emphasis — empty today, not
            // designed as a lock and not gating anything.
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(token: accentToken))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(token: DesignToken.ink), lineWidth: 2))
                .frame(width: 10, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                // No lineLimit: names wrap rather than truncate (must-fix — no
                // truncated text anywhere on the page).
                Text(template.name)
                    .font(.system(size: 15, weight: .bold, design: .serif))
                    .foregroundStyle(Color(token: DesignToken.ink))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("store.rowName.\(template.name)")

                // Meta line: total distance, plus a waypoint count ONLY when the
                // template has waypoints (Around the World omits it — never "0").
                HStack(spacing: 6) {
                    Text(DistanceFormatter.formattedMiles(template.totalDistance))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(token: DesignToken.ink).opacity(0.6))
                    if waypointCount > 0 {
                        // Inflection markup (String Catalog) pluralizes correctly:
                        // "1 waypoint" vs "8 waypoints", never "1 waypoints".
                        Text("· ^[\(waypointCount) waypoint](inflect: true)")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(token: DesignToken.ink).opacity(0.45))
                    }
                }

                // Paused directive on its OWN line, wrapping freely — the full
                // text always renders, never truncated at row density (must-fix).
                if state == .pausedBlocked {
                    Text("Paused — resume or restart on Your Journeys")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(token: DesignToken.ink).opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("store.status.\(template.name)")
                }
            }

            Spacer(minLength: 8)

            trailingAffordance
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(token: DesignToken.card), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(Color(token: DesignToken.ink), lineWidth: 2))
        // The row BODY is inert on every row (startable and blocked) — Jake's
        // ruling. Blocked navigation is a real labeled control in the trailing
        // affordance, not a row-level gesture, so VoiceOver discovers it.
    }

    @ViewBuilder
    private var trailingAffordance: some View {
        switch state {
        case .startable:
            Button(action: onStart) {
                PillStartButton(fillToken: accentToken)
                    // Pill visuals unchanged; the hit target meets the 44pt
                    // minimum like the blocked-state controls.
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("store.startButton.\(template.name)")

        case .activeBlocked:
            // A real labeled control (not a row gesture): the quiet "ACTIVE"
            // marker IS the button, popping back to manage the run on Your
            // Journeys. Small/quiet visual, explicit and VoiceOver-discoverable.
            Button(action: onManage) {
                Text("ACTIVE")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .kerning(0.8)
                    .foregroundStyle(Color(token: DesignToken.accentPrimary))
                    // Visuals stay quiet; the hit target meets the 44pt minimum.
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Active — manage on Your Journeys")
            .accessibilityIdentifier("store.status.\(template.name)")

        case .pausedBlocked:
            // The directive line (above) carries the full instruction; this is
            // the compact status marker + a "goes somewhere" chevron, wrapped as
            // the labeled manage control.
            Button(action: onManage) {
                HStack(spacing: 4) {
                    Text("PAUSED")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .kerning(0.8)
                        .foregroundStyle(Color(token: DesignToken.ink))
                        .opacity(0.6)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color(token: DesignToken.ink).opacity(0.4))
                }
                // Visuals stay quiet; the hit target meets the 44pt minimum.
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Paused — manage on Your Journeys")
            .accessibilityIdentifier("store.manageButton.\(template.name)")
        }
    }
}

// MARK: - Trailing "Start" pill (§07 button rules — crisp 3pt ink stroke, no shadow)

private struct PillStartButton: View {
    let fillToken: String

    var body: some View {
        Text("Start")
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(Color(token: DesignToken.ink))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 999)
                    .fill(Color(token: fillToken))
                    .overlay(RoundedRectangle(cornerRadius: 999)
                        .stroke(Color(token: DesignToken.ink), lineWidth: 3))
            }
    }
}

// MARK: - Zero-templates minimal state

private struct ZeroTemplatesState: View {
    var body: some View {
        VStack(spacing: 6) {
            Spacer(minLength: 12)
            Text("Nothing in the catalog yet.")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(token: DesignToken.ink).opacity(0.55))
                .accessibilityIdentifier("store.zeroTemplates")
            Spacer(minLength: 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(token: DesignToken.parchment))
    }
}
