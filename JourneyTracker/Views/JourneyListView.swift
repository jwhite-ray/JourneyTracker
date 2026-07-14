//
//  JourneyListView.swift
//  JourneyTracker
//
//  The app's main screen, "Your Journeys" (KAN-10, mockup Variant C hardened —
//  "corner stamp + kebab menu"). One Card Cream card per JourneyTemplate,
//  showing the highest-precedence instance for that template (active > most-
//  recent paused > most-recent completed — App Concept doc, Ruling 1). Each
//  card carries a STRAIGHT status stamp (no rotation, per Design System v1.3
//  §07), the shared progress bar, a "View Map" link, and a ••• kebab that
//  collapses the lifecycle actions.
//
//  Reads persisted instances via @Query. All lifecycle WRITES route through the
//  single shared `ProgressStore` actor — this view never mutates a model on the
//  main context. When there are no instances, a quiet empty state shows.
//

import SwiftUI
import SwiftData

struct JourneyListView: View {
    @Query private var instances: [UserJourney]

    /// Which card's kebab menu is open (by the shown instance's identity).
    @State private var openMenuID: PersistentIdentifier?
    /// The paused instance awaiting destructive restart confirmation.
    @State private var pendingPausedRestart: UserJourney?
    /// The instance (any status) awaiting destructive delete confirmation
    /// (KAN-13). Delete wipes ALL of its template's instances.
    @State private var pendingDelete: UserJourney?
    /// Drives the shared push to Available Journeys (the store). Both the
    /// toolbar `+` and the empty-state CTA set this — one destination (KAN-11).
    @State private var showingStore = false

    /// One card per template: the highest-precedence instance for each. Active
    /// wins; else the most-recent paused; else the most-recent completed.
    private var cards: [UserJourney] {
        let groups = Dictionary(grouping: instances) { $0.template?.persistentModelID }
        let chosen = groups.compactMap { key, group -> UserJourney? in
            guard key != nil else { return nil } // orphan instances have no card
            if let active = group.first(where: { $0.status == .active }) {
                return active
            }
            if let paused = group.filter({ $0.status == .paused })
                .max(by: { $0.startDate < $1.startDate }) {
                return paused
            }
            return group.filter { $0.status == .completed }
                .max(by: { $0.startDate < $1.startDate })
        }
        // Stable order by name so cards don't shuffle between refreshes.
        return chosen.sorted { $0.name < $1.name }
    }

