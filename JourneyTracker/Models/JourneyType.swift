//
//  JourneyType.swift
//  JourneyTracker
//
//  The kind of route a journey represents. Stored as a raw String so the
//  SwiftData store stays CloudKit-compatible (RawRepresentable + default).
//

import Foundation

enum JourneyType: String, Codable, CaseIterable {
    case fantasy
    case realWorld
}
