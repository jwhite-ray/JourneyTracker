# JourneyTracker: App Concept & Architecture

**Status:** living document · owned by Jake (lead engineer)

## What the app is

JourneyTracker turns everyday walking into visible progress along a chosen journey. The user picks a route — either a real-world distance (a marathon, "around the world," a specific trail) or an illustrated fantasy path (the road to Ember Spire, and eventually more) — and their real distance, read from Apple Health, moves a marker along that route over time. No app needs to be open for progress to accumulate; it happens passively in the background, on iPhone and eventually Apple Watch.

## Document precedence

Three documents govern this project. When they disagree, this order settles it:

| Document | Governs | Owner |
|---|---|---|
| `docs/JourneyTracker_App_Concept.md` (this doc) | Concepts, architecture, data model, behavior, naming | Jake |
| `docs/DESIGN_SYSTEM.md` | Visual style only — color, type, shape, layout, character rig | Jeff |
| `CLAUDE.md` | Team workflow, roles, Jira process | main session |

**The design system passes style, not concepts.** If it appears to specify a progress formula, a data model, a unit, or a behavior, that text is out of scope and this document wins. Conversely, no one — including this document — overrides the design system on what a thing *looks* like. If a conflict appears, the fix is to amend the wrong doc, not to quietly pick a side in code.

## How to use this document

This isn't a spec to gold-plate before writing code — it's a checklist of *cheap decisions to make correctly now*, so that adding real features later doesn't require rebuilding what already exists. Everything below is meant to cost almost nothing today and save a rewrite later.

**Read the Status column.** Most decisions below are *Decided, not built*. The code today is a small prototype and does not yet contain most of this. Do not assume a system exists because it's described here — check the code.

## The one assumption that matters most

Distance should always be calculated as **cumulative total since the journey's start date**, not "today's distance" or "this week's distance." A journey spans weeks or months; the progress metric needs to be anchored to a fixed start point and summed forward from there. Getting this wrong is the hardest thing to unwind later, because it touches the HealthKit query shape, the SwiftData model, and the background-delivery logic all at once. Build this correctly from day one.

**With multiple simultaneous journeys allowed**, the cleanest way to implement this is a *delta-based* update rather than querying HealthKit separately per journey: track one "last processed distance" anchor, and each time new HealthKit data arrives (one-time query or background observer), calculate the delta since that anchor and add it to every currently-active journey's own `distanceAccumulated`. Each journey still tracks progress from its own start date and totals independently — this avoids redundant HealthKit queries and avoids any risk of double-counting or drift between journeys.

## Distance is the progress metric. Steps are not.

**Decided: progress is driven by HealthKit's `distanceWalkingRunning`, never by steps.**

Steps and distance are two separate HealthKit data types (`stepCount` and `distanceWalkingRunning`), not one calculated from the other. Apple derives distance using a mix of the accelerometer, adaptive stride-length calibration, and GPS where available. A fixed stride multiplier cannot reproduce that, and accuracy is genuinely inconsistent — documented cases of readings off by 10–15% or more depending on where the phone is carried. Apple Watch tends to produce more consistent distance readings than iPhone-only, since it's worn more consistently on the body.

So, concretely:

- **Progress formula:** `progress = min(1.0, journey.distanceAccumulated / journey.totalDistance)`, both in meters.
- Query `distanceWalkingRunning` directly. **Never** estimate distance as `steps × strideLength`.
- Steps may be *displayed* as a secondary stat because some users relate to them intuitively — but a step count never feeds the progress calculation.
- Manage expectations somewhere in the app (onboarding or settings) that distance is an estimate, not GPS-precise.
- Keep the door open to eventually showing *which device* a reading came from (Watch vs. iPhone), since Watch users may trust their number more. See the `sourceDevice` row below.

*(Note: an earlier draft of the design system specified a steps × stride formula. That was a prototype shortcut, is superseded by this section, and has been removed from that document.)*

## Naming: no real-world intellectual property

