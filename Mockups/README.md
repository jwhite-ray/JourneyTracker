# Mockups

Jeff (design) writes 2–3 SwiftUI Preview variants here when a feature needs new or changed UI. They exist to be looked at in an Xcode Preview and then thrown away.

**This folder must be excluded from the app target.** Add it to the project as a folder reference, not a group with target membership — nothing in here ever ships.

Dan deletes the rejected variants once the user picks a direction, and removes the chosen variant's file too after hardening it into a real view. This folder should be empty (apart from this README) between features.