    var body: some View {
        content
            .background(Color(token: DesignToken.parchment))
            .navigationTitle("Your Journeys")
            // The `+` entry point to Available Journeys — always visible,
            // populated or empty (KAN-11).
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingStore = true } label: {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Color(token: DesignToken.ink))
                    }
                    .accessibilityIdentifier("list.addJourneyButton")
                    .accessibilityLabel("Available Journeys")
                }
            }
            // One shared destination, pushed onto the same NavigationStack that
            // already pushes JourneyMapView. A successful start pops back here.
            .navigationDestination(isPresented: $showingStore) {
                AvailableJourneysView()
            }
            .overlayPreferenceValue(KebabAnchorKey.self) { anchors in
                menuOverlay(anchors: anchors)
            }
            .overlay { confirmationOverlay }
    }

    @ViewBuilder
    private var content: some View {
        if cards.isEmpty {
            EmptyJourneysState(onStart: { showingStore = true })
        } else {
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(cards) { journey in
                        JourneyCard(
                            journey: journey,
                            hasActiveSibling: hasActiveSibling(of: journey),
                            isMenuOpen: openMenuID == journey.persistentModelID,
                            onToggleMenu: { toggleMenu(journey) },
                            onAction: { perform($0, on: journey) }
                        )
                    }
                }
                .padding(20)
            }
        }
    }

    // MARK: - Menu overlay (custom anchored dropdown, Design System §07)

    @ViewBuilder
    private func menuOverlay(anchors: [PersistentIdentifier: Anchor<CGRect>]) -> some View {
        GeometryReader { proxy in
            if let openID = openMenuID,
               let anchor = anchors[openID],
               let journey = cards.first(where: { $0.persistentModelID == openID }) {
                let rect = proxy[anchor]
                ZStack(alignment: .topLeading) {
                    // Outside-tap dismissal scrim (invisible, but hit-testable).
                    Color.clear
                        .contentShape(Rectangle())
                        .ignoresSafeArea()
                        .onTapGesture { openMenuID = nil }

                    KebabDropdown(
                        journey: journey,
                        hasActiveSibling: hasActiveSibling(of: journey),
                        onAction: { perform($0, on: journey) }
                    )
                    .frame(width: 190)
                    // §07 placement (Jeff's ruling): leading edge aligns to the
                    // kebab's leading edge, extending trailing, clamped to stay
                    // ≥12pt from the screen's trailing edge.
                    .offset(
                        x: min(rect.minX, proxy.size.width - 190 - 12),
                        y: rect.maxY + 6
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var confirmationOverlay: some View {
        if let journey = pendingPausedRestart {
            DimmedConfirm(
                title: "Restart \(journey.name)?",
                message: "This discards your current progress of \(DistanceFormatter.formattedMiles(journey.distanceAccumulated)) and starts over from zero. This can't be undone.",
                destructiveLabel: "Discard & Restart",
                destructiveIdentifier: "confirm.discardRestart",
                onCancel: { pendingPausedRestart = nil },
                onConfirm: {
                    let id = journey.persistentModelID
                    pendingPausedRestart = nil
                    Task { try? await ProgressStore.shared.restartPaused(id) }
                }
            )
        } else if let journey = pendingDelete {
            DimmedConfirm(
                title: "Delete \(journey.name)?",
                message: deleteMessage(for: journey),
                destructiveLabel: "Delete",
                destructiveIdentifier: "confirm.delete",
                onCancel: { pendingDelete = nil },
                onConfirm: {
                    let templateID = journey.template?.persistentModelID
                    pendingDelete = nil
                    guard let templateID else { return }
                    Task { try? await ProgressStore.shared.deleteJourney(templateID: templateID) }
                }
            )
        }
    }

    /// Body copy for the delete confirmation, differing only for completed
    /// (which has no live progress to discard — a completion record instead).
    private func deleteMessage(for journey: UserJourney) -> String {
        switch journey.status {
        case .completed:
            return "This deletes \(journey.name) and its completion record. The journey returns to Available Journeys to start fresh. This can't be undone."
        case .active, .paused:
            let progress = DistanceFormatter.formattedMiles(journey.distanceAccumulated)
            return "This deletes \(journey.name) and discards your progress of \(progress). The journey returns to Available Journeys to start fresh. This can't be undone."
        }
    }

    // MARK: - Actions

    private func toggleMenu(_ journey: UserJourney) {
        let id = journey.persistentModelID
        openMenuID = (openMenuID == id) ? nil : id
    }

    private func perform(_ action: LifecycleAction, on journey: UserJourney) {
        openMenuID = nil
        let id = journey.persistentModelID
        switch action {
        case .pause:
            Task { try? await ProgressStore.shared.pause(id) }
        case .resume:
            Task { try? await ProgressStore.shared.resume(id) }
        case .restart:
            switch journey.status {
            case .completed:
                // No confirmation — nothing is lost (Ruling: completion history
                // is preserved and a fresh run is created).
                Task { try? await ProgressStore.shared.restartCompleted(id) }
            case .paused:
                // Destructive — surface the dimmed confirmation first.
                pendingPausedRestart = journey
            case .active:
                break // restart is not offered for an active instance
            }
        case .delete:
            // Destructive on every status — surface the dimmed confirmation
            // first (KAN-13).
            pendingDelete = journey
        }
    }

    /// True if another instance of the same template is currently active — used
    /// to mute "Resume" defensively (precedence normally hides this case).
    private func hasActiveSibling(of journey: UserJourney) -> Bool {
        guard let templateID = journey.template?.persistentModelID else { return false }
        return instances.contains {
            $0.persistentModelID != journey.persistentModelID
                && $0.status == .active
                && $0.template?.persistentModelID == templateID
        }
    }
}

// MARK: - Lifecycle action kinds

enum LifecycleAction {
    case pause, resume, restart, delete
}

// MARK: - Anchor preference for the kebab dropdown

private struct KebabAnchorKey: PreferenceKey {
    static let defaultValue: [PersistentIdentifier: Anchor<CGRect>] = [:]
    static func reduce(
        value: inout [PersistentIdentifier: Anchor<CGRect>],
        nextValue: () -> [PersistentIdentifier: Anchor<CGRect>]
    ) {
        value.merge(nextValue()) { $1 }
    }
}

// MARK: - Card

private struct JourneyCard: View {
    let journey: UserJourney
    let hasActiveSibling: Bool
    let isMenuOpen: Bool
    let onToggleMenu: () -> Void
    let onAction: (LifecycleAction) -> Void

    private var stats: JourneyStats {
        JourneyStatsCalculator.stats(for: journey)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 10) {
                Text(journey.name)
                    .font(.system(size: 18, weight: .bold, design: .serif))
                    .foregroundStyle(Color(token: DesignToken.ink))
                    .padding(.trailing, 70) // clear the corner stamp
                    .accessibilityIdentifier("list.journeyName.\(journey.name)")

                // KAN-14/15: the mini stat ("X mi until [next]", or the
                // finish-date treatment) rides the progress bar's label row,
                // trailing, top-aligned with the total-miles text. Distance-
                // derived values are frozen for a paused run; a zero-waypoint
                // in-progress run has no mini stat.
                JourneyProgressBar(
                    progress: journey.progress,
                    accentColorToken: journey.theme.accentColorToken,
                    label: DistanceFormatter.progressLabel(
                        accumulated: journey.distanceAccumulated,
                        total: journey.totalDistance
                    ),
                    barIdentifier: "list.progressBar.\(journey.name)",
                    labelIdentifier: "list.distanceLabel.\(journey.name)",
                    trailingAccessory: AnyView(secondaryStat)
                )

                Text("Started \(StatFormatter.date(journey.startDate))")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(token: DesignToken.ink).opacity(0.7))
                    .accessibilityIdentifier("list.startDate.\(journey.name)")

                HStack(spacing: 10) {
                    NavigationLink {
                        JourneyMapView(journey: journey)
                    } label: {
                        // Opens the "journey view" (the tab renamed per Justin's
                        // 2026-07-12 two-surface ruling). Identifier kept stable.
                        StampButtonLabel(title: "View Journey", fillToken: journey.theme.accentColorToken)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("list.viewMapButton.\(journey.name)")

                    KebabButton(action: onToggleMenu)
                        .accessibilityIdentifier("list.kebab.\(journey.name)")
                        .anchorPreference(key: KebabAnchorKey.self, value: .bounds) {
                            [journey.persistentModelID: $0]
                        }
                }
            }
            .padding(16)
            .background(Color(token: DesignToken.card), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(Color(token: DesignToken.ink), lineWidth: 2))

            StatusStamp(status: journey.status)
                .padding(.top, 12)
                .padding(.trailing, 14)
                .accessibilityIdentifier("list.statusStamp.\(journey.name)")
        }
    }

    /// Right-aligned mini stat next to the start date. Completed → finish-date
    /// treatment; in-progress with a next waypoint → "X mi until [next]";
    /// otherwise (zero-waypoint or all reached) omitted.
    @ViewBuilder
    private var secondaryStat: some View {
        if journey.isCompleted {
            VStack(alignment: .trailing, spacing: 1) {
                Text(stats.completedAt.map(StatFormatter.date) ?? "date not recorded")
                    .font(.system(size: stats.completedAt == nil ? 11 : 14,
                                  weight: stats.completedAt == nil ? .semibold : .bold,
                                  design: .serif))
                    .foregroundStyle(Color(token: DesignToken.ink))
                    .multilineTextAlignment(.trailing)
                Text("Finished")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(token: DesignToken.ink).opacity(0.7))
            }
            .frame(maxWidth: 140, alignment: .trailing)
        } else if let next = stats.nextWaypoint {
            VStack(alignment: .trailing, spacing: 1) {
                Text(DistanceFormatter.formattedMiles(next.metersUntil))
                    .font(.system(size: 15, weight: .bold, design: .serif))
                    .foregroundStyle(Color(token: DesignToken.ink))
                    .accessibilityIdentifier("list.milesUntil.\(journey.name)")
                // Ruling 9: never truncate the waypoint name — wrap instead.
                Text("mi until \(next.name)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(token: DesignToken.ink).opacity(0.7))
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 140, alignment: .trailing)
        }
        // Zero-waypoint in-progress journeys: no mini stat.
    }
}

// MARK: - Status stamp (STRAIGHT — no rotation, per Design System v1.3 §07)

private struct StatusStamp: View {
    let status: JourneyStatus

    private var text: String {
        switch status {
        case .active: return "ACTIVE"
        case .paused: return "PAUSED"
        case .completed: return "COMPLETE"
        }
    }

    private var strokeToken: String {
        switch status {
        case .active: return DesignToken.accentPrimary
        case .paused: return DesignToken.ink
        case .completed: return DesignToken.reward
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            if status == .completed {
                EmberstoneGlyph(cell: 3)
            }
            Text(text)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .kerning(0.8)
        }
        .foregroundStyle(Color(token: DesignToken.ink))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(token: DesignToken.card))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(token: strokeToken), lineWidth: status == .completed ? 4 : 3)
                )
        }
        // The whole PAUSED stamp reads dormant (~60% opacity); no rotation and
        // no drop shadow on any status.
        .opacity(status == .paused ? 0.6 : 1)
    }
}