**Decided.** Journeys, characters, waypoints, color token display names, and UI copy use original names only. Nothing may be lifted from an existing book, film, or game — most pointedly, no Tolkien proper nouns. The fantasy *style* (parchment, faceted figures, a long walk to a volcano) is ours to use; the *names* are not.

The design system was originally authored with placeholder names from a well-known source. Those have been replaced throughout. Canonical names live here:

**Journey 1 — "The Road to Ember Spire"** · `totalDistance` = 1,800 mi (2,896,819 m)

| Order | Waypoint | Cumulative miles |
|---|---|---|
| 0 | Thistledown | 0 |
| 1 | Crosswater | 120 |
| 2 | Silvergate | 460 |
| 3 | The Deepdelve | 660 |
| 4 | Whisperwood | 720 |
| 5 | The Windmark | 1,040 |
| 6 | Whitewatch | 1,540 |
| 7 | Ember Spire | 1,800 |

These numbers live in journey *data* (a bundled JSON file or SwiftData records), never as Swift literals in view code. The table above is the source they're seeded from, not a second copy to keep in sync by hand.

**Journey 3 — "First Journey"** (KAN-7 test fixture) · `totalDistance` = 10 mi (16,093.44 m) · fantasy

A short, low-total journey seeded alongside the two starters so marker positioning and completion can be exercised without walking 1,800 miles. Waypoints at cumulative miles 1 / 3 / 7 / 9, plus start (0) and end (10). Original names, no real-world IP.

| Order | Waypoint | Cumulative miles |
|---|---|---|
| 0 | Trailhead | 0 |
| 1 | First Rest | 1 |
| 2 | Willowbend | 3 |
| 3 | Old Oak | 7 |
| 4 | Lastlight Bridge | 9 |
| 5 | Journey's End | 10 |

**Journey 4 — "The Lantern Road"** (KAN-12) · `totalDistance` = 20 mi (32,186.88 m) · fantasy

A mid-length journey with deliberately uneven waypoint spacing (3-mile and 14-mile segments) so interpolation is exercised across long gaps. Original names, no real-world IP. Accent: `accent/secondary`.

| Order | Waypoint | Cumulative miles |
|---|---|---|
| 0 | Wickgate | 0 |
| 1 | Foglow Bridge | 3 |
| 2 | Palefire Hollow | 17 |
| 3 | Lanternrest | 20 |

**Waypoint map positions (KAN-7).** `positionX`/`positionY` are image-relative normalized coordinates (0…1, origin top-left). These were all `0` in the shipped seed; KAN-7 seeds real placeholder values so the marker interpolation and pin layout can be verified. Exact values are placeholder art (Jeff finalizes against real backgrounds later); the requirement is only that they are distinct, non-colliding, and roughly track `distanceFromStart` so segment interpolation looks natural.

*The Road to Ember Spire:*

| Order | Waypoint | positionX | positionY |
|---|---|---|---|
| 0 | Thistledown | 0.12 | 0.88 |
| 1 | Crosswater | 0.28 | 0.78 |
| 2 | Silvergate | 0.20 | 0.60 |
| 3 | The Deepdelve | 0.40 | 0.52 |
| 4 | Whisperwood | 0.58 | 0.55 |
| 5 | The Windmark | 0.52 | 0.38 |
| 6 | Whitewatch | 0.70 | 0.24 |
| 7 | Ember Spire | 0.82 | 0.12 |

*First Journey:*

| Order | Waypoint | positionX | positionY |
|---|---|---|---|
| 0 | Trailhead | 0.15 | 0.85 |
| 1 | First Rest | 0.30 | 0.72 |
| 2 | Willowbend | 0.45 | 0.60 |
| 3 | Old Oak | 0.60 | 0.42 |
| 4 | Lastlight Bridge | 0.75 | 0.28 |
| 5 | Journey's End | 0.88 | 0.14 |

*The Lantern Road:*

| Order | Waypoint | positionX | positionY |
|---|---|---|---|
| 0 | Wickgate | 0.14 | 0.86 |
| 1 | Foglow Bridge | 0.24 | 0.76 |
| 2 | Palefire Hollow | 0.74 | 0.26 |
| 3 | Lanternrest | 0.86 | 0.14 |

