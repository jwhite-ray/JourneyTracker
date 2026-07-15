//
//  MilestoneNotificationRequest.swift
//  JourneyTracker
//
//  The ONE place a milestone notification's on-the-wire shape is assembled
//  (KAN-32, Phase 0). A `MilestoneNotificationRequest` is a Sendable value type
//  carrying only the fields Phase 1 supplies — the hook, the stable UUIDs, and
//  the already-resolved title/body — and derives every identifier and the
//  `userInfo` dictionary from them. This mirrors "formatting happens in exactly
//  one place": Phase 1 never hand-builds an identifier or a userInfo, and no
//  other type re-derives the notification's shape.
//
//  This file does NOT import UserNotifications — it is pure value-type assembly.
//  `NotificationManager` is the only type that touches UNUserNotificationCenter;
//  it consumes these values to build the actual UNNotificationRequest.
//
//  Only Sendable values cross the ProgressStore-actor boundary (App Concept doc,
//  KAN-32 Ruling 2): UUIDs and resolved Strings — never a @Model, never a
//  PersistentIdentifier (KAN-32 Ruling 5: PersistentIdentifier isn't
//  plist/string-friendly and isn't stable across migrations/devices).
//

import Foundation

/// Constants and identifier builders shared by the request assembly and the
/// manager — the single source of truth for the notification namespace, the
/// userInfo schema-v1 keys, and the deterministic identifier scheme (KAN-32
/// Ruling 6). Kept as one enum so the on-the-wire contract lives in one place.
///
/// `nonisolated` because this contract is assembled off the main actor — inside
/// `NotificationManager.enqueue`'s detached task and, in Phase 1, on the
/// ProgressStore @ModelActor. The project defaults new types to MainActor
/// isolation (`SWIFT_DEFAULT_ACTOR_ISOLATION`), which this value type opts out of.
nonisolated enum NotificationSchema {

    /// userInfo payload-shape version (KAN-32 Ruling 5), so Phase 2+ can evolve
    /// the deep-link schema without breaking a tap handler reading an old push.
    static let schemaVersion = 1

    /// Category identifiers (`UNNotificationCategory`) — one per milestone type,
    /// the home for Phase 1+ actions/grouping. Registered once at launch, no
    /// prompt. Under the app-owned `com.journeytracker.*` namespace (no
    /// real-world IP).
    enum CategoryID {
        static let waypointReached = "com.journeytracker.category.waypointReached"
        static let journeyComplete = "com.journeytracker.category.journeyComplete"
    }

    /// userInfo dictionary keys (schema v1). Stable strings — the deep-link
    /// contract Phase 1's tap handler reads.
    enum UserInfoKey {
        static let schemaVersion = "schemaVersion"
        static let hook = "hook"
        static let userJourneyID = "userJourneyID"
        static let templateID = "templateID"
        static let waypointID = "waypointID"
    }

    // MARK: - Deterministic identifier builders (KAN-32 Ruling 6)

    /// Request identifier for a waypoint crossing — deterministic from the run +
    /// waypoint, so re-adding the same milestone REPLACES rather than duplicates
    /// (the UNNotificationRequest idempotency/dedup key).
    static func waypointRequestIdentifier(userJourneyID: UUID, waypointID: UUID) -> String {
        "waypoint.\(userJourneyID.uuidString).\(waypointID.uuidString)"
    }

    /// Request identifier for a journey completion — one per run.
    static func completeRequestIdentifier(userJourneyID: UUID) -> String {
        "complete.\(userJourneyID.uuidString)"
    }

    /// Thread identifier — per run, so all of a journey's milestones stack
    /// together in Notification Center. This is what makes Phase 1's batching
    /// (several crossings from one delta) a pure content decision.
    static func threadIdentifier(userJourneyID: UUID) -> String {
        "journey.\(userJourneyID.uuidString)"
    }
}

/// One milestone notification, described by its Sendable fields. Phase 1 fills
/// `title`/`body` (with placeholders already resolved via DistanceFormatter/
/// StatFormatter, KAN-32 Ruling 4); Phase 0 accepted them as plain strings. The
/// request/thread/category identifiers and the userInfo are DERIVED here.
///
/// `nonisolated` (opting out of the project's MainActor default isolation) so the
/// value and its derived shape can be built and read off the main actor — the
/// whole point of a Sendable request that crosses the ProgressStore-actor
/// boundary in Phase 1.
nonisolated struct MilestoneNotificationRequest: Sendable {

    /// Which milestone fired — a sum type that carries the waypoint identity ONLY
    /// where it exists (KAN-33 Ruling 1). This makes the two invalid states the
    /// old `hook`/`waypointID?` pair allowed (`.waypointReached` with no id,
    /// `.journeyComplete` with a stray id) unrepresentable, so every derivation
    /// below has no nil-fallback branch and no "complete-with-waypoint" leak.
    enum Milestone: Sendable {
        case waypointReached(waypointID: UUID)
        case journeyComplete
    }

    let milestone: Milestone
    /// The specific run to deep-link to (stable UUID, never PersistentIdentifier).
    let userJourneyID: UUID
    /// The catalog template — lets a tap still resolve/route if the instance was
    /// deleted (KAN-32 Ruling 5).
    let templateID: UUID
    /// Already-resolved copy (Phase 1 fills placeholders); Phase 0 shipped none.
    let title: String
    let body: String

    // MARK: - Derived on-the-wire shape (the single assembly point)

    /// The `hook` string that matches the CSV `hook` column and the `userInfo.hook`
    /// value the tap handler routes on (KAN-32 schema v1, unchanged).
    private var hookRawValue: String {
        switch milestone {
        case .waypointReached: return "waypoint_reached"
        case .journeyComplete: return "journey_complete"
        }
    }

    /// The idempotency/dedup key. A re-applied delta that re-adds the same
    /// milestone replaces the pending/delivered notification rather than
    /// duplicating it (combined with KAN-14's crossing idempotency guard, a
    /// re-applied delta never double-notifies).
    var requestIdentifier: String {
        switch milestone {
        case .waypointReached(let waypointID):
            return NotificationSchema.waypointRequestIdentifier(
                userJourneyID: userJourneyID, waypointID: waypointID)
        case .journeyComplete:
            return NotificationSchema.completeRequestIdentifier(userJourneyID: userJourneyID)
        }
    }

    /// Per-run OS grouping key.
    var threadIdentifier: String {
        NotificationSchema.threadIdentifier(userJourneyID: userJourneyID)
    }

    /// The category this milestone belongs to (registered at launch).
    var categoryIdentifier: String {
        switch milestone {
        case .waypointReached: return NotificationSchema.CategoryID.waypointReached
        case .journeyComplete: return NotificationSchema.CategoryID.journeyComplete
        }
    }

    /// The schema-v1 deep-link payload. UUIDs are stringified; `waypointID` is
    /// present only for `.waypointReached` — the schema keys are IDENTICAL to
    /// KAN-32 (Ruling 1 keeps the on-the-wire contract stable).
    var userInfo: [String: Any] {
        var info: [String: Any] = [
            NotificationSchema.UserInfoKey.schemaVersion: NotificationSchema.schemaVersion,
            NotificationSchema.UserInfoKey.hook: hookRawValue,
            NotificationSchema.UserInfoKey.userJourneyID: userJourneyID.uuidString,
            NotificationSchema.UserInfoKey.templateID: templateID.uuidString,
        ]
        if case .waypointReached(let waypointID) = milestone {
            info[NotificationSchema.UserInfoKey.waypointID] = waypointID.uuidString
        }
        return info
    }
}
