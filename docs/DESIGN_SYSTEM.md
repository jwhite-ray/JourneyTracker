# JourneyTracker — Design System v1.5

**Status:** living document · owned by Jeff (design) · iOS · SwiftUI
**Scope:** this document passes **style only** — color, type, shape, layout, and the character rig. It does not define behavior, data models, units, or progress math. Those live in `docs/JourneyTracker_App_Concept.md`, which wins on any such question.

Every step you walk carries a wayfarer closer to the summit along the 1,800-mile road to Ember Spire. Faceted fantasy figures, parchment world, no gradients on characters — form comes from flat color facets.

> **v1.1 change log.** All proper nouns are now original (see the App Concept doc's naming section — no real-world IP). The v1.0 progress formula (`steps × stride`) has been **removed**: it specified behavior, which is out of this document's scope, and it contradicted the App Concept doc. Progress is driven by HealthKit `distanceWalkingRunning`.

> **v1.2 change log.** Added §07 "Waypoint & marker states" — the shared reached/next/upcoming/completed token language for journey maps, factored out of the three KAN-7 mockup variants in `Mockups/` so it's documented once regardless of which pin/badge shape the team picks.

> **v1.3 change log.** Added §07 "Status stamp," "Kebab action menu," and "Destructive confirmation overlay" — the chosen KAN-10 lifecycle-status treatment (mockup Variant C, "Corner Stamp + Kebab Menu"), with one change from the mockup: the stamp renders straight, no rotation. Variants A ("text row") and B (their treatments) are dead; not documented.

> **v1.4 change log.** Added §07 "Catalog row," "Row status captions," and "Catalog empty-state CTA" — the chosen KAN-11 available-journeys treatment, a hybrid of mockup Variant B ("Compact Manifest," store page rows) and Variant A (empty state), with the empty-state CTA copy changed to "Start a Journey." One fix from the mockup: a paused row's directive copy must never truncate. Variant B's other-than-chosen elements and Variant C are dead; not documented.

> **v1.4.1 correction.** The v1.4 §07 "Catalog row" and "Catalog empty-state CTA" text was written from memory and drifted from the approved Variant B render/implementation. Corrected to match what the user actually approved and Dan actually built: the chip is a narrow accent sliver (~10×34, r6), not a 44×44 swatch; there is no separately-reserved 28pt gutter for a future marker (the sliver itself is the reserved slot); rows are free-standing cards (`surface/card`, r12, 2pt stroke, 8pt gaps, 14pt horizontal padding), not flat hairline-separated rows; the ACTIVE caption is trailing at 10pt, not beneath the metadata line at 11pt; empty-state headline/caption are 18pt/13pt, not 20pt/15pt; and the empty-state character is noted as an unbuilt placeholder rather than documented as if the "fresh start" pose already ships. The never-truncate paused-directive rule, Start pill spec, waypoint-clause omission, and "Start a Journey" CTA copy were correct in v1.4 and are unchanged.

> **v1.5 change log.** Added §07 "Stat tile grid" and "Reached-waypoint timeline" — the chosen KAN-14 journey-stats treatment (mockup Variant A, "Stat Tiles"), picked at Gate 2 with three amendments over the mockup: tile values render at one uniform size (no scale-down-to-fit a long value; it wraps instead), the map frame is unchanged from KAN-7 (no new frame/sizing shipped with this feature), and the days-on-road tile's label reads "DAYS ON JOURNEY." Variants B ("Quiet Ledger") and C ("Eyebrow Rows") are dead; not documented.

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

**Stat tile grid (KAN-14).** The journey map's derived-stats block (Started / Days on Journey / Avg. Pace / Projected Finish, or Finished on a completed journey), rendered as a 2×2 grid of §07 stat cards — same radius 14 · border 2 · eyebrow label + Cinzel numeral spec as above, one tile per stat. **Tile values render at one uniform size across the grid — never individually scaled down to fit.** A long value (e.g. a far-future projected-finish date) wraps within its tile instead of shrinking, so every tile in the grid reads at the same visual weight; no tile is allowed to look "louder" than its neighbors just because its value happens to be short. The days-on-road tile's eyebrow label is **"DAYS ON JOURNEY."** A tile whose stat is below the data floor (pace/projection, per the App Concept doc's Ruling 7) shows a muted "Not enough data yet" caption in place of a numeral rather than a blank or zeroed value. The map frame itself is unchanged from KAN-7 — this feature adds the tile grid and the reached-waypoint timeline below the existing map/progress bar, it does not resize or restyle the map.

**Reached-waypoint timeline (KAN-14).** The map's per-instance log of reached waypoints, below the stat tile grid: one row per reached waypoint, each with a tick dot on a connecting vertical ink rail (echoing the map's own dot-dash trail), the waypoint name, its date reached, and time taken since the previous waypoint. **Every row's tick renders filled and checked, with no exception** — presence in this log already means the waypoint was reached, so the tick communicates that fact uniformly. A waypoint crossed before crossing-tracking existed (no recorded `crossedAt`) is **never** shown with an empty or unchecked tick, which would visually contradict a log titled "reached" — instead its date line reads "date not recorded," and its time-taken line degrades the same way, as plain text. The tick is never the carrier of missing-data information; only the text is.

**Waypoint & marker states (KAN-7)** — the token/opacity language a journey map uses to tell reached from upcoming, regardless of whether a given screen renders waypoints as pins, badges, or dots. Pin/badge *shape* is still open pending the KAN-7 mockup direction; this table is the part that's shared across all of them:

| State | Fill | Stroke | Opacity | Notes |
|---|---|---|---|---|
| Reached / passed | `journey.theme.accentColorToken` | 3pt ink (2pt if a smaller badge) | 100% | Optional small ink checkmark/glyph. |
| Next (the single upcoming waypoint) | `journey.theme.accentColorToken`, or `accent/reward` for the badge/ring itself | 3pt ink + an `accent/reward` emphasis ring or larger scale | 100% | The only waypoint whose name label is always shown, not just on tap — there is ever exactly one "next." |
| Further unreached | none (outline only) | 2pt ink, dashed | 60% | Same locked language as milestone badges (§07). No name label by default. |
| Completed-journey final waypoint | `accent/reward` | 3pt ink | 100% | Marker (Wren) is parked here, posed "fresh" (raised brows, no forward lean) with an `accent/reward` ring or pixel glyph attached — must read as *stopped*, distinct from mid-route "determined"/"worn out" walking poses. |

Marker position is always continuous distance-weighted interpolation between the two bracketing waypoints — never snapped to the nearer one. At 0% it sits on the first waypoint; at 100% (or `isCompleted`) it's pinned to the last.

**Status stamp (KAN-10).** A wax-seal-style badge pinned to a journey card's top-trailing corner, reporting lifecycle status (Active / Paused / Completed) without occupying the card's primary content flow. Renders **straight — no rotation or tilt**, unlike the original mockup, which tilted it for a wax-seal read; the chosen direction keeps the card calm. Shape: `RoundedRectangle`, radius 8, filled `surface/card`. Label: eyebrow-style caps ("ACTIVE" / "PAUSED" / "COMPLETE"), Nunito 700, 10pt, +0.08em kerning, `ink`. Padding 9 horizontal / 5 vertical. No drop shadow (consistent with §07 buttons/§08 — a shadow at this scale reads as a doubled border).

Per-status stroke, 3pt unless noted:
- **Active** — `accent/primary` stroke.
- **Paused** — `ink` stroke at reduced opacity (the stamp itself is muted, not just its stroke color — treat the whole stamp at ~60% opacity to read as dormant against an Active card).
- **Completed** — `accent/reward` stroke, 4pt (the one status that steps up stroke weight), plus the §05 pixel Emberstone glyph (6×6 grid, strict cells, no anti-aliasing) inline before the label. This is the only status with an icon — it's the celebratory one and should read as an award, not a fourth text label.

**Kebab (•••) action menu (KAN-10).** Secondary lifecycle actions (Pause, Resume, Restart) collapse behind a single kebab button so the card surface stays to name, status, progress, and the primary "View Map" action. Kebab button: 32×32 square, radius 10, `surface/card` fill, 3pt `ink` stroke, centered `ellipsis` glyph.

Tapping opens an anchored dropdown below the kebab whose leading edge aligns to the kebab's leading edge and extends trailing (x = kebab.minX), clamped to stay ≥12pt from the screen's trailing edge: `surface/card` fill, radius 12, 3pt `ink` stroke, fixed width 190. Rows are label + leading icon, Nunito 600, 13pt, `ink`, 12pt horizontal / 9pt vertical padding, separated by a 1pt `ink`-at-15%-opacity hairline (no divider after the last row). A row representing an action currently unavailable (e.g. "Resume" while another journey is active) renders its full row — icon, label, text — at 40% opacity rather than being hidden, so the option's existence is never a surprise.

**Destructive confirmation overlay (KAN-10).** Reserved for irreversible, discard-language actions (e.g. Restart, which zeroes accumulated progress). Full-bleed dimmed scrim: `ink` at 45% opacity covering the whole screen/card context behind it. Centered card: max width 340, radius 16, `surface/card` fill, 3pt `ink` stroke, 20pt padding, content left-aligned. Header row pairs a warning glyph (SF Symbol `exclamationmark.triangle.fill` in `accent/alert`) with a serif title ("Restart *Journey Name*?"), Cinzel-register 700, 18pt, `ink`. Body copy states plainly what is lost and that it cannot be undone — Nunito 600, 14pt, `ink`. Footer is two buttons per the §07 button spec: **Cancel** (`surface/card` fill — visually recessive) and the destructive action (`accent/alert` fill, e.g. "Discard & Restart") — always in that left-to-right order, destructive action never defaulted/auto-focused.

**Catalog row (KAN-11).** The compact row used to list available journeys on the store/catalog screen (mockup Variant B, "Compact Manifest"), rendered as a free-standing card: `surface/card` fill, radius 12, 2pt `ink` stroke, 14pt horizontal internal padding, rows separated by an 8pt gap (not a hairline divider — the card edge already separates rows visually). Leading accent: a narrow vertical sliver, ~10×34, radius 6, filled `journey.theme.accentColorToken`, 2pt `ink` stroke — a plain color mark carrying the journey's identity, no artwork or glyph inside it. There is no separate reserved gutter for a future premium/featured marker; the sliver itself is the reserved slot — a later marker either replaces or is layered onto the sliver (e.g. swaps its fill, or adds a small glyph beside it). If a future marker ever needs more footprint than the sliver affords, that's a deliberate reflow to make at that time, not something pre-reserved today. Next, a leading-aligned two-line text stack: journey name (Nunito 700, 15pt, `ink`) on the first line, a metadata caption (Nunito 600, 12pt, `ink` at reduced opacity) on the second reading `distance · N waypoints` — the waypoint-count clause is omitted entirely (not shown as "0 waypoints" or a placeholder dash) when the count is 0, leaving just the distance. Trailing: a Start pill per the §07 button spec (radius 999, 3pt `ink` border, filled `journey.theme.accentColorToken`), right-aligned and vertically centered.

**Row status captions (KAN-11).** Inline, non-badge status language for catalog rows — distinct from the §07 status stamp used on journey cards elsewhere in the app. An active journey's row carries a trailing caption, near the row's trailing edge: "ACTIVE," Nunito 700, 10pt, kerning 0.8, `accent/primary`. A paused journey's row instead carries its paused directive (e.g. "Resume to keep this journey moving") beneath the metadata line, Nunito 600, 12pt, `ink` at reduced opacity. **The paused directive must never truncate.** It does not get a fixed single-line height with ellipsis truncation; let it wrap to a second line and let the row grow to fit rather than clip it. This is a deliberate departure from the row's otherwise-fixed single height — a paused row's height is intrinsic to its directive copy.

Both the "ACTIVE" caption and the paused row's trailing "PAUSED ›" marker (Nunito 700, 10pt, kerning 0.8, `ink` at reduced opacity, chevron indicating it leads somewhere) are not static labels — they're quiet, understated tappable controls that pop back to Your Journeys so the user can manage that journey's lifecycle from the catalog. Keep the visual treatment quiet (no button chrome, no fill, no border — text-and-chevron only) so the row still reads primarily as a catalog listing, but give each a minimum 44×44pt hit target and a VoiceOver label of "Active — manage on Your Journeys" / "Paused — manage on Your Journeys" respectively, per Jake's ruling.

**Catalog empty-state CTA (KAN-11).** Shown in place of the row list when no journeys exist yet (mockup Variant A). A centered column, vertically centered in the available space: a placeholder mark today (the character rig's "fresh start" pose per §04 is the intended long-term treatment but is not yet built as real art — implement the pose as soon as it exists rather than shipping the placeholder indefinitely) above a serif headline (Cinzel 700, 18pt, `ink`), a one-line supporting caption below it (Nunito 600, 13pt, `ink`), then a primary button per the §07 button spec labeled **"Start a Journey."** Since no journey exists yet to source a `journey.theme` accent from, the button fills `accent/primary`.

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
