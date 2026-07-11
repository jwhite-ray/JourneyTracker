//
//  JourneyStatus.swift
//  JourneyTracker
//
//  The lifecycle state of one UserJourney instance (KAN-10). Replaces the old
//  `isActive`/`isCompleted` booleans on the shipped combined `Journey` model.
//
//  Stored on UserJourney via its raw String (RawRepresentable + a default) so
//  the SwiftData store stays CloudKit-compatible — exactly like JourneyType.
//
//  Premium is deliberately NOT a case here: it is a catalog attribute on
//  JourneyTemplate. When purchases ship, this enum must not need a new case.
//

import Foundation

enum JourneyStatus: String, Codable, CaseIterable {
    /// Accruing distance; at most one per template (a code invariant enforced
    /// in ProgressStore, since CloudKit forbids unique constraints).
    case active
    /// Frozen; the UI word is "Paused". Does not accrue, so it never
    /// auto-completes.
    case paused
    /// Reached 100%; preserved as history and can be restarted into a fresh
    /// active instance.
    case completed
}
