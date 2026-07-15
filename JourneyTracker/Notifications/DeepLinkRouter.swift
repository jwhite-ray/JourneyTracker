//
//  DeepLinkRouter.swift
//  JourneyTracker
//
//  The navigation seam a notification tap needs (KAN-33 Ruling 8). The
//  NavigationLink-only stack has no way for an external event to drive it, so
//  this small `@MainActor @Observable` router holds the two pieces of navigation
//  state RootView + JourneyListView bind to:
//   • `selectedTab` — so a tap can bring the Journeys tab forward, and
//   • `path` — the path-based NavigationStack's route, so a tap can push the
//     resolved journey's JourneyMapView.
//
//  `handle(userInfo:)` parses the schema-v1 payload and resolves the target
//  instance (KAN-32 UserInfo schema): `userJourneyID` → UserJourney by `id`;
//  falling back to `templateID` → that template's highest-precedence instance
//  (active > most-recent paused > most-recent completed — KAN-10 Ruling 1); and,
//  if neither resolves, simply selecting the Journeys tab root (never a crash).
//
//  `waypointID` is carried in the payload but scroll-to-waypoint is DEFERRED
//  (Ruling 8): the in-tab journey view has no per-waypoint scroll API yet.
//
//  Resolution reads the container's `mainContext` — the same context the list's
//  @Query observes — never the ProgressStore write context.
//

import Foundation
import SwiftData

@MainActor
@Observable
final class DeepLinkRouter {

    /// The app's two tabs, so a tap can select Journeys regardless of where the
    /// user was. Mirrors RootView's TabView selection.
    enum Tab: Hashable {
        case journeys
        case debug
    }

    /// The currently-selected tab (bound by RootView's TabView).
    var selectedTab: Tab = .journeys

    /// The Journeys NavigationStack path (bound by JourneyListView). A single-
    /// element path pushes exactly that journey's map; empty is the list root.
    var path: [UserJourney] = []

    /// The context notification-tap resolution reads. Defaults to the shared
    /// container's main context (the one the list's @Query uses).
    private let context: ModelContext

    /// `context` defaults to the shared container's main context (the one the
    /// list's @Query uses); resolved in the body because a MainActor property
    /// can't be a nonisolated default-argument expression.
    init(context: ModelContext? = nil) {
        self.context = context ?? SharedModelContainer.shared.mainContext
    }

    // MARK: - Tap handling

    /// Resolves a schema-v1 notification payload to a journey and routes to it.
    /// Malformed or unresolvable payloads fall back to the Journeys tab root
    /// rather than throwing.
    func handle(userInfo: [AnyHashable: Any]) {
        // Bring the Journeys tab forward for every milestone tap (even a fallback
        // that resolves no specific instance lands somewhere sensible).
        selectedTab = .journeys

        guard let journey = resolveJourney(from: userInfo) else {
            // Unresolvable → Journeys tab root, no push.
            path = []
            return
        }
        openJourney(journey)
    }

    /// Pushes a specific journey's map (replacing any existing route so a tap
    /// never stacks maps).
    func openJourney(_ journey: UserJourney) {
        selectedTab = .journeys
        path = [journey]
    }

    // MARK: - Resolution (KAN-32 schema v1 → instance)

    private func resolveJourney(from userInfo: [AnyHashable: Any]) -> UserJourney? {
        // Guard the schema version; an unknown shape resolves nothing.
        guard (userInfo[NotificationSchema.UserInfoKey.schemaVersion] as? Int)
                == NotificationSchema.schemaVersion else { return nil }

        let all = (try? context.fetch(FetchDescriptor<UserJourney>())) ?? []

        // 1) Exact instance by userJourneyID.
        if let idString = userInfo[NotificationSchema.UserInfoKey.userJourneyID] as? String,
           let id = UUID(uuidString: idString),
           let exact = all.first(where: { $0.id == id }) {
            return exact
        }

        // 2) Fallback: the template's highest-precedence instance (the instance was
        //    deleted, but the template still resolves the run to open).
        if let templateIDString = userInfo[NotificationSchema.UserInfoKey.templateID] as? String,
           let templateID = UUID(uuidString: templateIDString) {
            let ofTemplate = all.filter { $0.template?.id == templateID }
            if let active = ofTemplate.first(where: { $0.status == .active }) {
                return active
            }
            if let paused = ofTemplate.filter({ $0.status == .paused })
                .max(by: { $0.startDate < $1.startDate }) {
                return paused
            }
            return ofTemplate.filter { $0.status == .completed }
                .max(by: { $0.startDate < $1.startDate })
        }

        return nil
    }
}
