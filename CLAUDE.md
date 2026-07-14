# JourneyTracker — Team Workflow

An iOS/watchOS app that turns real walking into visible progress along real-world or fantasy journeys. This project uses a team of specialized subagents. Follow this workflow.

## Source-of-truth documents

| Document | Governs | Owner | Who must read it |
|---|---|---|---|
| `docs/JourneyTracker_App_Concept.md` | Concepts, architecture, data model, behavior, naming | **Jake** | everyone |
| `docs/DESIGN_SYSTEM.md` | Visual style only — color, type, shape, layout, character rig | **Jeff** | Jeff, Dan, Rooster |
| `CLAUDE.md` (this file) | Workflow, roles, Jira process | main session | everyone |

**Precedence:** the App Concept doc wins on anything about behavior, data, or naming. The Design System wins on anything about how a thing looks. Neither may silently contradict the other — if they do, fix the doc, don't pick a side in code.

Both docs are mirrored on the Jira board (see below). The repo copy is canonical; the Jira copy is a read-only mirror refreshed when the doc's owner changes it.

## Roles

| Agent | Role | Writes | Owns |
|---|---|---|---|
| **Collin** | Product | nothing (read-only) | user stories, acceptance criteria |
| **Jake** | Lead engineer | `docs/JourneyTracker_App_Concept.md` only | PRDs, architecture, the App Concept doc |
| **Jeff** | Design | mockups in `Mockups/`, `docs/DESIGN_SYSTEM.md` | visual direction, the Design System doc |
| **Dan** | Implementation engineer | production source | the real feature |
| **Rooster** | QA reviewer | nothing (read-only) | code correctness findings |
| **Jeremiah** | Manual tester | nothing (read-only) | behavioral verification in the Simulator |
| **Claude** (main session) | Coordinator | this file, Jira | orchestration, all Jira updates, commits |

Nobody writes outside their column. Collin and Rooster and Jeremiah never edit files at all.

## For new features (not small fixes)

1. **Collin** drafts a user story and acceptance criteria from the user's perspective.
   - **→ PAUSE: user reviews and approves Collin's story.** Do not proceed to Jake until approved.

2. **Jake** reviews Collin's draft against the App Concept doc, questions assumptions, and finalizes a combined PRD.

3. If the feature involves new or changed UI: **Jeff** proposes 2–3 SwiftUI Preview mockup variants based on Jake's PRD. **The user picks the direction** — not Jeff, not the main session.
   - **→ PAUSE: user reviews PRD + mockups and approves the chosen direction.** Do not proceed to Dan until approved.

4. **Dan** implements the real feature from the finalized PRD and the chosen mockup, then deletes the rejected mockup variants.

5. **Rooster** reviews the implementation for bugs, edge cases, and quality — read-only, reports findings, never edits.

6. **Jeremiah** verifies the feature in the Simulator from a real user's perspective — driven by a tightly-scoped flow (see token discipline).

## For small fixes and tweaks

Skip the full pipeline — implement directly, then have Rooster review before committing.

## Mockups

Jeff writes variants to `Mockups/`, which is **excluded from the app target**. They exist to be looked at in an Xcode Preview and then thrown away. Dan deletes the rejected variants as part of step 4; the chosen one gets hardened into a real view and its mockup file removed too. `Mockups/` should be empty between features.

The mockup *source files* are disposable, but their rendered screenshots are not: at each Design Review gate the main session renders every variant/state to PNG (shown to the user inline + as an artifact page) and archives the renders to `docs/mockups/<TICKET>/` before the losing variants are deleted. Each ticket's Jira record links both the artifact page and the repo archive path. Jira attachments aren't possible with the connected tools — links only.

## Token discipline (quality gates are exempt)

The pipeline exists to ship correct code — none of the rules below may weaken a review, a QA pass, or a user gate. They cut coordination overhead only.

