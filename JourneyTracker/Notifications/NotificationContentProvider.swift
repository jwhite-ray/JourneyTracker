//
//  NotificationContentProvider.swift
//  JourneyTracker
//
//  The SINGLE authority for milestone-notification COPY (KAN-33 Ruling 4) —
//  mirroring DistanceFormatter/StatFormatter as the single authority for numbers.
//  It owns two jobs and nothing else:
//
//   1. Reading the bundled per-journey CSV sheets (Notifications/Content/*.csv),
//      with a quoted-field-aware parser (bodies contain commas), and
//   2. Resolving a matched row's `{placeholder}` tokens into finished title/body
//      strings — every `{miles_*}`/`{total_miles}` through DistanceFormatter, so
//      no literal mileage and no hand-formatting ever enters notification copy.
//
//  The CSVs live INSIDE the app target under `JourneyTracker/Notifications/Content/`,
//  where the file-system-synchronized `JourneyTracker` group bundles them as
//  resources automatically (Ruling 4) — one canonical copy, loaded from
//  `Bundle.main` at fire time, no build-time codegen, no docs↔bundle drift.
//
//  Journey→sheet lookup is NAME-KEYED via a static catalog mirroring
//  MapAuthoringCatalog (which keys map authoring by `JourneyTemplate.name`): the
//  per-journey slug is curated here, not derived from the name, so no model/seed
//  field is added. A journey with no sheet, or a row that doesn't match, resolves
//  to `nil` — a silent no-op (no notification), never a crash.
//
//  `nonisolated` (opting out of the project's MainActor default isolation) so the
//  provider runs on the ProgressStore actor's own context during `apply` — pure,
//  in-memory CPU (a tiny CSV parse), no `await`, no shared mutable state.
//

import Foundation