*Around the World* (real-world, no waypoints) is the "journey with no waypoints" case the map must degrade gracefully against.

**Character 1 — "Wren,"** a faceted wayfarer of the small-folk. Additional characters follow the same `Character` model.

## Journey lifecycle & the catalog/instance split (KAN-10 — Decided, not built)

**Decided (KAN-10), not yet built.** The shipped code still has a single combined `Journey` model with `isActive`/`isCompleted`/`isPremium` booleans. KAN-10 splits that one model into two and replaces the booleans with a lifecycle enum. Until Dan ships KAN-10, this section is the target shape, not the code.

**Two models, not one.** A *journey* is really two different things that were conflated in the prototype:

- **`JourneyTemplate` — the catalog entry.** Immutable content: `name`, `type`, `totalDistance` (meters), the four theme fields, `isPremium`, a future `isFeatured`, and the owned `waypoints`. Templates are *seeded content*, re-derivable from this doc's tables. They carry no progress and no lifecycle.
- **`UserJourney` — the instance.** One user's run of a template: `startDate` (UTC), `distanceAccumulated` (meters), a `status`, and a reference to its `JourneyTemplate`. This is the only place per-user, irreplaceable data lives.

**Waypoints belong to the template now** (they are content, one set shared by every instance of that template), not to the instance. `Waypoint.journey` becomes `Waypoint.template`.

**Lifecycle enum — `JourneyStatus`.** Exactly three states on a `UserJourney`, replacing the `isActive`/`isCompleted` booleans:

```swift
enum JourneyStatus: String, Codable, CaseIterable {
    case active     // accruing distance; at most one per template
    case paused     // frozen; UI word is "Paused"; does not accrue
    case completed  // reached 100%; preserved as history
}
```

- **Premium is not a lifecycle state.** It is a catalog attribute (`JourneyTemplate.isPremium`). When purchases ship, `JourneyStatus` must not need a new case — that is the point of keeping it off the enum.
- **At most one `active` instance per template**, enforced in application logic (CloudKit forbids unique constraints, so this is a code invariant, not a DB constraint).
- **Completed wins over paused.** Only an `active` instance accrues distance and can auto-flip to `completed` at 100%. A `paused` instance never accrues, so it never auto-completes.

**Restart keeps completion history.** Restarting a **completed** instance preserves it and creates a *fresh* `UserJourney` at `distanceAccumulated = 0`, `startDate = now`, `status = active`, same template. No confirmation — nothing is lost.

**Restart discards paused progress.** Restarting a **paused** instance *deletes* it and creates a fresh active instance (destructive confirmation required). Abandoned partial runs are not history; only completions are. This is a deliberate ruling (below) to keep the enum at three states — there is no fourth `abandoned` status and no `isArchived` flag.

### Three rulings (KAN-10, Jake)

1. **Completed stacking — one card per template.** "Your Journeys" renders at most one card per `JourneyTemplate`, reflecting the highest-precedence instance: `active` if one exists, else the most-recent `paused`, else the most-recent `completed`. Superseded completed instances are preserved in data but do *not* each get a card here — they surface later in the trophy case (out of scope). This bounds the list and keeps "Your Journeys" a list of things you're doing / can act on, not a history log.
2. **Paused-restart discards.** Restarting a paused instance deletes it (destructive "discard" confirmation). Trophy/history value comes from completions, not abandoned attempts. Keeps `JourneyStatus` at three cases — no fourth terminal state, no archive flag.
3. **All lifecycle mutations route through `ProgressStore`.** Pause / Resume / Restart (and any instance or status write) execute as methods on the `ProgressStore` `@ModelActor`, exactly like delta application — extending the existing "every `Journey`/`ProgressUpdate` write goes through this actor" invariant to the new instance model. Because the actor serializes on one `ModelContext`, an in-flight HealthKit delta and a restart can never interleave. **Invariant:** a delta processed *after* a restart lands only on the new active instance (the old one is no longer `active`); a delta processed *before* correctly credited the old instance. Restart never touches the shared anchor's `lastProcessedDistance` — the anchor keeps advancing monotonically regardless of lifecycle, so a fresh instance simply accrues from the next delta forward, never retroactively. Pause + resume works the same way: deltas during the paused window advance the anchor but are not credited to the paused instance, so resume continues from frozen progress.

