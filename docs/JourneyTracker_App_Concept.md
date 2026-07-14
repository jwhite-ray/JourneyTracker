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

> **Identity under review (KAN-25, 2026-07-13).** After copyright concerns, this journey's narrative identity — its name, waypoints, and theme — is being rethought, because its shape sits close to well-known fictional territory. The entry stays **functional** meanwhile (seeded, startable, renders via the KAN-7 pin-and-route fallback); its faceted-map authoring is deferred until KAN-25 resettles the identity, then goes through the KAN-23 hand-drawn pipeline (see the fantasy-map P4 note). Treat the names below as provisional until KAN-25 lands.

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

**Journey 5 — "Road to The Windrise Peaks"** (KAN-23) · `totalDistance` = 302.4 mi (486,665.6 m) · fantasy

The first journey authored through the KAN-23 hand-drawn-map pipeline: Justin drew the world, the coordinator digitized it (source-image pixels as map units, ~6.85 px/mi), and waypoints were placed by his landmark descriptions. Its faceted map authoring ships in `WindrisePeaksMap`, and the journey view renders that faceted map (KAN-21 — this journey is the P4 vehicle); the KAN-7 pin-and-route screen remains only as the fallback for non-authored journeys. Original names, no real-world IP.

| Order | Waypoint | Cumulative miles |
|---|---|---|
| 0 | Wavecrest | 0 |
| 1 | Millhollow | 14.2 |
| 2 | Sable Ford | 20.9 |
| 3 | Hallowmere | 72.9 |
| 4 | Oxbow Crossing | 122.6 |
| 5 | Thistlewood | 153.9 |
| 6 | Farrow's Rest | 172.1 |
| 7 | Stonewash Ford | 218.8 |
| 8 | Rivergate | 227.7 |
| 9 | The Windrise Peaks | 302.4 |

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

*Road to The Windrise Peaks:* Unlike the earlier journeys' eyeballed art placement, these derive directly from the hand-drawn map's pixel space — `positionX = x / 1190`, `positionY = y / 896` against the 1190×896 source bounds — and are what `SeedData` ships.

| Order | Waypoint | positionX | positionY |
|---|---|---|---|
| 0 | Wavecrest | 0.0740 | 0.3371 |
| 1 | Millhollow | 0.1412 | 0.3973 |
| 2 | Sable Ford | 0.1647 | 0.4375 |
| 3 | Hallowmere | 0.4437 | 0.5446 |
| 4 | Oxbow Crossing | 0.4681 | 0.8359 |
| 5 | Thistlewood | 0.6370 | 0.7567 |
| 6 | Farrow's Rest | 0.7244 | 0.8292 |
| 7 | Stonewash Ford | 0.8748 | 0.6217 |
| 8 | Rivergate | 0.9160 | 0.5804 |
| 9 | The Windrise Peaks | 0.9118 | 0.0469 |

*Around the World* (real-world, no waypoints) is the "journey with no waypoints" case the map must degrade gracefully against.

**Character 1 — "Wren,"** a faceted wayfarer of the small-folk. Additional characters follow the same `Character` model.

## Journey lifecycle & the catalog/instance split (KAN-10 — Built, PR #6)