// MARK: - §05 pixel Emberstone glyph (strict grid, color blocks only)

private struct EmberstoneGlyph: View {
    // 6x6 grid. 1 = accent/reward, 2 = ink, 0 = transparent.
    private let grid: [[Int]] = [
        [0, 0, 1, 1, 0, 0],
        [0, 1, 1, 1, 1, 0],
        [1, 1, 1, 1, 1, 1],
        [2, 1, 1, 1, 1, 2],
        [0, 2, 1, 1, 2, 0],
        [0, 0, 2, 2, 0, 0]
    ]
    var cell: CGFloat = 3

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<grid.count, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<grid[row].count, id: \.self) { col in
                        cellColor(grid[row][col])
                            .frame(width: cell, height: cell)
                    }
                }
            }
        }
    }

    private func cellColor(_ value: Int) -> Color {
        switch value {
        case 1: return Color(token: DesignToken.reward)
        case 2: return Color(token: DesignToken.ink)
        default: return .clear
        }
    }
}

// MARK: - Buttons (§07 crisp stroke, no shadow)

private struct StampButtonLabel: View {
    let title: String
    let fillToken: String

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(Color(token: DesignToken.ink))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(token: fillToken))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(token: DesignToken.ink), lineWidth: 3))
            }
    }
}

private struct KebabButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color(token: DesignToken.ink))
                .frame(width: 32, height: 32)
                .background {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(token: DesignToken.card))
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(token: DesignToken.ink), lineWidth: 3))
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Kebab dropdown (custom anchored menu)

