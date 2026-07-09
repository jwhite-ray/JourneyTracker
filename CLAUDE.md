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
2. **Jake** reviews Collin's draft against the App Concept doc, questions assumptions, and finalizes a combined PRD.
3. If the feature involves new or changed UI: **Jeff** proposes 2–3 SwiftUI Preview mockup variants based on Jake's PRD. **The user picks the direction** — not Jeff, not the main session.
4. **Dan** implements the real feature from the finalized PRD and the chosen mockup, then deletes the rejected mockup variants.
5. **Rooster** reviews the implementation for bugs, edge cases, and quality — read-only, reports findings, never edits.
6. **Jeremiah** verifies the feature in the Simulator from a real user's perspective.

## For small fixes and tweaks

Skip the full pipeline — implement directly, then have Rooster review before committing.

## Mockups

Jeff writes variants to `Mockups/`, which is **excluded from the app target**. They exist to be looked at in an Xcode Preview and then thrown away. Dan deletes the rejected variants as part of step 4; the chosen one gets hardened into a real view and its mockup file removed too. `Mockups/` should be empty between features.

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