**Built (KAN-10, PR #6 on `feature/kan-10-journey-lifecycle` — complete; merge to `main` pending).** The single combined `Journey` model is gone: it is split into `JourneyTemplate` (catalog) + `UserJourney` (instance), and the `isActive`/`isCompleted` booleans are replaced by the `JourneyStatus` enum. Pause / Resume / Restart and the one-active-per-template invariant ship as serialized `ProgressStore` methods; "Your Journeys" renders one card per template with the KAN-10 status stamp + kebab menu. This section now describes shipped shape, not a target. (A store upgraded from the retired combined-`Journey` shape restores its instances once via the migration stash — see `JourneyMigration`/`SeedData`.)

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

**Seeding after KAN-10.** Templates are *always* ensured (idempotent, by name). Instances are *never* auto-created on a fresh install — a new install has a fully-seeded catalog and an empty "Your Journeys". Creating instances is a user action — the `+` / **Available Journeys** store page (KAN-11); see "Available Journeys & the start flow" below.

## Available Journeys (the store page) & the start flow (KAN-11 — Built, PR #8)

**Built (KAN-11, PR #8 — merged).** KAN-10 seeds a full catalog but gives no way to start a run — a fresh install has an empty "Your Journeys". KAN-11 adds the entry point that first creates a `UserJourney`. Until Dan ships it, this section is the target shape, not the code.

**Entry point.** A circled `+` lives in the "Your Journeys" navigation bar (trailing) at all times — populated or empty — and opens **Available Journeys**, the catalog/store page. The empty state gains a primary CTA that opens the same screen, so an empty "Your Journeys" is never a dead end. Both the toolbar `+` and the empty-state CTA drive one shared navigation destination.

**Navigation shape — push, not sheet (Jake's ruling).** Available Journeys is *pushed* onto the existing "Your Journeys" `NavigationStack` (the same stack that already pushes `JourneyMapView`). On a successful start the screen pops back to "Your Journeys", which — because it reads instances via `@Query` — already shows the new active card with no manual refresh. Tradeoff: a sheet would read more as a discrete modal "add" task and give free swipe-to-dismiss, but push composes better with the future premium/detail drill-down, gives a native back button for "back out changes nothing", and makes the land-on-Your-Journeys-and-see-the-new-card return a clean pop rather than an explicit sheet dismiss.

**What it lists.** Every `JourneyTemplate` in the catalog (three today), one row each, showing: `name`, total distance via `DistanceFormatter` (the single formatting authority, meters → miles), and a waypoint count **only when the template has waypoints** — "Around the World" has none, so the count is omitted entirely, never rendered as "0". A row may use the template's `theme.accentColorToken` for its accent (e.g. the Start button fill, per §07). The row reserves a structural slot for a future premium lock badge and `isFeatured` emphasis; today the list is plain and neither gates nor reorders anything.

**Startable predicate (authoritative in `ProgressStore`).** A template is **startable** iff it has **no `.active` instance AND no `.paused` instance**. Completed instances do not block. Concretely:
- **Startable** → the row offers an enabled "Start Journey" button (§07).
- **Active instance exists** → the row is blocked and shows an "ACTIVE" badge (same status language as the KAN-10 stamp); no second active can be created.
- **Paused instance exists** → the row is blocked and directs the user to resume or restart it on "Your Journeys" (a paused run is not a second startable slot).

**Two start-flow rulings (KAN-11, Jake):**
1. **Paused blocks store-start.** A template with a paused instance is *not* startable here. Starting a "new" run while a paused one exists would either strand the paused run behind one-card precedence or silently discard it; both belong to the explicit Resume/Restart affordances on "Your Journeys", not to a store tap. So the store never creates a run for a template that already has a paused instance — it points the user back to the card.
2. **Completed-only allows store-start.** A template whose only instances are completed *is* startable here, and starting it is exactly the card's "Restart completed" — a fresh `UserJourney` at 0 m / `startDate = now` / `.active`, completion history preserved, no confirmation (nothing is lost). This keeps the store and the card consistent: the same non-destructive fresh-run behavior, reachable from two places.

**Row-body vs. control affordance (Jake's ruling, KAN-11 Rooster finding 5).** The **row body is inert on every row** — startable and blocked alike — and is reserved for a future premium/detail drill-down; all actions live in explicit, labeled controls. On a **startable** row the *only* start affordance is the "Start Journey" pill (so a stray body tap can't cause an accidental start). On a **blocked** row (active or paused) the "manage this on Your Journeys" affordance is a **real, labeled `Button`/`NavigationLink`** — never a whole-row `onTapGesture` — because an invisible row-tap is undiscoverable to VoiceOver and inverts the affordance (an inert-looking body being tappable while the action-inviting row is dead). Activating it pops Available Journeys and returns to "Your Journeys", where that template's card and its kebab lifecycle actions (Pause / Resume / Restart) live — the store starts *new* runs; managing an existing run belongs to its card. Paused rows additionally carry a short directive caption. (Exact visuals — badge, caption, disabled-button styling, the blocked control's label — are Jeff's.)

**Where the start mutation lives.** Starting a journey is a new serialized method on the `ProgressStore` `@ModelActor` — e.g. `startJourney(templateID: PersistentIdentifier)` — extending KAN-10 Ruling 3 (every instance/status write routes through this one actor). It resolves the template on the actor's own context, **re-checks the startable predicate there** (no active and no paused instance of that template — reusing/adjacent to `ensureNoActiveInstance`), and only then inserts a fresh `.active` `UserJourney` and saves. If the predicate fails it throws a new `LifecycleError` (e.g. `.notStartable`), which the UI swallows.

**Double-tap safety is an actor guard, not just UI state.** Two rapid taps enqueue two `startJourney` calls; the actor serializes them on its one context. The first creates the active instance and saves; the second re-runs the predicate, now sees an active instance, and throws — so exactly one instance is ever created even if the button's disabled state hasn't propagated yet. The UI *also* flips the affordance immediately off the `@Query` update, but correctness does not depend on that.

**Works with HealthKit never granted.** A started run sits at `distanceAccumulated = 0` and simply accrues future deltas whenever (if ever) Health data arrives — the shared monotonic anchor keeps advancing regardless. Starting never backfills; a run created "now" starts at 0 (see "The one assumption that matters most" and the delta-anchor rules).

**Out of scope for KAN-11:** purchases / paywall, rendering premium-locked visuals beyond a structural slot, `isFeatured` behavior (the featured shelf), and the trophy case (superseded completed instances). The row leaves room for these; none is wired.

## Delete a journey (KAN-13 — Built, PR #9)

**Built (KAN-13, PR #9).** A card's kebab (`•••`) on "Your Journeys" gains a **Delete** row on every status (active / paused / completed), below the lifecycle actions. Delete **wipes the journey's data entirely and returns the template to a startable state** — the primary use is testing (delete, then re-start fresh from the store), but it is also the real "completely remove this" affordance.

**Scope: template-wide, all instances.** Delete keys on the **`JourneyTemplate`**, not the single shown instance, and destroys **every** `UserJourney` of that template — active, paused, **and** completed history. Deleting only the shown instance is wrong: KAN-10 Ruling 1's one-card precedence would then surface a buried completed/paused sibling as a new card right after the user asked to remove it. Deleting a **completed** card therefore **destroys its completion record** (and its future trophy) — the only self-consistent reading of "completely remove." Because delete wipes *all* instances including superseded completions, it is also the correct primitive for the future **trophy case**: a template-wide delete clears every trophy for that template, and the trophy case (when built) must treat this as authoritative and never resurrect a deleted completion.

**What delete never touches:** the `JourneyTemplate` (shared, re-seeded catalog content — it stays and returns to startable), and the shared `ProgressUpdate` anchor (`lastProcessedDistance` / `anchorStartDate`). The anchor keeps advancing monotonically; a template started again after delete accrues from the next delta forward at 0, exactly like any fresh start.

**Where the mutation lives.** Deleting is a new serialized method on the `ProgressStore` `@ModelActor` — `deleteJourney(templateID: PersistentIdentifier)` — extending KAN-10 Ruling 3 (every instance write routes through this one actor's single context). It resolves the template on the actor's own context (throws `LifecycleError.templateNotFound` if it doesn't resolve), fetches all `UserJourney` and deletes those matching the template's ID in one save, and **deletes instances only — never the template, never the anchor**. It **fails closed**: a throwing guard fetch throws `LifecycleError.guardCheckFailed` and aborts *before* deleting anything (no partial delete); an empty match set is a no-op success (covers the double-tap race). Because delete serializes with delta application on the one context, an in-flight HealthKit delta and a delete can never interleave — the delta lands fully before the wipe or finds no instance after it, so no double-credit and no corruption. After delete, the template's Available Journeys row is startable again (KAN-11 predicate: no active and no paused instance).

**Confirmation (§07).** Every status routes through the §07 destructive confirmation (dimmed scrim, alert language, **Cancel first**), reusing the KAN-10 paused-restart overlay pattern — no new visual language. Active/paused copy discards "X mi" of progress via `DistanceFormatter`; completed copy destroys the completion record; all state the journey returns to Available Journeys and that it can't be undone.

## Journey stats & waypoint crossings (KAN-14 — Built, on `feature/kan-14-journey-stats`; PR pending)

**Built (KAN-14, on `feature/kan-14-journey-stats`; PR pending; merge to `main` pending).** KAN-14 adds journey *stats* to two existing screens and, to support them, the app's **first record of when a waypoint was crossed**. Before this, nothing persisted a crossing time — the map derived waypoint *state* live from `distanceAccumulated` but kept no history of *when* each was reached. This section describes the shipped shape and rules the whole feature.

**What ships:** on the "Your Journeys" card — the journey's start date, and a "X mi until [next waypoint]" line. On the map screen — a stats list under the progress bar: start date, three derived stats (**DAYS ON JOURNEY**, average pace in mi/day, projected finish date), then one row per **reached** waypoint (name, date reached, time taken from the previous waypoint). Completed and zero-waypoint journeys degrade per the rulings below. (The shipped card/map label for the days stat is **"DAYS ON JOURNEY"**; the prose below calls the underlying computed value "days-on-road / days-on-journey" interchangeably — same stat.)

### The data problem: crossings must be recorded, forward-only

Waypoints are **template content** (KAN-10) — shared by every instance, carrying no per-run timing. "When did *this run* cross Crosswater?" is per-instance, irreplaceable data that nothing records today. KAN-14 introduces it.

**Ruling 1 — a `WaypointCrossing` `@Model`, owned by the `UserJourney`, snapshotting waypoint identity.** A crossing is its own model, not a serialized blob on `UserJourney`. Rationale: it matches the app's existing relational, fetch-and-insert-on-the-actor pattern; a delta that crosses several waypoints at once inserts one row each (all with the same `crossedAt` — that is the truth: they were observed crossed at the same reading); and per-instance crossing counts are tiny (≤ waypoint count). A `Data` blob would be opaque, would force a read-decode-append-encode-write on every delta, and would break the one-concept-one-`@Model` grain. The crossing **snapshots** the waypoint's identity (`waypointID`, `order`, `name`, `distanceFromStart`) rather than holding a `Waypoint` relationship — waypoints are re-seeded content and can be recreated/cascaded, so a snapshot keeps the historical row self-standing and immune to content churn. The crossing's owning relationship is to the **`UserJourney`** with `deleteRule: .cascade`, so a KAN-13 delete and a paused-restart wipe an instance's crossings automatically. CloudKit-safe: inline default on every stored property, optional relationship, no unique constraint.

**Ruling 2 — crossings are written by `ProgressUpdater` at delta-application time, inside the actor (extends KAN-10 Ruling 3).** In `ProgressUpdater.apply`, per active journey, let `old` = `distanceAccumulated` before the delta and `new` = its value after (including any completion clamp). A waypoint is crossed iff `old < waypoint.distanceFromStart <= new` **and** `waypoint.distanceFromStart > 0` (half-open interval, low end excluded so the same waypoint is never double-recorded across consecutive deltas; the `> 0` guard is Ruling 4 below). Insert a `WaypointCrossing` for each, `crossedAt = ` the reading's `date`, guarded by an idempotency check (skip if a crossing with that `waypointID` already exists for this instance). All of this saves in the same actor transaction as the delta — an in-flight delta and a lifecycle mutation can never interleave.

**Ruling 3 — pre-existing progress is forward-only; the migration creates NO crossing records.** A journey already part-way along when KAN-14 ships has crossed waypoints with no record, and there is no honest `crossedAt` to assign them — the true crossing time is unknown. We do **not** fabricate one, and we do **not** stamp a "reached at ship time" marker (that would be a fabricated date wearing a disguise). The V2→V3 migration creates nothing. At read time, a waypoint that is reached (`distanceFromStart <= distanceAccumulated`) but has no crossing row renders **"date not recorded"** — unambiguous and truthful. Distinguishing "reached before tracking" from a genuine write bug is not the migration's job: a real bug would be a `ProgressUpdater` defect, and no marker would surface it. Forward-only from ship, period.

**Ruling 4 — 0-mile waypoints (start positions like Trailhead / Wickgate) are never crossings and never appear in the reached log.** The journey *starts* there; arriving at the origin is not an achievement. The `distanceFromStart > 0` guard in Ruling 2 excludes them from recording, and the reached-log builder skips any waypoint at `distanceFromStart == 0`. Consequence for the map log: the **first listed** reached waypoint's "time taken" is measured **from the journey's `startDate`**, not from a (non-existent) origin crossing.

### Completion, pause, and the derived stats

**Ruling 5 — `completedAt` is the canonical finish date, set by `ProgressUpdater` at auto-complete.** Add `completedAt: Date?` to `UserJourney` (optional, default `nil`, CloudKit-safe). When `apply` clamps to `total` and flips `status = .completed`, it sets `completedAt = date`. The card's finish-date treatment and the map list's final row both read `completedAt`. This is authoritative because it also covers **zero-waypoint** completions ("Around the World"), which have no final-waypoint crossing to read. A pre-KAN-14 / migrated completed instance has `completedAt == nil` → "date not recorded" (never fabricated). The KAN-7 completed **banner** ("Journey complete — Wren resting at X") is unchanged; the finish date is an additional stat line, not competing copy — no contradiction.

**Ruling 6 — paused journeys freeze honestly via `pausedAt` + `accumulatedPausedSeconds`; days-on-road and pace exclude paused time.** The three derived stats use elapsed time as a denominator; wall-time keeps growing while a paused run's distance is frozen, which would silently tank pace and push out the projection — dishonest to the walker. So add two CloudKit-safe fields to `UserJourney`: `pausedAt: Date?` (default `nil`) and `accumulatedPausedSeconds: Double` (default `0`). `ProgressStore.pause` sets `pausedAt = now`; `ProgressStore.resume` does `accumulatedPausedSeconds += now − pausedAt` then `pausedAt = nil`. Define **active elapsed** = `(reference − startDate) − accumulatedPausedSeconds − currentPauseSeconds`, where `currentPauseSeconds = (now − pausedAt)` while paused else `0`, and `reference` is `completedAt` for a completed run else `now`. While paused this formula **freezes automatically** — as wall-time advances, `(now − startDate)` and `(now − pausedAt)` grow in lockstep and cancel — so days-on-road, pace, and projection all sit frozen at their pause-moment values with no special-casing, and resume continues correctly. **Rulings that follow from this:**
- **DAYS ON JOURNEY (days-on-road) = active elapsed (excludes paused time).** Pace × days ≈ distance stays internally consistent, and a long pause never permanently defames the walker's pace. The wall-clock date is still shown separately as the start date, so nothing is hidden.
- **Projected finish** = `reference + (remainingDistance / paceMetersPerActiveDay)`, frozen while paused (frozen pace, frozen reference).
- **Legacy paused edge:** an instance paused *before* KAN-14 (or via a KAN-10 migration path) has `pausedAt == nil` while `status == .paused`; its true pause moment is unknown. Such an instance degrades its three time-derived stats to a "not enough data yet" state rather than fabricating — a bounded edge that self-heals on the next resume→pause. Distance-derived bits (progress, "X mi until next") are unaffected.
- **Legacy completed edge (Rooster finding 2):** a run completed *before* KAN-14 has `completedAt == nil` after migration, so a naive `reference = completedAt ?? now` would fall through to `now` and let DAYS ON JOURNEY keep counting and AVG. PACE keep decaying forever on a *finished* run — plainly wrong. Ruling: when `status == .completed && completedAt == nil`, the three time-derived stats (days, pace, projected/finish date) degrade to "not enough data yet" / "date not recorded" (dovetailing Ruling 5's `completedAt == nil` → "date not recorded"); distance-derived stats are unaffected. This mirrors the legacy-paused treatment: an unknown timing anchor degrades honestly rather than fabricating. A run completed *after* KAN-14 has a real `completedAt`, so its finished stats freeze at completion correctly.

**Ruling 7 — pace/projection need a floor of data; otherwise "not enough data yet."** A same-day, zero-distance fresh journey cannot be projected (division by ~0). Require `distanceAccumulated > 0` **and** active elapsed ≥ a small floor (≈ 1 hour) before showing pace or projection; below that, both render a "not enough data yet" placeholder (exact copy is Jeff's). Days-on-road and start date always show.

### The single formatting authority for durations and dates

**Ruling 8 — one duration rule and one date style, in a new `StatFormatter`; distances (incl. rates) stay in `DistanceFormatter`.** `DistanceFormatter` is distance-only; dates and durations get a sibling authority, `StatFormatter`, so all calendar/elapsed formatting lives in exactly one place (mirroring "formatting happens in exactly one place").
- **Duration** (time-taken between waypoints, days-on-road): `< 1 minute` → "under a minute"; `< 1 hour` → whole minutes ("1 minute" / "47 minutes"); `< 48 hours` → whole hours ("1 hour" / "14 hours"); `≥ 48 hours` → whole days ("6 days"). Rounded to the shown unit; singular/plural handled. No absurd extremes in either direction (never "0.02 hours", never "0.3 days"); very long spans simply stay in days.
- **Date** (start date, date reached, projected finish, finish date): locale-aware medium date, no time — "Jun 3, 2026". One shared formatter for every calendar date in the feature, matching the start-date display.
- **Pace** stays in `DistanceFormatter` as `milesPerDay(_:)` → "4.2 mi/day", keeping every meters→miles division inside the distance authority; views never divide.

**Ruling 9 — the "X mi until [next]" label must never truncate the waypoint name (KAN-11 never-truncate precedent).** Layout is Jeff's, but the constraint is architectural: the miles-until line reflows/wraps rather than clipping a long waypoint name against the start date. Handed to Jeff.

**Where the derived math lives.** A pure, SwiftUI/SwiftData-free `JourneyStatsCalculator` (sibling to `MarkerPositionCalculator`) computes days-on-road, pace, projected finish, next-waypoint + distance-to-next, and the reached-waypoint log rows from an instance's raw fields + waypoints + crossings. Both screens and the formatters render its output; it is unit-testable in isolation and owns none of the state.

**Schema:** this is **V3**, reached by an **additive lightweight** migration — a new `WaypointCrossing` model plus optional/defaulted fields on `UserJourney` (`completedAt`, `pausedAt`, `accumulatedPausedSeconds`, the `crossings` relationship). No custom stage, no stash (unlike KAN-10's V1→V2): register `JourneySchemaV3`, add `MigrationStage.lightweight(fromVersion: V2, toVersion: V3)`, point `SharedModelContainer.schema` at V3's models.

**Out of scope for KAN-14:** backfilling historical crossings; year-rollup or richer duration phrasing; charts/graphs/trend lines; the trophy case; per-waypoint milestone notifications; km/locale unit switching (still deferred); steps-as-a-stat; real-world MapKit journey stats; any visual design (Jeff owns both screens' layout, mocked at Gate 2).

## The fantasy map: faceted cartography system (epic KAN-16 — P1–P3 built, P4 in progress via KAN-21)

The fantasy-journey map is the app's signature surface. **KAN-7 already shipped a first, real version of it** (see the "Fantasy map + marker" row and "What's actually built today"): a parchment field with a dot-dash ink route, teardrop waypoint pins, and Wren interpolated along the waypoint polyline by real distance. As originally shipped that map was deliberately simple — a handful of SwiftUI pin views (a `WaypointPin` type) over a procedural background, positioned by normalized 0…1 coordinates. (That `WaypointPin` view type is now deleted: KAN-21 renders pins on **every** surface — the faceted map and the pin-and-route fallback alike — in a `Canvas` via `TerrainRenderer.drawPins`, per the shared §07.8 terrain-pin anatomy in `docs/DESIGN_SYSTEM.md`.) The **faceted cartography system** described here is the *next* layer: the textured, faceted **terrain** the map is meant to have, the data it's authored from, the coordinate space it lives in, and a camera that can move over it. **P1–P3 of this layer are now built** — the seeded generator, `MapValidator`, the single-pass `Canvas` `TerrainRenderer`, and the camera/LOD — but wired only into `DebugView`, not yet into any user-facing screen. **P4 (KAN-21) is in progress**: wiring that renderer into the user-facing journey view. It is epic KAN-16, phased P1–P4.

The **visual** style of the terrain — facet recipes, color triads, glyph sizes, the fixed back-to-front draw order — lives in `docs/DESIGN_SYSTEM.md`'s terrain & cartography section (Jeff owns it, and is porting it in parallel). This section owns the **behavior, data, and architecture** underneath that style: how a map is authored, what coordinate space it lives in, how it's drawn, and how the camera moves. Where the two meet they cross-reference; neither restates the other.

Real-world journeys (Around the World, a specific trail) are a *separate* visualization and will use MapKit when built — see the Journey types row. Everything below is the **custom fantasy** renderer. Camera behavior (zoom, pan, framing) should feel consistent across both kinds of journey.

**Decided: a map is authored as a short list of REGION records plus a deterministic seed — never as hand-placed glyphs.**

A range, a forest, a river, a lake, a coastline, a village site are each one *region record* describing a shape and a few parameters (extent, density, jitter, edge feathering) in map units. A seeded procedural scatter generator expands those regions into the hundreds of tiny glyph placements the style calls for (a forest is dozens of scattered trees, a range is many small peaks, a village is a tight cluster of homes — the visual recipes are Jeff's).

- *Trap:* authoring a map by placing individual glyphs by hand. It doesn't scale, it can't be re-tuned, and it can't be validated. Explicitly rejected.
- *Mitigation:* author regions; generate glyphs.
- **Determinism is a hard requirement — 1 journey = 1 map, the same for every user (re-confirmed by Justin 2026-07-12).** A journey's **regions + seed ship frozen with the journey** as bundled authoring content (not synced state — see "Map authoring data"), and the generator is a pure function of `(regions, seed)`. So one journey yields exactly one map, identical for every user, on every launch and every device — no wall-clock, no `Date()`, no unseeded RNG. A map that reshuffles between launches is a bug. Because only the small, frozen authoring input is ever present, a user's iCloud devices — and every other user's install — regenerate the very same map without syncing any glyph positions.

**Decided: placement rules are build-time validators, not runtime conventions.**

The design session fixed logical constraints on how terrain relates; the KAN-23 pilot loosened several of them (see "the drawing trumps the rules" below). The current set: **a river's source may rise anywhere on land** — an upland spring, a range, or off-map — and the only source rule the validator keeps is that a source must **not be IN water** (a lake or sea); **a river terminates in a lake, at the coastline, OR by exiting the authored bounds** (draining to an off-map sea/basin, which the renderer clips as usual) — never mid-land under the ocean fill; roads and the trek path stay on land and never cross a lake or ocean; **settlements sit within a soft ≤40-mile cap of water** (river bank, lake shore, coast) — a sanity cap on inland distance, not a "villages hug the shore" rule. These are checked when a map is authored/generated, and a violation **fails authoring, not the render**.

- *Settlements — inland is allowed (KAN-23):* the old ≤4-mile-from-water rule assumed every place is a fishing village; real worlds have road towns and market towns miles from any shore (the pilot map's farthest town is ~33 mi out). The hard validator is now the soft **≤40-mile** cap only. "Villages sit by water" survives as a **design preference**, not a validator — it belongs to the look-rules in `docs/DESIGN_SYSTEM.md` (Jeff's), where it can guide placement aesthetics without failing authoring.

Three further validators were fixed at the **KAN-18 Phase 1 gate** and are decided in their own blocks below — they join this same P2 build-time validator list: **every waypoint lies on the trek path**, **every terrain region's real-mile size falls within its canonical bounds**, and **a mountain range's *total authored* length meets its minimum even when the range runs off-map**.

- *Trap:* checking these at runtime and drawing a "best-effort" broken map, or trusting authors to remember them.
- *Mitigation:* a validator over the region set and its generated placement, so a map that breaks a rule is an authoring error the author fixes. The shipped map is correct by construction.

**Decided: each fantasy journey has a fixed logical map-unit coordinate space; rendering applies one camera transform.**

Waypoints, regions, and the trek path are all authored in *map units* — the journey's own logical coordinate space — not as a fraction of the screen. A map may be far larger than the screen. Rendering maps logical units → screen points through a single camera transform (translate + scale).

- *Trap:* the coordinate space the shipped KAN-7 map uses. Today `JourneyMapView.swift` positions waypoints and pins as fractions of the container (`waypoint.positionX * geo.size.width`, `positionY * geo.size.height`), and `MarkerPositionCalculator` returns normalized 0…1 points. That normalized image-relative space is correct and sufficient for a *single-screen* pin-and-route map, but it can't zoom, can't exceed the screen, and ties layout to device size. A faceted map is far larger than one screen.
- *Mitigation:* one map-unit space per fantasy journey (its bounds are journey data), one camera transform at draw time. **This extends and supersedes the normalized 0…1 space in P4** (below) — it is not a bug in KAN-7, it is the next coordinate model the terrain and camera require.

**Decided (KAN-18 P1 gate): each fantasy map's map-unit space has a real-distance scale.**

The map-unit space above stops being scale-agnostic the moment a map is authored for a real journey. The trek path's drawn **arc length** in map units corresponds to the journey's real `totalDistance` (meters), and waypoint `distanceFromStart` values pin intermediate points along that path. Together these define a **miles-per-map-unit** scale for that journey. Region sizes (the bounds block below) are authored and validated in **real miles** and converted through this scale into map units at authoring time.

- This is the honest answer to "the specimen looks like 10 miles, not 1,800": with a real scale the map canvas *grows with journey length*, and one screen at chapter zoom shows a single leg — not the whole world. P1's hand-placed specimen is deliberately scale-agnostic; scale becomes real at P2 authoring.
- *The one subtlety worth stating:* a drawn trek path meanders, so its map-unit arc length is longer than the journey's straight-line displacement across the map. The scale is defined by **trek-path arc length ↔ journey `totalDistance`**, not by straight-line distance — and everything else (region-size conversion, marker interpolation) follows from that single identity.
- *Trap — meander is a scale knob in disguise:* authoring a wildly meandering trek path silently compresses apparent terrain scale. The same real mile buys fewer map units of straight-line extent, so a range or forest authored in real miles renders smaller relative to the visible corridor than the author expects.
- *Mitigation:* keep trek-path meander moderate, and treat the arc-length ↔ `totalDistance` identity as the one true definition of scale. If terrain reads wrong-sized, the fix is the path's arc length, never per-region fudge factors.

**Decided (KAN-18 P1 gate): every waypoint lies ON the trek-path polyline.**

The dotted trek path is the line the user's avatar travels, and it is the spine of the map. **Every waypoint's position is a point on that polyline** — geometrically, the trek path passes through each waypoint at that waypoint's `distanceFromStart` along the path. A waypoint is not placed *near* the path or beside it; it *is* the point on the path at its distance. (In KAN-7 today the marker rides a polyline that connects the waypoints, so this holds trivially; in P4 the trek path is authored as its own `trekPath` region and the marker rides *that*, so the rule ensures the authored path still passes through every waypoint.)

- *Why it matters — the marker-interpolation implication:* the marker rides the trek path by real distance (per "the map reads progress" below). Because waypoints are pinned to the same path at the same distances, **marker-position and waypoint-position agree exactly** at the moment the marker crosses a waypoint. An off-path waypoint would make the marker "arrive" at a spot the waypoint visibly isn't — and would desync the KAN-14 crossing that fires at that distance.
- *Validator (P2):* a map any of whose waypoint positions does not lie on the trek-path polyline (within tolerance) **fails authoring**.
- *Trap:* authoring a waypoint at an evocative spot beside the path but off it.
- *Mitigation:* author waypoints by `distanceFromStart` and let the path define position, or snap authored positions onto the path, then validate.

**Decided (KAN-18 P1 gate): terrain regions are sized in REAL MILES, within canonical bounds.**

Region extents are authored and validated in real miles (converted to map units through the journey's scale above), giving terrain real-world plausibility. The canonical bounds for `MapRegion` records, enforced by P2 validators:

| Region kind | Bound (real-world) |
|---|---|
| Range / hill-chain | 15–300 miles long; never more than 10 miles wide |
| Forest | 0.5–300 square miles |
| River | never shorter than 2 miles long |
| Lake | 0.3–60 square miles |
| Ocean | no size restriction |

- *One kind covers ranges and hills (KAN-23 ruling):* the old 75-mile minimum assumed Ember Spire-scale massifs; real hand-drawn worlds are hill country. The minimum drops to **15 miles**, and a single `range` kind spans everything from a low hill-chain to a great massif. The renderer treats shorter/lower chains as **hills** visually. Justin chose *looser bounds over a new element* at the KAN-23 pilot; a dedicated **hills glyph** stays a possible future Design System addition (Jeff's call), but bounds-wise one kind suffices and no new region kind is introduced here.
- *Ranges run off-map (the small-journey ruling):* scenery is bigger than the journey. Small maps — First Journey (10 mi), The Lantern Road (20 mi) — cannot contain a long range, so a range may **extend beyond the map's authored bounds**; the small map shows a big range merely passing through its corridor. Validators check a range's **total authored length** (which may exceed the map bounds), never its on-map visible portion. Regions may be authored partly outside `bounds` and the renderer clips them — the `Canvas` already culls to the visible rect, so clipping is free.
- *Trap — clipped-portion validation cuts both ways:* validating the visible (clipped) portion of a region would either reject a legitimately large range on a small map, or tempt the author to shrink scenery below real-world plausibility just to make it fit inside the bounds. Both are wrong.
- *Mitigation:* validate the authored (total) extent in real miles; let the renderer clip to bounds at draw time.

**Decided (KAN-23 pilot, 2026-07-13): the drawing trumps the rules.** When Justin's first real hand-drawn map was digitized, the validators flagged 23 honest conflicts with the bounds table above — which had been written before anyone had seen real hand-drawn geography. His ruling was verbatim: *"The drawing trumps my rules, in fact, update the rules to fit with these new constraints."* So the bounds and validators exist to catch **digitization errors and physical absurdities** (a river running uphill into the sea, a town in the middle of the ocean, a zero-length lake), **not to constrain Justin's geography**. When a hand-drawn map conflicts with a bound, the **bound gets re-examined first**, not the map. The looser range/hill length, the ≤40-mile inland settlement cap, the land-anywhere river source, the off-map river mouth, and the raised lake cap below are all products of this ruling — each widened to fit the pilot's real geography rather than rejecting it.

*Visual cross-reference:* the *look* of these rulings — the always-labeled destination pin, the lake facet seam, the river-confluence melt — is Jeff's, in `docs/DESIGN_SYSTEM.md`'s terrain & cartography section. This doc owns where waypoints and regions sit, how they're sized, and how they're validated; that doc owns how they're drawn. Neither restates the other.

**Decided: terrain is drawn in a single-pass SwiftUI `Canvas`, visible-rect culled; no per-glyph view hierarchy.**

Hundreds of glyphs cannot each be a SwiftUI `View` — layout and diffing would collapse. The terrain is one `Canvas` that draws the generated glyphs in the design system's fixed back-to-front order, culling anything outside the current visible rect. Terrain is fully **static** — it does not animate and does not change once generated; only the marker and the camera move. So the generated glyph set is produced once per map (per LOD bucket) and redrawn cheaply.

- *Trap:* a `ZStack`/`ForEach` of glyph views, or animating the terrain. (KAN-7 originally drew its ~8 waypoint pins as SwiftUI `WaypointPin` views over the terrain — fine at that count. KAN-21 deleted that type: pins on **every** surface, the pin-and-route fallback included, now draw in the `Canvas` via `TerrainRenderer.drawPins` per the shared §07.8 terrain-pin anatomy. So the *terrain's* hundreds of glyphs are what must not become a view hierarchy — and the pins are no longer one either.)
- *Mitigation:* one culled `Canvas` pass for terrain; all motion lives in the marker and the camera.

**Decided (amended 2026-07-12 by Justin): two surfaces — a STATIC journey view, and a gesture-driven FULL-SCREEN map. Gestures, LOD, and the overview toggle live only on the full-screen surface.**

Justin's 2026-07-12 ruling splits the camera across two surfaces rather than putting pinch-zoom directly in the main tab: "show them a static map zoomed to an appropriate level but give them a button on the map where they can expand it to full screen and do the pinching and zooming." This supersedes the earlier single-surface framing of this block (which put gestures on the map screen itself). Concretely:

- **Journey view (the tab formerly called the "map view" — renamed 2026-07-12).** Shows a **static** map — no pinch, no pan, no gestures — framed at **chapter zoom**: the current leg only (last waypoint reached → next waypoint), marker centered. An **expand button** on the map opens the full-screen map. This is the default surface a user lands on for a journey; daily progress stays legible here precisely because chapter zoom, not the whole world, is the framing.
- **Full-screen map (opened by the expand button).** This is where the camera lives: pinch-zoom and pan, backed by `UIScrollView` (via a representable) for correct momentum, bounce, and zoom feel. Default framing is **chapter view** (the same leg the journey view showed); a toggle switches to a **full-journey overview**.
- **LOD (full-screen only, since only it zooms):** as zoom decreases, the scatter *density* thins, and glyph/stroke *on-screen* sizes stay roughly constant **near the design-reference scale** (the ~30-mile-per-screen chapter framing the P1 look was approved at) but then **taper toward a fixed floor as the camera climbs to extreme altitude**. Zooming out keeps masses reading as textured terrain — never collapsing to dust, never popping into a few large icons. *Trap — literal constant sizing at altitude defeats itself:* holding glyph/stroke size truly constant all the way out to the 1,800-mile overview makes each glyph out-scale entire landforms — trees become icons, a river stroke renders wider than a lake — so the very mechanism meant to prevent "icons" produces them. *Mitigation:* a **deterministic pt-per-mile taper with a floor** — constant near the reference scale, easing to a minimum on-screen size at overview altitude (Dan's implementation is the reference for the exact constants). The static journey view renders at its fixed chapter framing's LOD bucket; on a long-leg journey that bucket **may** thin deterministically (stable per marker position). What it never does is change with gestures — it has none.
- *Rationale — why the camera is not optional:* a day's walking is on the order of 0.2% of Ember Spire's 1,800 miles. Framed to the whole journey, a day's progress is sub-pixel and the marker never visibly moves — the core motivation loop dies. Chapter framing (on both surfaces) makes daily progress legible; the full-journey overview is a deliberate opt-in on the full-screen surface only. This is *why* the map-unit space and camera exist at all.
- *Trap — gesture surfaces inside a scrolling tab fight the parent scroll view:* putting pinch-zoom/pan directly in the in-tab journey view pits the map's own `UIScrollView` against the tab/navigation scrolling around it, producing gesture conflicts and unpredictable zoom feel.
- *Mitigation:* gestures live **only** on the dedicated full-screen surface, which owns the whole screen and has no competing scroll parent. The in-tab journey view is inert (static) by construction, so there is nothing for a gesture to fight.

**Decided: the map reads progress; it never owns or computes it.**

This reinforces the Journey types row — and, unlike the other decisions here, **KAN-7's built map already satisfies it.** `MarkerPositionCalculator` is a pure function of the journey's distance-based progress (`distanceAccumulated` interpolated by each waypoint's real `distanceFromStart` in meters, per "The one assumption that matters most" and the Progress metric section). It reads progress, never writes it, and never touches HealthKit or steps. The faceted system **preserves that exactly**: the marker keeps interpolating by real distance; terrain simply draws around it. The map layer has no distance math of its own — no steps, no per-view constants.

- *Note on the retired prototype:* the old `JourneyTest` map drove its marker off a step count plus a unitless distance literal, and split position evenly across waypoint indices. Both were bugs, both were fixed in KAN-7 (`MarkerPositionCalculator`'s header calls the even-split out by name), and neither is a pattern to reintroduce. This repo does **not** carry that drift.

**Phased delivery — epic KAN-16.** Each phase is gated on Justin's visual approval before the next begins:

- **P1** — a hand-placed `Canvas` specimen that proves the faceted look (one screen, static, no generator). Validates the aesthetic cheaply before building machinery. Hand-placement here is a deliberate one-off proof, not the authoring model.
- **P2** — the seeded generator plus a **persistent** tuning harness: an authoring tool with live knobs for density, jitter, feather, and seed. The harness stays in the repo as the map-authoring surface; it is *not* throwaway like a `Mockups/` variant.
- **P3** — camera, LOD, and performance: UIScrollView-backed zoom/pan, chapter-view framing, density-thinning LOD, `Canvas` culling.
- **P4 (in progress — KAN-21 on `feature/kan-21-journey-view`)** — wire the built faceted renderer (P1–P3: generator, `MapValidator`, `Canvas` `TerrainRenderer`, camera/LOD, all exercised in `DebugView` today) into the **user-facing journey view**, with **Road to The Windrise Peaks (KAN-23) as the vehicle** — the wholly-original, hand-drawn journey whose region+seed authoring already ships in `WindrisePeaksMap`. Per the two-surface decision above: the in-tab **journey view** renders a **static, chapter-framed** terrain surface with an **expand button** onto the gesture-driven **full-screen map**. The marker rides the authored `trekPath` by real `distanceAccumulated` (via `MarkerPositionCalculator`'s map-unit successor — the distance math is unchanged, per "the map reads progress"); **runtime waypoint states (reached / next / upcoming / completed, derived live from progress) override any authored preview states**; a fantasy journey's waypoints move from normalized 0…1 to map units through the camera transform, with the terrain `Canvas` beneath the unchanged marker and pins.
  - **The template→authoring lookup is the bundled-content seam.** A journey view resolves its template to its map authoring here; **keyed by template *name* today** (as `DebugView` hardcodes `WindrisePeaksMap.make()`), moving to **shipped JSON** later (see "Map authoring data"). A journey **without** map authoring — the catalog's other templates today — **keeps the KAN-7 pin-and-route rendering**, which is now the **documented fallback**, not dead code: the two surfaces coexist, selected by whether authoring exists for that template.
  - **Ember Spire's map authoring is deferred.** The old plan to author "the real Ember Spire map" as P4 is replaced by the above. Ember Spire's own faceted map waits on the **KAN-25 identity rethink** (its narrative shape sits close to well-known fictional territory); when its identity resettles, its map is authored through the proven **KAN-23 hand-drawn pipeline** — Justin draws the world, the coordinator digitizes it to regions + seed — not through this wiring step. Until then Ember Spire renders via the KAN-7 pin-and-route fallback like any unauthored journey.

**Naming.** The design session's sample map used a placeholder proper noun lifted from a well-known source; it must **never** ship. All map content uses original names — see the naming section (Ember Spire, Thistledown, Crosswater, and the rest).

## Future-proofing checklist

`Built` = exists in the code today. `Decided` = settled, not yet implemented — implement it this way when you get there. `Open` = still needs a call.

| Area | Status | Where this could go later | Assumption to avoid baking in | Lightweight choice instead |
|---|---|---|---|---|
| **Progress anchor** | Built (KAN-6) | Long-running journeys over weeks/months | Querying "today's distance" as the whole metric | Cumulative since `startDate`, always (see above). |
| **Progress metric** | Built (KAN-6) | — | Deriving distance from steps × stride | `distanceWalkingRunning` only; steps are a display stat. |
| **Multiple journeys** | Built (KAN-6); split Built (KAN-10, PR #6) | User runs more than one journey, switches between them, keeps a history of completed ones | "There is only one journey, ever" (a singleton); *and* conflating catalog content with a user's run of it | Model as a list. KAN-10 splits this into `JourneyTemplate` (catalog) + `UserJourney` (instance) and replaces `isActive`/`isCompleted` with the `JourneyStatus` enum — see "Journey lifecycle & the catalog/instance split". |
| **Multiple simultaneous journeys** | Built (KAN-6) | Yes — a user can run several journeys at once (e.g. Ember Spire and Around the World together) | Assuming only one journey can ever be "active" at a time | The delta-based update above: one shared "last processed distance" anchor, applied to every active journey's own accumulated total. |
| **Fantasy map + marker** | Built (KAN-7; §04 rig marker KAN-9) | Real-world MapKit routes later | "Progress = marker position" baked into progress logic | Map screen *reads* `journey.progress` / waypoint distances and interpolates marker position; it never owns or writes progress. Faceted terrain rendering is a separate Decided layer — see next row. |
| **Fantasy map rendering (faceted terrain)** | P1–P3 built (KAN-16); P4 in progress (KAN-21) | The signature faceted terrain; zoom/pan; more journeys later | Hand-placing glyphs; fractional-of-screen coordinates for a map larger than the screen; a per-glyph SwiftUI view hierarchy for hundreds of terrain glyphs | Author as region records + a deterministic seed; one logical map-unit space + a single camera transform; a single culled SwiftUI `Canvas` pass for terrain. Builds *around* KAN-7's already-correct distance-driven marker (row above), which it preserves. See "The fantasy map: faceted cartography system". |
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
| **Monetization** | Built (KAN-6: field only); moved to template (KAN-10, PR #6) | Unlocking journey packs, one-time purchase or subscription | Assuming all journeys are always free/unlocked everywhere in the UI; *and* modeling premium as a lifecycle state | `isPremium` is a **catalog** attribute on `JourneyTemplate`, never a `JourneyStatus` case. When purchases ship, the lifecycle enum must not need to change. |
| **Completion behavior** | Built (KAN-6); now `status` (KAN-10, PR #6); `completedAt` added (KAN-14) | What happens at 100%? | Assuming progress stops cleanly at 100% with no defined next state | Cap `progress` at 1.0; KAN-10 sets `status = .completed` (replacing `isCompleted`) and stops accumulating. KAN-14 records `completedAt` (UTC) as the canonical finish date. Completed instances are **preserved as history** and can be restarted into a fresh instance. Looping is still a v2 decision. |
| **Notifications & milestones** | Built (KAN-6: fields only); crossing timing added (KAN-14) | Notify when passing a named landmark | Waypoints as bare coordinates with no metadata | Give each waypoint a `name` and `description` now, even if unused today — costs nothing, enables notifications later without a model change. KAN-14 adds `WaypointCrossing` records (when a run crossed each waypoint), written by `ProgressUpdater` — the same detection point a future crossing notification would fire from. |
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
- A journey-scoped fantasy **map view** (the tab renamed the **journey view** on 2026-07-12 — see the two-surface camera decision): themed background, character marker interpolated along the waypoint polyline by real distance, waypoint states (reached / next / upcoming / completed). It only *reads* progress.
- A minimal **journey list / entry point** to open the map from (no such screen exists today — only `DebugView`), so the map is always scoped to the journey it was opened from.
- Seed data: real placeholder `positionX`/`positionY` for Ember Spire's waypoints (were all `0`), plus the **First Journey** fixture (10 mi, waypoints at miles 1/3/7/9) with its own waypoints and positions, seeded idempotently.
- Not in KAN-7: waypoint-driven Deepdark appearance (still Open), real commissioned art, Watch-side map, cross-device seed de-duplication (deferred until CloudKit sync is actually enabled).

**KAN-10 (built; PR #6 on `feature/kan-10-journey-lifecycle`, merge to `main` pending)** split the model and added the lifecycle:
- `JourneyTemplate` (catalog content) + `UserJourney` (per-user instance) replace the combined `Journey`; `JourneyStatus` (active / paused / completed) replaces `isActive`/`isCompleted`. `Waypoint.journey` → `Waypoint.template`.
- Pause / Resume / Restart-completed / Restart-paused ship as serialized `ProgressStore` methods enforcing the one-active-per-template invariant; a one-time migration stash restores instances from the retired shape.
- "Your Journeys" renders one card per template (highest-precedence instance) with the §07 status stamp + kebab action menu + destructive restart confirmation. Instances are never auto-seeded — a fresh install has a full catalog and an empty list.
- Not in KAN-10: the entry point that *creates* an instance (the `+` / Available Journeys store — KAN-11), the trophy case for superseded completions, purchase/premium gating.

**KAN-11 (built, PR #8 — merged)** — the Available Journeys store page and the start flow that first creates a `UserJourney`. See "Available Journeys (the store page) & the start flow" above.

**KAN-13 (built, PR #9)** — Delete a journey from "Your Journeys" (template-wide data wipe) via the card kebab. New serialized `ProgressStore.deleteJourney(templateID:)`; §07 destructive confirmation per status; returns the template to startable; anchor and other journeys untouched. See "Delete a journey (KAN-13)" above.

**KAN-14 (built, on `feature/kan-14-journey-stats`; PR pending)** — Journey stats on the card + map, plus the first per-run waypoint-crossing timing. New `WaypointCrossing` model (V3, additive lightweight migration) written by `ProgressUpdater` inside the actor; `completedAt` / `pausedAt` / `accumulatedPausedSeconds` added to `UserJourney`; new `StatFormatter` (dates + durations) and `DistanceFormatter.milesPerDay`; pure `JourneyStatsCalculator`. Forward-only crossings, honest paused/completed freezing. See "Journey stats & waypoint crossings (KAN-14)" above.

**KAN-16 (epic — P1–P3 built, P4 in progress)** — the faceted cartography system: region authoring + a deterministic seeded scatter generator + a persistent tuning harness, a map-unit coordinate space, a culled single-pass `Canvas` terrain renderer, and a chapter-view camera with density-thinning LOD. Phased P1–P4, each gated on Justin's visual approval. **P1–P3 are built** — the generator, `MapValidator`, the `Canvas` `TerrainRenderer`, and the camera/LOD, plus the `WindrisePeaksMap` / `SampleJourneyMap` / `EmberSpireScaleFixture` authoring — but wired only into `DebugView` so far. **P4 (KAN-21, on `feature/kan-21-journey-view`, in progress)** wires that renderer into the user-facing journey view with Road to The Windrise Peaks as the vehicle (KAN-23 authoring). Once P4 lands, the faceted surface **supersedes KAN-7's pin-and-route `JourneyMapView` for journeys that have map authoring**, while pin-and-route **remains the documented fallback for journeys without authoring**; the distance-driven marker is preserved unchanged on both surfaces. See "The fantasy map: faceted cartography system" above.

## What NOT to worry about yet

To be precise about "database": a **local database is already part of the plan** — SwiftData (SQLite under the hood) runs entirely on the user's device and is the right home for journeys, characters, and progress data, with zero server involved. What to skip for now is a **backend/server database** — one running on the internet that many users' apps talk to over a network. That's only needed for cross-device sync beyond what iCloud offers for free, social features, or pushing new content without an app update. Journeys, characters, and progress all belong in SwiftData from day one; none of that requires a backend.

## Rough data model sketch

All properties need inline default values and optional relationships to stay CloudKit-compatible. Never name a type plain `Task` — it collides with Swift's concurrency type.

> **KAN-10 (PR #6) split `Journey` into a catalog `JourneyTemplate` and an instance `UserJourney`** (see "Journey lifecycle & the catalog/instance split"). This shipped; the combined `Journey` below is the retired pre-KAN-10 shape, kept only for migration reference. The split shape follows it.

**Journey** (retired pre-KAN-10 shape, KAN-6/7 — superseded by the split below; kept for migration reference)
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
- **KAN-14 additive fields (V3):** `completedAt: Date?` = nil (UTC, set at auto-complete — canonical finish date); `pausedAt: Date?` = nil (UTC, set on pause / cleared on resume); `accumulatedPausedSeconds: Double` = 0 (sum of completed pause windows, so active-elapsed excludes paused time); `@Relationship(deleteRule: .cascade) crossings: [WaypointCrossing]?` (cascades on instance delete / paused-restart)

**WaypointCrossing** (KAN-14 — when a run crossed a waypoint; the first per-instance timing record)
- `id`, `crossedAt` (UTC) — the reading date at which the crossing was observed
- snapshot of the crossed waypoint's identity (not a live relationship): `waypointID: UUID`, `order: Int`, `name: String`, `distanceFromStart: Double` (meters)
- optional owning relationship back to its `UserJourney` (inverse of the cascade `crossings`)
- CloudKit-safe: inline default on every stored property, optional relationship, no unique constraint. Written only by `ProgressUpdater` inside the `ProgressStore` actor. Never records a 0-mile (origin) waypoint. Forward-only — no historical backfill.

**Waypoint**
- `id`, `order`, `positionX` / `positionY` — **today** image-relative normalized (0…1, origin top-left) for fantasy maps (KAN-7); lat/long later for real-world. **KAN-16 P4** reinterprets a fantasy-journey waypoint's position as **map units** (the journey's own logical coordinate space — see "The fantasy map: faceted cartography system"), rendered through the camera transform rather than multiplied by container size. *Not* a fraction of the screen once P4 lands.
- `distanceFromStart` — meters (unchanged across P4; the marker interpolates by this real distance, never by screen position)
- `name`, `descriptionText` (for future notifications)
- KAN-10: relationship back-reference is `template` (was `journey`)

**Map authoring data** (fantasy journeys only, KAN-16 — the input to the seeded scatter generator; **the `MapRegion` model + Swift authoring are built (P1–P3), e.g. `WindrisePeaksMap`; bundled-JSON shipping and the template→authoring lookup seam are P4/KAN-21 work in progress**)
- the journey's map-unit `bounds` (its logical coordinate space), its **miles-per-map-unit scale** (defined by trek-path arc length ↔ journey `totalDistance`, per "The fantasy map"), and a single scatter `seed`
- an ordered list of **MapRegion** records: `kind` (range / forest / river / lake / coast / groundCover / settlement / road / **trekPath**), a shape spec (blob or ellipse extent; river source→mouth; village site; path polyline) authored and validated in **real miles** and converted to map units through the scale, subject to the canonical size bounds (KAN-18, loosened at the KAN-23 pilot: ranges/hill-chains 15–300 mi long / ≤10 mi wide, forests 0.5–300 sq mi, rivers ≥2 mi, lakes 0.3–60 sq mi, oceans unrestricted), and scatter parameters (density, jitter, feather). A region may be authored partly outside `bounds` (a range running off-map); the range validator checks *total authored* length, and the renderer clips.
- every **Waypoint** position on a fantasy journey lies on the `trekPath` polyline at its `distanceFromStart` — a P2 authoring validator (KAN-18), not just a convention; this is what keeps the distance-driven marker and the waypoint pins coincident at crossings.
- This is *static authored content*, not user-mutable state, and it is **deliberately NOT a CloudKit-synced SwiftData model** — unlike `UserJourney` / `WaypointCrossing` / `ProgressUpdate`. It travels as part of the bundled journey definition (JSON) alongside the `JourneyTemplate` catalog content; the generator expands it to glyphs deterministically at load. Nothing here changes as the user walks — only the marker's position moves (read from progress via `MarkerPositionCalculator`, or its P4 map-unit successor). Because the map is a pure function of `(regions, seed)`, iCloud devices regenerate an identical map without syncing any glyph positions: only the small authoring input needs to be present, and it ships as bundled content rather than synced state.

**Character**
- `id`, `name`, `assetName`, `descriptionText`

**ProgressUpdate** (the delta-based anchor)
- `anchorStartDate` (UTC) — the fixed reference date the cumulative query runs *from*. Set once when the anchor is created (first authorization). Not per-journey.
- `lastProcessedDistance` — meters, the cumulative `distanceWalkingRunning` from `anchorStartDate` that has already been applied to journeys. One shared anchor across all active journeys.
- `lastUpdated` (UTC)
- `sourceDevice` (watch / phone / unknown)

**Delta computation — get this right (the prototype's triple-count bug lived here):** compute the new cumulative total with an `HKStatisticsQuery` using `.cumulativeSum` over `[anchorStartDate, now]`, which de-duplicates overlapping samples from multiple sources (iPhone + Watch). **Never sum raw `HKQuantitySample`s** — that double/triple-counts when phone and watch both record. `delta = max(0, newCumulative − lastProcessedDistance)`. Add `delta` to each active, non-completed journey's `distanceAccumulated`. **`lastProcessedDistance` is monotonic — advance it only when `newCumulative > lastProcessedDistance`; never lower it.** This is fail-closed by design: revoked read access surfaces as zero data with *no error* (HealthKit hides read status for privacy), so a downward re-anchor would reset the anchor toward 0 and then re-credit all distance since `anchorStartDate` to every journey on the next real reading — a silent, unbounded double-credit. Holding the anchor means a transient dip yields `delta 0` with the anchor intact, and a genuine Health-side deletion merely under-credits future walking until the cumulative total re-exceeds the old anchor. That matches this doc's rule that edits/deletions must not drive progress backward (a real "adjustment" story is still `Open`); under-crediting is bounded and recoverable, double-crediting is neither. `lastUpdated`/`sourceDevice` may refresh on any successful numeric reading for liveness; on a query *error* (nil), touch nothing. The cumulative-sum predicate uses `options: []` (not `.strictStartDate`): the window start is fixed across queries so there is no delta drift, and including a boundary-straddling sample whole is preferred over `.strictStartDate` silently dropping its real post-anchor portion. A journey created with a past `startDate` needs a one-time backfill query from its own `startDate`; a journey created "now" starts at 0 and simply accrues future deltas.
