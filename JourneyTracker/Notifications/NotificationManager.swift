//
//  NotificationManager.swift
//  JourneyTracker
//
//  The single authority for local notifications (KAN-32, Phase 0), mirroring the
//  HealthKitManager grain: one @Observable @MainActor final class with a
//  `static let shared`, and the ONLY type in the app that imports
//  UserNotifications / touches UNUserNotificationCenter — exactly as
//  HealthKitManager is the only type that touches HealthKit and DistanceFormatter
//  / StatFormatter are the only formatting authorities.
//
//  It owns: category/identifier registration, honest observable 3-state
//  authorization, the contextual permission request (after the user's FIRST
//  journey start — never cold at launch), and the fire/schedule primitive.
//
//  Local-only. No push, no APNs, no aps-environment entitlement — everything is
//  UNUserNotificationCenter local scheduling (App Concept doc, Notifications v1
//  Phase 0). Phase 0 fires nothing to the user: `fireDebugSample()` is the only
//  firing, dev-only, through the real primitive so the plumbing is verifiable
//  without walking.
//

import Foundation
import UserNotifications

@Observable
@MainActor
final class NotificationManager {

    /// The single shared instance — every caller (launch, the start-journey UI,
    /// the future ProgressUpdater fire in Phase 1) funnels through this one.
    static let shared = NotificationManager()

    /// Honest, coarse 3-state authorization for the UI. Provisional/ephemeral
    /// (both can post) fold into `.authorized` — the fine-grained "can this
    /// status post?" decision lives in `enqueue`, off-main, against the LIVE
    /// settings, not this cached property.
    enum Authorization: String {
        case notDetermined
        case denied
        case authorized
    }

    /// Observed by DebugView. Refreshed at launch, after the contextual request,
    /// and via DebugView's manual refresh — there is no foreground/scenePhase
    /// hook yet, so this can read stale after a Settings.app change until the
    /// next refresh. `enqueue`'s LIVE settings read is unaffected (Ruling 3).
    private(set) var authorization: Authorization = .notDetermined

    private init() {}

    // MARK: - Launch wiring (no prompt)

