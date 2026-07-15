//
//  JourneyCharacter.swift
//  JourneyTracker
//
//  The ONE seam for the wayfarer's name (KAN-33 Ruling 5). There is no Character
//  model or selection feature yet (App Concept doc future-proofing row: "Decided,
//  not built"), and "Wren" is the shipped name in the KAN-7 completion banner.
//  Every place that names the character — the completion banner AND the milestone
//  notifications' `{character}` placeholder — reads from HERE, so when character
//  selection ships, both swap to the selected name in this single spot and can
//  never diverge (Ruling 10).
//
//  NOT named `Character`: that shadows Swift's stdlib `Character`, exactly the
//  kind of built-in-type collision the project bars for `Task`.
//
//  `nonisolated` (opting out of the project's MainActor default isolation) so the
//  name resolves on the ProgressStore actor's context while building notification
//  copy — the same off-main path the content provider and factory run on.
//

import Foundation

nonisolated enum JourneyCharacter {

    /// The current wayfarer's display name. A single constant today; the seam a
    /// future character-selection feature replaces with the chosen name.
    static let currentName = "Wren"
}