- **Never resume a large agent for a small question.** A resume replays the agent's whole transcript (a two-sentence ruling has cost 147k tokens this way) and stale context causes real errors (a resumed agent once "restored" correctly-deleted files). Spawn a fresh, narrowly-briefed agent — or handle it on the light path — unless the prior context genuinely saves more than the replay costs (e.g. a reviewer re-verifying his own findings).
- **Tier the pipeline by default.** Full pipeline: new UI *and* new architecture. Middle path (user's request is the story; skip Collin; mockups only if genuinely new visual language): user-specced features. Light path: content, fixes, chores. When in doubt between two tiers, ask the user — it's one sentence.
- **Mockups stay at 2–3 variants with full state coverage** (user decision: three variants, not fewer — the state coverage has caught real defects).
- **Rooster's FIRST pass is always full for features.** His RE-verification after rework is skipped only when every finding was Low severity — Jeremiah's QA covers the behavior; keep the re-pass for any High/Medium finding.
- **Jeremiah always gets a tightly-scoped test flow, never "test the app."** Before invoking him, the implementer (Dan) — or Jake — writes the exact flow, derived from the surfaces the diff actually touched: the shortest, most tap-reliable path to reach the changed surface in each relevant state, plus a checklist where each item ties to something the change altered. Hand that to Jeremiah close to verbatim. This keeps him from wandering into untouched flows and burning the run on navigation/tap-reliability (a real failure on KAN-27, where an unscoped brief left him retry-tapping the catalog/debug/lifecycle and never reaching the marker). If a needed state isn't reachable through seeded data or normal navigation, the flow says so rather than sending him to flail.
- **Jira: one comment per phase-pair** (story+PRD, mockups+pick, implementation+review, QA+ship) rather than per stage; keep them tight. Doc mirror refreshes happen once at ticket close, batched across tickets when several close together.
- **Agent reports: cap at what the next role needs to act.** Findings/rulings in full; narrative at a minimum. The coordinator's prompts should say so.

## Documentation maintenance

When a feature introduces a new architectural decision, changes an existing one, or resolves something a doc flags as `Open`, update the doc as part of completing the feature — don't leave it stale. Jake owns the App Concept doc; Jeff owns the Design System. For rare light-path changes that touch architecture without Jake, the main session handles it and says so.

When a doc changes, the main session refreshes its Jira mirror.

## Jira board management

Claude (the main session, not subagents) owns all Jira updates via the connected Atlassian tools.

- **Site:** `justinwhitehead.atlassian.net` (cloudId `ea56bb10-4ca3-472f-a1a7-c20c146485ec`)
- **Project key: `KAN`** (display name "JourneyTracker")
- **Doc mirrors:** [KAN-4](https://justinwhitehead.atlassian.net/browse/KAN-4) (App Concept), [KAN-5](https://justinwhitehead.atlassian.net/browse/KAN-5) (Design System). Read-only mirrors — never edit a doc *in* Jira; edit the repo copy and refresh the mirror.

### Lanes and transitions

These are the board's **actual** status names and transition IDs, verified against the API. Use the exact names; don't guess.

| Lane (status name) | Status ID | Transition ID | Owned by |
|---|---|---|---|
| `Backlog` | 10004 | 11 | — |
| `PRD in progress` | 10008 | 2 | Collin, then Jake |
| `Design Review` | 10009 | 3 | Jeff (UI features only) |
| `In Development` | 10005 | 21 | Dan |
| `In Review` | 10006 | 31 | Rooster |
| `QA / Testing` | 10010 | 4 | Jeremiah |
| `Done` | 10007 | 41 | — |

The seven lanes map one-to-one onto the pipeline. Design Review applies only to features with UI changes; skip it otherwise.

- When a new feature is kicked off: create a ticket in `Backlog` with the user's request as the description, then move it to `PRD in progress` when Collin starts.
- At each pipeline handoff, move the ticket to the matching lane and post the completing agent's summary as a comment (Collin's user story, Jake's PRD, Jeff's chosen mockup direction, Dan's implementation summary, Rooster's findings, Jeremiah's test results).
- If Rooster or Jeremiah finds issues requiring rework, move the ticket back to `In Development` and comment why.
- Move to `Done` only after Jeremiah's verification passes and the work is committed.
- **Every feature's deliverable ends with a pull request.** Before moving the ticket to `Done`: push the feature branch, open a GitHub PR (repo `jwhite-ray/JourneyTracker`), and post the PR link in BOTH places — the final Jira comment on the ticket and the closing summary to the user in chat. A feature isn't delivered until the user has the PR link in hand.
- For small fixes (light path): create the ticket directly in `In Development`, then move to `In Review` for Rooster and on to `Done` after the commit. Skip the earlier lanes.
- Never mark a ticket Done without a commit hash referenced in a comment.
- Issue types available: Epic, Story, Task, Feature, Bug, Subtask. Use Story for user-facing features, Bug for defects, Task for chores and docs.

## Always

- Read `docs/JourneyTracker_App_Concept.md` before any architectural decision. **Most of what it describes is decided but not yet built** — check the code before assuming a system exists.
- Progress is driven by HealthKit **`distanceWalkingRunning`**, cumulative since each journey's `startDate`, via the shared delta-based update. Never "today's steps," and never `steps × stride`.
- Distances are stored in **meters**. Timestamps in **UTC**. Formatting happens in exactly one place.
- No real-world intellectual property in names — journeys, characters, waypoints, and copy are original. No Tolkien proper nouns.
- Keep art and styling swappable: global design tokens for surfaces and ink, `JourneyTheme` for per-journey art and accents. No hardcoded colors or literal asset names in views.
- SwiftData models stay CloudKit-compatible: default values on every stored property, optional relationships, no unique constraints.
- Never name a type plain `Task` — it conflicts with Swift's built-in concurrency type.