    /// Registers the milestone categories once at launch. `setNotificationCategories`
    /// does NOT prompt — it only declares the category ids Phase 1's requests
    /// reference (and the home for future actions/grouping).
    func registerCategories() {
        let waypointReached = UNNotificationCategory(
            identifier: NotificationSchema.CategoryID.waypointReached,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        let journeyComplete = UNNotificationCategory(
            identifier: NotificationSchema.CategoryID.journeyComplete,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current()
            .setNotificationCategories([waypointReached, journeyComplete])
    }

    /// Reads the current system authorization into the observable property. Called
    /// at launch and on foreground — never prompts.
    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorization = Self.coarseAuthorization(settings.authorizationStatus)
    }

    // MARK: - Contextual permission (KAN-32 Ruling 1)

    /// Requests authorization immediately after the user's FIRST successful
    /// journey start — the ONLY place the app ever requests it. Self-gated on
    /// `.notDetermined`: because the app requests nowhere else, the first
    /// successful start is the only start where status is still `.notDetermined`;
    /// every later start (and every restart, which needs a pre-existing instance)
    /// sees a determined status and no-ops. This is how "first journey ever" is
    /// determined with NO model change, and it's self-correcting — deny once and
    /// it never re-prompts.
    ///
    /// Options are the standard `[.alert, .sound, .badge]` (not provisional/quiet)
    /// — a real contextual prompt at a moment the user just expressed intent.
    func requestAuthorizationOnFirstJourney() async {
        guard authorization == .notDetermined else { return }
        do {
            _ = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            // A failed request leaves the status for the refresh below to read
            // honestly; nothing is asserted from the (unused) granted bool.
        }
        // Re-read the real status rather than trusting the returned bool, so the
        // observable property reflects what the system actually recorded.
        await refreshAuthorizationStatus()
    }

    // MARK: - Fire primitive (KAN-32 Rulings 2 & 3)

    /// Enqueues milestone notifications. SYNCHRONOUS, non-blocking, and
    /// `nonisolated` — callable straight from the ProgressStore @ModelActor in
    /// Phase 1 without hopping to the main actor or awaiting the center inside the
    /// delta transaction (App Concept doc, KAN-32 Ruling 2). It returns
    /// immediately and hands the work to a detached Task.
    ///
    /// Only Sendable values cross in: `[MilestoneNotificationRequest]`. The
    /// detached task reads the LIVE system authorization off-main (not the cached
    /// `@MainActor` property — correct off-main, no staleness) and, unless the
    /// status can post, silently returns. Nothing is persisted for later: a
    /// milestone requested before authorization resolves is DROPPED, never queued,
    /// so a late grant never replays a backlog of past-tense nudges (KAN-32
    /// Ruling 3, mirroring KAN-14's forward-only crossings). Denied/undetermined
    /// is a first-class, non-crashing no-op.
    nonisolated func enqueue(_ requests: [MilestoneNotificationRequest]) {
        guard !requests.isEmpty else { return }
        Self.deliver(requests, trigger: nil)
    }

    /// The detached add-loop shared by the real `enqueue` path and the dev
    /// trigger. `trigger` is `nil` for `enqueue` (immediate delivery, which
    /// Phase 1 depends on) and a short time-interval trigger only for the
    /// dev sample (KAN-32 Ruling on the QA finding). Reads the LIVE system
    /// settings off-main, gates on `canPost`, and builds one request per item.
    private nonisolated static func deliver(
        _ requests: [MilestoneNotificationRequest],
        trigger: UNNotificationTrigger?
    ) {
        Task.detached {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard Self.canPost(settings.authorizationStatus) else { return }

            for request in requests {
                let content = UNMutableNotificationContent()
                content.title = request.title
                content.body = request.body
                content.sound = .default
                content.threadIdentifier = request.threadIdentifier
                content.categoryIdentifier = request.categoryIdentifier
                content.userInfo = request.userInfo

                // A nil trigger delivers immediately. The deterministic
                // identifier makes a re-fire REPLACE rather than duplicate.
                let notification = UNNotificationRequest(
                    identifier: request.requestIdentifier,
                    content: content,
                    trigger: trigger
                )
                do {
                    try await center.add(notification)
                } catch {
                    // A single add failure must not abort the batch or crash;
                    // Phase 1 owns any user-facing surfacing.
                }
            }
        }
    }

    // MARK: - Dev trigger (Phase 0 only)

    /// Fires a single sample milestone so the plumbing is verifiable without
    /// walking. Dev-only, clearly-marked placeholder copy — NO real milestone
    /// copy ships in Phase 0. Random UUIDs keep it self-contained (it deep-links
    /// nowhere in Phase 0). If not authorized, `deliver` silently drops it
    /// (Ruling 3) — no crash.
    func fireDebugSample() {
        let sample = MilestoneNotificationRequest(
            hook: .waypointReached,
            userJourneyID: UUID(),
            templateID: UUID(),
            waypointID: UUID(),
            title: "[DEV] Sample milestone",
            body: "[DEV] Phase 0 notification plumbing — placeholder copy, not real milestone text."
        )
        // DEV-ONLY: a short time-interval trigger (not the real `enqueue`'s
        // immediate `trigger: nil`) so the banner is human-verifiable — Phase 0
        // has no `willPresent` delegate, so an immediate fire is suppressed
        // while foreground; this 5s delay lets the tester background the app and
        // actually SEE it (Jake's KAN-32 QA-finding ruling). The real `enqueue`
        // path is untouched and keeps `trigger: nil` for Phase 1.
        Self.deliver(
            [sample],
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        )
    }

    // MARK: - Status mapping

    /// Fold the system status into the coarse 3-state property. Provisional and
    /// ephemeral can post, so they read as `.authorized` for the UI.
    private nonisolated static func coarseAuthorization(_ status: UNAuthorizationStatus) -> Authorization {
        switch status {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized, .provisional, .ephemeral: return .authorized
        @unknown default: return .notDetermined
        }
    }

    /// Whether a notification may actually be posted under `status` (KAN-32
    /// Ruling 3). Read off-main against the LIVE settings before adding anything.
    private nonisolated static func canPost(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral: return true
        case .notDetermined, .denied: return false
        @unknown default: return false
        }
    }
}
