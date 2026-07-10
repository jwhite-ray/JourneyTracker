# JourneyTracker — Design System v1.2

**Status:** living document · owned by Jeff (design) · iOS · SwiftUI
**Scope:** this document passes **style only** — color, type, shape, layout, and the character rig. It does not define behavior, data models, units, or progress math. Those live in `docs/JourneyTracker_App_Concept.md`, which wins on any such question.

Every step you walk carries a wayfarer closer to the summit along the 1,800-mile road to Ember Spire. Faceted fantasy figures, parchment world, no gradients on characters — form comes from flat color facets.

> **v1.1 change log.** All proper nouns are now original (see the App Concept doc's naming section — no real-world IP). The v1.0 progress formula (`steps × stride`) has been **removed**: it specified behavior, which is out of this document's scope, and it contradicted the App Concept doc. Progress is driven by HealthKit `distanceWalkingRunning`.

> **v1.2 change log.** Added §07 "Waypoint & marker states" — the shared reached/next/upcoming/completed token language for journey maps, factored out of the three KAN-7 mockup variants in `Mockups/` so it's documented once regardless of which pin/badge shape the team picks.

---

## 01 · Brand principles

**Flat facets, never gradients.** Characters and scenery get volume from 2–3 flat color facets per shape (highlight top-left, shadow bottom-right) — no gradients, no soft shadows on figures.

**Faces speak without mouths.** Hard rule: characters have no mouth. Emotion is carried entirely by eyebrows, eyelids, posture, blush and props.

**Real miles, real myth.** Progress maps to the 1,800-mile Thistledown → Ember Spire route. Milestones are named waypoints (Crosswater, Silvergate, The Deepdelve…).

**Pixel accents, not pixel everything.** 8-bit sprite treatment is reserved for reward glyphs and badges on a strict grid. Characters and scenes stay faceted-vector.

---

## 02 · Color tokens

Authored in oklch; hex fallbacks given for iOS asset catalogs. **The token name is what code references** — never the display name, never a literal.

| Display name | Token | Hex | Use |
|---|---|---|---|
| Parchment | `bg/parchment` | `#E8DEC0` | app background |
| Ink | `ink` | `#37342B` | text, outlines |
| Meadow Green | `accent/primary` | `#5B8A4B` | primary, progress |
| Haven Blue | `accent/secondary` | `#3F6EA8` | links, secondary |
| Reward Gold | `accent/reward` | `#D6A64B` | badges, rewards |
| Ember Red | `accent/alert` | `#B23A2E` | streak risk, alert |
| Wayfarer Skin | `char/skin` | `#D8B58C` | faces, ears, feet |
| Cloak Brown | `char/cloak` | `#7A6A4F` | cloak / neutral prop |
| Card Cream | `surface/card` | `#F4EEDD` | card surfaces |
| Deepdark | `bg/dark` | `#12201A` | dark mode base |

### Deepdark (dark) mode

Swap `bg/parchment` → `#12201A`, `ink` → `#E6E2D3`, `surface/card` → `#1D3327`. **Accent hues (green, gold, blue, red) stay identical** — only surfaces and ink invert. Trigger by system appearance, or inside cave milestones such as The Deepdelve.

> Waypoint-driven appearance is flagged as an open architectural question in the App Concept doc. Don't implement the cave trigger until Jake resolves how it interacts with `JourneyTheme`.

---

## 03 · Typography

**Display — Cinzel.** Screen titles, milestone names, distance numerals. Weights 600/700/800. Never for body or anything under 15px.

**Body / UI — Nunito.** All UI, stats, settings. Weights 400/600/700/800. iOS fallback: SF Pro Rounded.

Bundle Cinzel + Nunito (both SIL Open Font License), or map to SF Pro Rounded (body) + a serif display. **Never render body copy in the display face.**

| Role | Face | Size | Sample |
|---|---|---|---|
| Display / Title | Cinzel 800 | 32pt | *The Long Road Begins* |
| Screen title | Cinzel 700 | 24pt | — |
| Stat numeral | Nunito 800 | 26pt | 4,213 |
| Body | Nunito 600 | 15pt | 1.8 miles to Crosswater |
| Caption | Nunito 600 | 12pt | — |
| Eyebrow / label | Nunito 700 | 11pt · +0.14em | TODAY |

---

## 04 · Character: the faceted wayfarer

One rig, re-posed and re-skinned. Each body part is a rounded shape holding three stacked layers: base fill, a top-left highlight facet, and a bottom-right shadow facet. **This is the entire "3D" trick — keep it consistent everywhere.**

Default character: **Wren**, a wayfarer of the small-folk.

**Construction order (back → front):** shadow ellipse → feet → back arm → staff → pack → body (cloak) → belt → ears → face circle → hood → eye whites → pupils → eyebrows

**Fixed proportions** (on a 180×216 box): head ⌀60 · hood 76×64 pentagon · body 90×68 r20 · arms 26×56 r13 · feet 24×38 · eye white ⌀16, pupil ⌀7. Big feet, no visible hands = the small-folk read.

**Facet recipe (per shape):**
1. base = mid tone
2. highlight = +10% L, clipped to the top-left
3. shadow = −12% L, clipped to the bottom-right

Clip each facet to the parent's rounded silhouette. In SwiftUI: `.clipShape(RoundedRectangle(...))` on a `ZStack`, with each facet a `Path` — the original CSS `clip-path: polygon(0 0, 100% 0, 100% 45%, 0 70%)` becomes a four-point `Path` in the shape's local coordinate space.

**Emotional states — brows + posture only, never a mouth:**

| State | Expression |
|---|---|
| Determined | brows angled in-down, forward lean |
| Worn out | heavy lids, drooped brows, hunch |
| Fresh start | raised brows, blush, mid-hop |

State is driven by daily activity: fresh in the morning or after hitting a goal, determined mid-walk, worn out when the streak is at risk or late in the day.

**Ship as a layered vector** — an SVG or SwiftUI shape stack, not a raster — so facet colors and brow/posture states can be swapped at runtime.

---

## 05 · Pixel iconography

Reward and stat glyphs only, drawn on a strict grid (6px cells, 12×12 default). No anti-aliasing, no outlines — color blocks alone. Export at 1× grid, then scale by **integer factors only** (2×/3×) to keep edges crisp.

Core glyphs: **Steps** · **Ember Spire** · **The Emberstone** (the journey's reward token)

---

## 06 · Journey map

Top-down parchment map. Dot-dash ink trail (8px on / 6px off — in SwiftUI, `StrokeStyle(lineWidth: 3, dash: [8, 6])`). Pin fill = the milestone's accent color, 3px ink stroke, 2px offset shadow. Segment lengths reflect real relative distances along the route.

Waypoints in order: Thistledown · Crosswater · Silvergate · The Deepdelve · Whisperwood · The Windmark · Whitewatch · Ember Spire

Their canonical distances live in the App Concept doc and ship as journey data — not as constants in this file or in view code.

---

## 07 · Core components

**Progress bar** — h22 · border 3 ink · radius 999 · fill `accent/primary` + hatch. Label reads `342 / 1,800 mi`.

**Buttons** — radius 12 · border 3 · fill `journey.theme.accentColorToken` + crisp 3pt ink stroke, no shadow (KAN-8 — the hard drop shadow read as a doubled border at button size). Press state: translate down 2pt, no shadow to collapse. Labels: "Start Journey," "View Map."

**Milestone badges** — earned: `accent/reward` border. Locked: dashed border, 60% opacity.

**Stat card** — radius 14 · border 2 · Cinzel numerals, Nunito labels. Eyebrow "TODAY," a step numeral, and a caption pairing distance with share-of-journey.

**Waypoint & marker states (KAN-7)** — the token/opacity language a journey map uses to tell reached from upcoming, regardless of whether a given screen renders waypoints as pins, badges, or dots. Pin/badge *shape* is still open pending the KAN-7 mockup direction; this table is the part that's shared across all of them:

| State | Fill | Stroke | Opacity | Notes |
|---|---|---|---|---|
| Reached / passed | `journey.theme.accentColorToken` | 3pt ink (2pt if a smaller badge) | 100% | Optional small ink checkmark/glyph. |
| Next (the single upcoming waypoint) | `journey.theme.accentColorToken`, or `accent/reward` for the badge/ring itself | 3pt ink + an `accent/reward` emphasis ring or larger scale | 100% | The only waypoint whose name label is always shown, not just on tap — there is ever exactly one "next." |
| Further unreached | none (outline only) | 2pt ink, dashed | 60% | Same locked language as milestone badges (§07). No name label by default. |
| Completed-journey final waypoint | `accent/reward` | 3pt ink | 100% | Marker (Wren) is parked here, posed "fresh" (raised brows, no forward lean) with an `accent/reward` ring or pixel glyph attached — must read as *stopped*, distinct from mid-route "determined"/"worn out" walking poses. |

Marker position is always continuous distance-weighted interpolation between the two bracketing waypoints — never snapped to the nearer one. At 0% it sits on the first waypoint; at 100% (or `isCompleted`) it's pinned to the last.

---

## 08 · Layout tokens

**Spacing scale (pt):** 4-pt base — 4 / 8 / 12 / 16 / 24 / 32

**Radii & strokes:**
- Cards — 14–16 radius, 2pt hairline border
- Buttons / bars — 12 / 999 radius, 3pt ink border
- Map frame — 18 radius, 3pt ink border
- Hard drop shadow — `.shadow(color: ink, radius: 0, x: 0, y: 4)` — **no blur**
- Character facets — no border, no shadow

---

## 09 · Developer handoff notes

**Progress.** `progress = min(1.0, journey.distanceAccumulated / journey.totalDistance)`, both meters, where `distanceAccumulated` comes from HealthKit `distanceWalkingRunning` via the shared delta-based update. Steps are a display stat only and never feed progress. See the App Concept doc — that document owns this.

**Waypoints.** Names and distances are journey data (bundled JSON or SwiftData records), seeded from the table in the App Concept doc. Never Swift literals in view code.

**Colors.** Ship as Asset Catalog colorsets keyed by token name, each with a light and a Deepdark variant. Views reference `Color("accent/primary")` or `journey.theme.accentColor` — never `Color.red`, never a hex literal.

**Character rig.** Layered vector, runtime-swappable facet colors and brow/posture states.

**Fonts.** Bundle Cinzel + Nunito, or map to SF Pro Rounded + a serif display. Never body copy in the display face.

**Pixel glyphs.** 1× grid, integer scaling only.

**Naming.** Every proper noun in this document is original to JourneyTracker. Do not reintroduce names from existing books, films, or games — see the App Concept doc's naming section.