**Seeding after KAN-10.** Templates are *always* ensured (idempotent, by name). Instances are *never* auto-created on a fresh install — a new install has a fully-seeded catalog and an empty "Your Journeys". Creating instances is a user action (the `+` / store page is KAN-11, out of scope here).

## Future-proofing checklist

`Built` = exists in the code today. `Decided` = settled, not yet implemented — implement it this way when you get there. `Open` = still needs a call.

| Area | Status | Where this could go later | Assumption to avoid baking in | Lightweight choice instead |
|---|---|---|---|---|
| **Progress anchor** | Built (KAN-6) | Long-running journeys over weeks/months | Querying "today's distance" as the whole metric | Cumulative since `startDate`, always (see above). |
| **Progress metric** | Built (KAN-6) | — | Deriving distance from steps × stride | `distanceWalkingRunning` only; steps are a display stat. |
| **Multiple journeys** | Built (KAN-6); split Decided (KAN-10, not built) | User runs more than one journey, switches between them, keeps a history of completed ones | "There is only one journey, ever" (a singleton); *and* conflating catalog content with a user's run of it | Model as a list. KAN-10 splits this into `JourneyTemplate` (catalog) + `UserJourney` (instance) and replaces `isActive`/`isCompleted` with the `JourneyStatus` enum — see "Journey lifecycle & the catalog/instance split". |
| **Multiple simultaneous journeys** | Built (KAN-6) | Yes — a user can run several journeys at once (e.g. Ember Spire and Around the World together) | Assuming only one journey can ever be "active" at a time | The delta-based update above: one shared "last processed distance" anchor, applied to every active journey's own accumulated total. |
| **Fantasy map + marker** | Built (KAN-7; §04 rig marker KAN-9) | Real-world MapKit routes later | "Progress = marker position" baked into progress logic | Map screen *reads* `journey.progress` / waypoint distances and interpolates marker position; it never owns or writes progress. |
| **Journey types** | Decided | Fantasy illustrated path today; real-world MapKit routes later | Baking "progress = position on my custom image" into the core progress logic | Keep "distance accumulated" and "how that's visualized" as separate concerns. The map screen reads progress; it doesn't own it. |
| **Activity data source** | Built (KAN-6) | Cycling, swimming, wheelchair distance, manual entry for offline days | Hardcoding "distance = HealthKit walking/running distance" deep in many places | Wrap HealthKit access in one small "distance provider." Everything else calls that, not HealthKit directly. |
| **Units** | Built (KAN-6) | Users outside the US expecting km | Hardcoding "miles" into display strings | Store distance in **meters** internally, always. Format for display in one place based on locale. |
| **Journey content** | Partially built (KAN-6: Ember Spire waypoints seeded; no remote/user content) | New journeys added without an app update; eventually user-created routes | Waypoints hardcoded as Swift literals scattered in view code | Define waypoints as structured data (a small JSON file or SwiftData records), even if bundled locally for now. |
| **Visual styling / art** | Built (KAN-7, placeholder art; procedural §04 marker KAN-9) | Placeholder art now; commissioned art later; possibly a distinct art style per journey | Hardcoding image names, colors, or marker shapes directly inside view code | Global design tokens for surfaces/ink; a `JourneyTheme` for per-journey art and accents. See "Theme vs. tokens" below. |
| **Distance accuracy & source device** | Built (KAN-6) | Showing users whether a reading came from Watch or iPhone | Treating the distance number as a single, unlabeled, always-accurate value | Tag stored progress updates with a `sourceDevice` field (watch / phone / unknown) now, even if unused in the UI today. |
| **Character / avatar selection** | Decided | A handful of selectable characters at MVP; more later, possibly customizable or purchasable | Hardcoding the journey marker as one fixed icon | Define a `Character` type (name, asset reference, short description) as SwiftData records. Store the user's `selectedCharacter` reference. |
| **Widget / Lock Screen support** | Built (KAN-6; placeholder App Group ID) | A home screen widget or Live Activity showing journey progress | Storing SwiftData in the default app-private container | Set up the SwiftData container in an **App Group** from day one. Costs nothing now; avoids a real data migration when a widget extension needs the same store. |
| **Localized text** | Decided | Non-English users | Hardcoding UI strings in view code | Use SwiftUI's String Catalog from the start. Same English text today, just organized for translation later. |
| **Time zones** | Built (KAN-6) | User travels during a long-running journey | Comparing "since start" dates in local time, which drifts near midnight across time zones | Store journey start timestamps and progress timestamps in **UTC**; compare consistently regardless of the user's current time zone. |
| **iPhone + Watch + iCloud sync** | Built (KAN-6: model constraints; sync itself not enabled) | Watch app needs the same progress; eventually multi-device | A SwiftData model that's hard to retroactively CloudKit-sync | Build the model **CloudKit-compatible from the start**: default values on every property, optional relationships, no unique constraints. Retrofitting this later is genuinely painful. |
| **Monetization** | Built (KAN-6: field only); moves to template (KAN-10, not built) | Unlocking journey packs, one-time purchase or subscription | Assuming all journeys are always free/unlocked everywhere in the UI; *and* modeling premium as a lifecycle state | `isPremium` is a **catalog** attribute on `JourneyTemplate`, never a `JourneyStatus` case. When purchases ship, the lifecycle enum must not need to change. |
| **Completion behavior** | Built (KAN-6); becomes `status` (KAN-10, not built) | What happens at 100%? | Assuming progress stops cleanly at 100% with no defined next state | Cap `progress` at 1.0; KAN-10 sets `status = .completed` (replacing `isCompleted`) and stops accumulating. Completed instances are **preserved as history** and can be restarted into a fresh instance. Looping is still a v2 decision. |
| **Notifications & milestones** | Built (KAN-6: fields only) | Notify when passing a named landmark | Waypoints as bare coordinates with no metadata | Give each waypoint a `name` and `description` now, even if unused today — costs nothing, enables notifications later without a model change. |
| **Manual correction** | Open | HealthKit data is occasionally wrong, or a user bikes and doesn't want it counted | Treating HealthKit as the sole, unquestionable source of truth forever | Not needed for v1 — just don't design anything that would make an "adjustment" field impossible to add later (it won't). |
| **Social / sharing** | Open | Friends, leaderboards, group journeys | No structural blocker — just don't assume it can't happen | Nothing to do now. Local-first data doesn't prevent adding this later. |

## Theme vs. design tokens

Two layers, and they are not the same thing:

**Global design tokens** (`docs/DESIGN_SYSTEM.md`) define the app's shell: `bg/parchment`, `ink`, `surface/card`, `bg/dark`, plus the four accent hues. These are app-wide, live in the Asset Catalog as colorsets with light/Deepdark variants, and every screen uses them.

**`JourneyTheme`** defines what varies *per journey*: art assets and which accents that journey leans on. **Built (KAN-7).**

**Persistence shape (decided in KAN-7).** A `JourneyTheme` value type cannot be stored on the SwiftData model directly — `Color` is not CloudKit-persistable, and storing a literal `Color` would also violate the design-token rule. So the theme's four pieces live on `Journey` as **flat, CloudKit-safe stored `String` fields** (inline defaults, no unique constraints): `backgroundImageName`, `markerImageName`, `accentColorToken`, `pathColorToken`. Colors are stored as **design-token *names*** (`"accent/primary"`, `"ink"`), never as literal color values. A computed `journey.theme` assembles those strings into a lightweight value type for views:

```swift
struct JourneyTheme {
    let backgroundImageName: String   // asset name, e.g. "ember_spire_bg"
    let markerImageName: String       // asset name, e.g. "marker_wren"
    let accentColorToken: String      // design-token NAME, e.g. "accent/primary"
    let pathColorToken: String        // design-token NAME, e.g. "ink"
}
```

Views read `Image(journey.theme.backgroundImageName)`, `Color(journey.theme.accentColorToken)`, etc. — never `Image("ember_spire_bg")` or `Color.red` typed inline. Swapping placeholder art for commissioned art later becomes: change the asset, update one string in one place (in seed data, not view code).

**Open question for Jake — still Open, explicitly NOT resolved by KAN-7.** The design system notes Deepdark mode can be triggered "inside cave milestones" — i.e. the journey's current waypoint drives appearance. That's a third thing, neither a global token nor a static per-journey theme. KAN-7 ships `JourneyTheme` as a **static per-journey** theme only; it does not implement any waypoint-driven appearance. When that feature is picked up, it can be added as an *optional* per-waypoint override without disturbing KAN-7's shape (additive, not a rewrite) — so this remains a deliberately deferred question, not a KAN-7 blocker.

## What's actually built today

> An earlier, separate prototype repo (`JourneyTest`) contained a `JourneyProgress` singleton, a step-driven `JourneyMapView`, and a `HealthKitManager` that summed raw samples (and triple-counted across sources). **None of that was carried over.** Do not treat it as a baseline; it is retired.

**KAN-6 (shipped)** built the data foundation everything else depends on:
- `Journey` and `ProgressUpdate` SwiftData models (plus a minimal `Waypoint` to hold the relationship), CloudKit-compatible, in an **App Group** container (placeholder group ID — needs the real team prefix before device provisioning).
- A `HealthKitManager` "distance provider": authorization request, a one-time cumulative statistics query on launch, and an `HKObserverQuery` with background delivery. HealthKit's no-data error is treated as a legitimate zero reading; unexpected errors (e.g. locked-device store) never touch the anchor.
- The **delta-anchor** update applied to every active journey, serialized through a `@ModelActor` (`ProgressStore`) — all `Journey`/`ProgressUpdate` writes must go through it.
- Meters as the canonical unit, UTC timestamps, `sourceDevice` tagging. The anchor is **monotonic** — never re-anchored downward.
- A developer-only debug display (no journey UI, no themed art yet) with accessibility identifiers for automated testing.
- Deferred from KAN-6: Watch-side HealthKit wiring; past-`startDate` journey backfill (journey creation doesn't exist yet); waypoint seeding beyond the Ember Spire table.

`Character`, `JourneyTheme`, `isPremium` behavior, the String Catalog, and the real map UI remain **Decided, not built** and are out of scope for KAN-6.

**KAN-7 (shipped; marker upgraded to the §04 rig in KAN-9)** built the first real, themed UI on top of KAN-6's data foundation:
- `JourneyTheme` as four flat CloudKit-safe `String` fields on `Journey` (see "Theme vs. design tokens") plus a computed `theme` accessor. Colors stored as token *names*, resolved at the view layer.
- A journey-scoped fantasy **map view**: themed background, character marker interpolated along the waypoint polyline by real distance, waypoint states (reached / next / upcoming / completed). It only *reads* progress.
- A minimal **journey list / entry point** to open the map from (no such screen exists today — only `DebugView`), so the map is always scoped to the journey it was opened from.
- Seed data: real placeholder `positionX`/`positionY` for Ember Spire's waypoints (were all `0`), plus the **First Journey** fixture (10 mi, waypoints at miles 1/3/7/9) with its own waypoints and positions, seeded idempotently.
- Not in KAN-7: waypoint-driven Deepdark appearance (still Open), real commissioned art, Watch-side map, cross-device seed de-duplication (deferred until CloudKit sync is actually enabled).

## What NOT to worry about yet

To be precise about "database": a **local database is already part of the plan** — SwiftData (SQLite under the hood) runs entirely on the user's device and is the right home for journeys, characters, and progress data, with zero server involved. What to skip for now is a **backend/server database** — one running on the internet that many users' apps talk to over a network. That's only needed for cross-device sync beyond what iCloud offers for free, social features, or pushing new content without an app update. Journeys, characters, and progress all belong in SwiftData from day one; none of that requires a backend.

## Rough data model sketch

All properties need inline default values and optional relationships to stay CloudKit-compatible. Never name a type plain `Task` — it collides with Swift's concurrency type.

> **KAN-10 splits `Journey` into a catalog `JourneyTemplate` and an instance `UserJourney`** (see "Journey lifecycle & the catalog/instance split"). The shipped code still has the single combined `Journey` below until Dan ships KAN-10; the split shape is shown after it.

**Journey** (shipped shape, KAN-6/7 — superseded by the split below once KAN-10 ships)
- `id`, `name`, `type` (fantasy / realWorld)
- `totalDistance` — meters
- `distanceAccumulated` — meters
- `startDate` (UTC), `isActive`, `isCompleted`, `isPremium`
- `theme`, relationship to its waypoints

**JourneyTemplate** (KAN-10 catalog — content, no progress, no lifecycle)
- `id`, `name`, `type` (fantasy / realWorld)
- `totalDistance` — meters
- `isPremium`, `isFeatured` (dormant field, cheap to add now)
- four flat theme fields (`backgroundImageName`, `markerImageName`, `accentColorToken`, `pathColorToken`) + computed `theme`
- relationship to its `waypoints`; optional inverse to its `instances`

**UserJourney** (KAN-10 instance — one user's run of a template)
- `id`, `startDate` (UTC), `distanceAccumulated` — meters
- `status: JourneyStatus` (active / paused / completed) — replaces `isActive`/`isCompleted`
- optional relationship to its `template`
- computed `totalDistance` / `name` / `theme` / `progress` proxy through `template`

**Waypoint**
- `id`, `order`, `position` (image-relative x/y, or lat/long)
- `distanceFromStart` — meters
- `name`, `descriptionText` (for future notifications)
- KAN-10: relationship back-reference becomes `template` (was `journey`)

**Character**
- `id`, `name`, `assetName`, `descriptionText`

**ProgressUpdate** (the delta-based anchor)
- `anchorStartDate` (UTC) — the fixed reference date the cumulative query runs *from*. Set once when the anchor is created (first authorization). Not per-journey.
- `lastProcessedDistance` — meters, the cumulative `distanceWalkingRunning` from `anchorStartDate` that has already been applied to journeys. One shared anchor across all active journeys.
- `lastUpdated` (UTC)
- `sourceDevice` (watch / phone / unknown)

**Delta computation — get this right (the prototype's triple-count bug lived here):** compute the new cumulative total with an `HKStatisticsQuery` using `.cumulativeSum` over `[anchorStartDate, now]`, which de-duplicates overlapping samples from multiple sources (iPhone + Watch). **Never sum raw `HKQuantitySample`s** — that double/triple-counts when phone and watch both record. `delta = max(0, newCumulative − lastProcessedDistance)`. Add `delta` to each active, non-completed journey's `distanceAccumulated`. **`lastProcessedDistance` is monotonic — advance it only when `newCumulative > lastProcessedDistance`; never lower it.** This is fail-closed by design: revoked read access surfaces as zero data with *no error* (HealthKit hides read status for privacy), so a downward re-anchor would reset the anchor toward 0 and then re-credit all distance since `anchorStartDate` to every journey on the next real reading — a silent, unbounded double-credit. Holding the anchor means a transient dip yields `delta 0` with the anchor intact, and a genuine Health-side deletion merely under-credits future walking until the cumulative total re-exceeds the old anchor. That matches this doc's rule that edits/deletions must not drive progress backward (a real "adjustment" story is still `Open`); under-crediting is bounded and recoverable, double-crediting is neither. `lastUpdated`/`sourceDevice` may refresh on any successful numeric reading for liveness; on a query *error* (nil), touch nothing. The cumulative-sum predicate uses `options: []` (not `.strictStartDate`): the window start is fixed across queries so there is no delta drift, and including a boundary-straddling sample whole is preferred over `.strictStartDate` silently dropping its real post-anchor portion. A journey created with a past `startDate` needs a one-time backfill query from its own `startDate`; a journey created "now" starts at 0 and simply accrues future deltas.