nonisolated enum NotificationContentProvider {

    /// The two hooks Phase 1 fires. The `percent_*` rows authored in the sheets
    /// are DORMANT (KAN-37) and never match here — the parser ignores every hook
    /// but these two (Ruling 4).
    enum Hook: String {
        case waypointReached = "waypoint_reached"
        case journeyComplete = "journey_complete"
    }

    /// Everything a template's copy can reference, in RAW form: names as strings,
    /// distances as METERS (formatted here via DistanceFormatter — the caller
    /// never divides). Optional values that are absent leave their `{token}`
    /// unresolved, which degrades gracefully (see `fill`).
    struct FillContext {
        var journeyName: String
        var waypointName: String?
        var nextWaypointName: String?
        var milesWalkedMeters: Double?
        var milesToNextMeters: Double?
        var milesRemainingMeters: Double?
        var totalMilesMeters: Double?
    }

    /// Finished, placeholder-resolved copy ready to hand to the request assembly.
    struct ResolvedContent {
        let title: String
        let body: String
    }

    // MARK: - Name-keyed sheet catalog (the seam, mirroring MapAuthoringCatalog)

    /// Curated `JourneyTemplate.name` → CSV slug. The slug is authored, NOT a pure
    /// derivation of the name, so it lives here rather than being computed. A
    /// journey absent from this map has no sheet and notifies nothing.
    private static let slugByJourneyName: [String: String] = [
        "First Journey": "first-journey",
        "Road to The Windrise Peaks": "windrise-peaks",
        "Around the World": "around-the-world",
    ]

    // MARK: - Entry point

    /// Resolves finished copy for one milestone, or `nil` when the journey has no
    /// sheet, the hook has no matching row, or the sheet can't be read. Waypoint
    /// rows match on `Waypoint.order` (the structural key the crossing snapshots);
    /// `journeyComplete` takes the sheet's single `journey_complete` row.
    static func resolvedContent(
        journeyName: String,
        hook: Hook,
        waypointOrder: Int?,
        context: FillContext
    ) -> ResolvedContent? {
        guard let slug = slugByJourneyName[journeyName],
              let rows = loadRows(slug: slug),
              let row = matchRow(in: rows, hook: hook, waypointOrder: waypointOrder)
        else { return nil }

        let values = resolvableValues(context)
        let title = fill(row.titleTemplate, values: values)
        let body = fill(row.bodyTemplate, values: values)
        // A row that resolved to empty copy (e.g. every clause dropped) is treated
        // as a no-op rather than firing a blank banner.
        guard !title.isEmpty || !body.isEmpty else { return nil }
        return ResolvedContent(title: title, body: body)
    }

    // MARK: - Row matching

    /// The two template columns a matched row contributes.
    private struct SheetRow {
        let titleTemplate: String
        let bodyTemplate: String
    }

    /// Column order in every sheet: hook, order, waypoint, cumulative_miles,
    /// title_template, body_template, artwork_asset, notes.
    private enum Column {
        static let hook = 0
        static let order = 1
        static let titleTemplate = 4
        static let bodyTemplate = 5
        static let minCount = 6 // title/body must be present
    }

    private static func matchRow(
        in rows: [[String]],
        hook: Hook,
        waypointOrder: Int?
    ) -> SheetRow? {
        // Skip the header row; ignore any row whose hook isn't one of the two we
        // fire (the dormant percent_* rows fall out here).
        for row in rows.dropFirst() where row.count >= Column.minCount {
            guard row[Column.hook].trimmed == hook.rawValue else { continue }
            if hook == .waypointReached {
                guard let waypointOrder,
                      Int(row[Column.order].trimmed) == waypointOrder else { continue }
            }
            return SheetRow(
                titleTemplate: row[Column.titleTemplate],
                bodyTemplate: row[Column.bodyTemplate]
            )
        }
        return nil
    }

    // MARK: - Placeholder resolution

    /// The token→value map for the tokens we CAN resolve. `{character}` (the
    /// Ruling-5 seam) and `{journey}` are always present; the rest are included
    /// only when their source value exists — an absent one leaves its token in the
    /// string for `fill` to prune (graceful degrade, never a raw "{token}").
    private static func resolvableValues(_ c: FillContext) -> [String: String] {
        var values: [String: String] = [
            "{character}": JourneyCharacter.currentName,
            "{journey}": c.journeyName,
        ]
        if let waypointName = c.waypointName { values["{waypoint}"] = waypointName }
        if let nextWaypointName = c.nextWaypointName { values["{next_waypoint}"] = nextWaypointName }
        if let meters = c.milesWalkedMeters { values["{miles_walked}"] = DistanceFormatter.formattedMiles(meters) }
        if let meters = c.milesToNextMeters { values["{miles_to_next}"] = DistanceFormatter.formattedMiles(meters) }
        if let meters = c.milesRemainingMeters { values["{miles_remaining}"] = DistanceFormatter.formattedMiles(meters) }
        if let meters = c.totalMilesMeters { values["{total_miles}"] = DistanceFormatter.formattedMiles(meters) }
        return values
    }

    /// Substitutes every resolvable token, then DROPS any remaining sentence that
    /// still carries an unresolved `{token}` (Ruling on graceful degradation: omit
    /// the clause, never crash or print a raw token). Sentences are split on ". "
    /// — safe here because formatted distances ("3.2 mi", "1,540 mi") never contain
    /// a period-then-space.
    static func fill(_ template: String, values: [String: String]) -> String {
        var result = template
        for (token, value) in values {
            result = result.replacingOccurrences(of: token, with: value)
        }
        guard result.contains("{") else {
            return result.trimmingCharacters(in: .whitespaces)
        }
        // Strip each piece's own trailing period, keep only clause with no residual
        // token, then re-punctuate as full sentences.
        let kept = result
            .components(separatedBy: ". ")
            .map { $0.trimmingCharacters(in: .whitespaces).trimmingTrailingPeriod }
            .filter { !$0.isEmpty && !$0.contains("{") }
        guard !kept.isEmpty else { return "" }
        return kept.joined(separator: ". ") + "."
    }

    // MARK: - CSV loading + parsing

    /// Loads and parses a sheet from the app bundle, or `nil` if it isn't present
    /// / can't be read as UTF-8. The synchronized `JourneyTracker` group bundles
    /// each CSV flat under `Bundle.main`, so a bare slug resolves it.
    private static func loadRows(slug: String) -> [[String]]? {
        guard let url = Bundle.main.url(forResource: slug, withExtension: "csv"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        return parse(text)
    }

    /// A minimal RFC-4180-style CSV parser: comma-separated fields, `"`-quoted
    /// fields may contain commas and `""`-escaped quotes, records end on newline.
    /// Enough for these hand-authored sheets (no embedded newlines in fields).
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var record: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.makeIterator()
        var pending: Character? = nil

        func nextChar() -> Character? {
            if let p = pending { pending = nil; return p }
            return iterator.next()
        }

        while let c = nextChar() {
            if inQuotes {
                if c == "\"" {
                    if let n = nextChar() {
                        if n == "\"" { field.append("\"") } // escaped quote
                        else { inQuotes = false; pending = n } // closing quote, reprocess n
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(c)
                }
            } else {
                switch c {
                case "\"": inQuotes = true
                case ",": record.append(field); field = ""
                case "\r": break // tolerate CRLF
                case "\n":
                    record.append(field); field = ""
                    rows.append(record); record = []
                default: field.append(c)
                }
            }
        }
        // Flush a trailing field/record (file without a final newline).
        if !field.isEmpty || !record.isEmpty {
            record.append(field)
            rows.append(record)
        }
        // Drop blank lines.
        return rows.filter { !($0.count == 1 && $0[0].trimmed.isEmpty) }
    }
}

// MARK: - Small string helpers (file-private to the provider)

private extension String {
    // `nonisolated` (the provider that calls these runs off the main actor).
    nonisolated var trimmed: String { trimmingCharacters(in: .whitespaces) }

    /// Drops a single trailing period so sentence pieces can be re-punctuated
    /// uniformly by `fill`.
    nonisolated var trimmingTrailingPeriod: String {
        hasSuffix(".") ? String(dropLast()) : self
    }
}