private struct KebabDropdown: View {
    let journey: UserJourney
    let hasActiveSibling: Bool
    let onAction: (LifecycleAction) -> Void

    private struct Row: Identifiable {
        let id = UUID()
        let action: LifecycleAction
        let label: String
        let systemImage: String
        let muted: Bool
        let identifier: String
        /// Ink for the lifecycle actions; `DesignToken.alert` for the
        /// destructive Delete row (the established destructive language — no new
        /// visuals). Delete is NEVER muted.
        var tintToken: String = DesignToken.ink
    }

    /// The destructive Delete row, present on EVERY status and placed LAST below
    /// the lifecycle actions (KAN-13). Icon + label tinted `DesignToken.alert`.
    private var deleteRow: Row {
        Row(action: .delete, label: "Delete", systemImage: "trash",
            muted: false, identifier: "list.action.delete.\(journey.name)",
            tintToken: DesignToken.alert)
    }

    private var rows: [Row] {
        switch journey.status {
        case .active:
            return [Row(action: .pause, label: "Pause", systemImage: "pause.fill",
                        muted: false, identifier: "list.action.pause.\(journey.name)"),
                    deleteRow]
        case .paused:
            // §07: an unavailable action renders its FULL normal row (icon,
            // label) at 40% opacity — never a swapped label/icon — so the
            // option's existence is never a surprise. `muted` drives the opacity
            // and disables the tap; the row content is identical either way.
            return [
                Row(action: .resume,
                    label: "Resume",
                    systemImage: "play.fill",
                    muted: hasActiveSibling,
                    identifier: "list.action.resume.\(journey.name)"),
                Row(action: .restart, label: "Restart", systemImage: "arrow.counterclockwise",
                    muted: false, identifier: "list.action.restart.\(journey.name)"),
                deleteRow,
            ]
        case .completed:
            return [Row(action: .restart, label: "Restart", systemImage: "arrow.counterclockwise",
                        muted: false, identifier: "list.action.restart.\(journey.name)"),
                    deleteRow]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                Button {
                    guard !row.muted else { return }
                    onAction(row.action)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: row.systemImage)
                        Text(row.label)
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(token: row.tintToken).opacity(row.muted ? 0.4 : 1))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(row.muted)
                .accessibilityIdentifier(row.identifier)

                if index < rows.count - 1 {
                    Rectangle()
                        .fill(Color(token: DesignToken.ink).opacity(0.15))
                        .frame(height: 1)
                }
            }
        }
        .background(Color(token: DesignToken.card), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(Color(token: DesignToken.ink), lineWidth: 3))
    }
}

