# Notification content sheets

One CSV per journey: the waypoint, its mileage, which notification hook fires, the message templates, and the artwork asset. **These files are the canonical source for notification copy** — open them in Numbers or Excel to view/edit, but save back as CSV (they live in git).

Consumed by Phase 1 (KAN-33, milestone notifications); the `artwork_asset` column is consumed by the notification-artwork phase (KAN-34 epic).

## Columns

| Column | Meaning | Editable? |
|---|---|---|
| `hook` | When it fires: `waypoint_reached`, `journey_complete`, `percent_25/50/75` | yes (but hooks beyond `waypoint_reached`/`journey_complete` fire only once Phase 2 ships) |
| `order` | Waypoint order in the journey (blank for non-waypoint hooks) | reference only |
| `waypoint` | Waypoint name (blank for percent hooks) | reference only — canonical names live in the App Concept doc / seed data |
| `cumulative_miles` | Miles from start (blank for percent hooks) | reference only — authoritative distance lives in seed data |
| `title_template` | Notification title. Budget: **≤ 35 characters** after placeholder fill | yes — this is the point of the sheet |
| `body_template` | Notification body. Budget: **core message in first ~110 chars**; ~170 max | yes |
| `artwork_asset` | Asset-catalog name for the attached image. Convention: `notif_<journey>_<waypoint>` (e.g. `notif_windrise_millhollow`). Blank = no attachment yet | yes, once artwork exists |
| `notes` | Free-form | yes |

## Placeholders (filled by the app at fire time)

- `{character}` — the user's character name (never hardcode "Wren"; character selection is roadmapped)
- `{journey}` — journey name
- `{waypoint}` / `{next_waypoint}` — waypoint names
- `{miles_walked}` — cumulative distance walked, via `DistanceFormatter`
- `{miles_to_next}` — distance to the next waypoint, via `DistanceFormatter`
- `{miles_remaining}` — distance to journey end, via `DistanceFormatter`
- `{total_miles}` — the journey's total distance, via `DistanceFormatter`

All numbers are formatted by `DistanceFormatter` at fire time — never write literal mileage into a template.

## Rules

- **Past tense only** ("has reached", never "is arriving") — HealthKit background delivery can lag minutes to hours.
- **0-mile origin waypoints never notify** (KAN-14 Ruling 4) — they have no row here.
- **Original IP only** — copy and artwork alike (no real-world/franchise names).
- **Ember Spire's sheet is provisional** — its identity is being rethought under KAN-25; don't polish that copy until KAN-25 lands.
- **Every journey eventually gets waypoint rows.** A journey's development is complete only when it has waypoints, a map, and notification content (ruling 2026-07-14). Around the World's sheet carries only percent/complete rows *today* because its waypoints aren't authored yet — `waypoint_reached` rows get added when they are.
- Artwork must read at **thumbnail size** (collapsed notifications show a small square on the right); the expanded view shows it near full-width.