// MARK: - Destructive confirmation (full dimmed overlay, §07)

/// One generalized dimmed-overlay confirmation, shared by the paused-restart
/// (KAN-10) and delete (KAN-13) flows. Only the title, body, and destructive
/// button's label + identifier vary — the layout, dim scrim, warning glyph,
/// Cancel-first ordering, and alert-filled destructive button are identical, so
/// the destructive language is defined in exactly one place. Cancel keeps the
/// stable `confirm.cancel` identifier for whichever overlay is up; the caller
/// supplies the destructive identifier (`confirm.discardRestart` for restart,
/// `confirm.delete` for delete) so existing drivers keep working unchanged.
private struct DimmedConfirm: View {
    let title: String
    let message: String
    let destructiveLabel: String
    let destructiveIdentifier: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        ZStack {
            Color(token: DesignToken.ink).opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color(token: DesignToken.alert))
                    Text(title)
                        .font(.system(size: 18, weight: .bold, design: .serif))
                        .foregroundStyle(Color(token: DesignToken.ink))
                }

                Text(message)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(token: DesignToken.ink))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button(action: onCancel) {
                        StampButtonLabel(title: "Cancel", fillToken: DesignToken.card)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("confirm.cancel")

                    Button(action: onConfirm) {
                        StampButtonLabel(title: destructiveLabel, fillToken: DesignToken.alert)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(destructiveIdentifier)
                }
            }
            .padding(20)
            .frame(maxWidth: 340, alignment: .leading)
            .background(Color(token: DesignToken.card), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .stroke(Color(token: DesignToken.ink), lineWidth: 3))
            .padding(24)
        }
    }
}

// MARK: - Empty state

private struct EmptyJourneysState: View {
    /// Opens Available Journeys — the same destination as the toolbar `+`, so an
    /// empty "Your Journeys" is never a dead end (KAN-11, Variant A's design).
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 16)

            // Minimal "Wren is waiting" stand-in — the real §04 faceted rig is
            // the map marker; this is just a quiet hint.
            Circle()
                .fill(Color(token: DesignToken.card))
                .overlay(Circle().stroke(Color(token: DesignToken.ink), lineWidth: 2))
                .frame(width: 34, height: 34)

            Text("No journeys yet")
                .font(.system(size: 18, weight: .bold, design: .serif))
                .foregroundStyle(Color(token: DesignToken.ink).opacity(0.8))
                .accessibilityIdentifier("list.emptyState")
            Text("Wren is ready when you are.")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(token: DesignToken.ink).opacity(0.5))

            // Primary CTA driving the shared store destination (§07 button —
            // radius 12, 3pt ink stroke, accent/primary fill, no shadow).
            Button(action: onStart) {
                StampButtonLabel(title: "Start a Journey", fillToken: DesignToken.accentPrimary)
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
            .accessibilityIdentifier("list.emptyStateCTA")

            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(token: DesignToken.parchment))
    }
}
