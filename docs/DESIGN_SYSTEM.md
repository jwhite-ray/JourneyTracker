# JourneyTracker — Design System v1.9

**Status:** living document · owned by Jeff (design) · iOS · SwiftUI
**Scope:** this document passes **style only** — color, type, shape, layout, the character rig, and the faceted terrain/cartography system. It does not define behavior, data models, units, or progress math. Those live in `docs/JourneyTracker_App_Concept.md`, which wins on any such question.

Every step you walk carries a wayfarer closer to the summit along the 1,800-mile road to Ember Spire. Faceted fantasy figures, parchment world, no gradients on characters or terrain — form comes from flat color facets.

> **v1.1 change log.** All proper nouns are now original (see the App Concept doc's naming section — no real-world IP). The v1.0 progress formula (`steps × stride`) has been **removed**: it specified behavior, which is out of this document's scope, and it contradicted the App Concept doc. Progress is driven by HealthKit `distanceWalkingRunning`.

> **v1.2 change log.** Added §07 "Waypoint & marker states" — the shared reached/next/upcoming/completed token language for journey maps, factored out of the three KAN-7 mockup variants in `Mockups/` so it's documented once regardless of which pin/badge shape the team picks.

> **v1.3 change log.** Added §07 "Status stamp," "Kebab action menu," and "Destructive confirmation overlay" — the chosen KAN-10 lifecycle-status treatment (mockup Variant C, "Corner Stamp + Kebab Menu"), with one change from the mockup: the stamp renders straight, no rotation. Variants A ("text row") and B (their treatments) are dead; not documented.

> **v1.4 change log.** Added §07 "Catalog row," "Row status captions," and "Catalog empty-state CTA" — the chosen KAN-11 available-journeys treatment, a hybrid of mockup Variant B ("Compact Manifest," store page rows) and Variant A (empty state), with the empty-state CTA copy changed to "Start a Journey." One fix from the mockup: a paused row's directive copy must never truncate. Variant B's other-than-chosen elements and Variant C are dead; not documented.

> **v1.4.1 correction.** The v1.4 §07 "Catalog row" and "Catalog empty-state CTA" text was written from memory and drifted from the approved Variant B render/implementation. Corrected to match what the user actually approved and Dan actually built: the chip is a narrow accent sliver (~10×34, r6), not a 44×44 swatch; there is no separately-reserved 28pt gutter for a future marker (the sliver itself is the reserved slot); rows are free-standing cards (`surface/card`, r12, 2pt stroke, 8pt gaps, 14pt horizontal padding), not flat hairline-separated rows; the ACTIVE caption is trailing at 10pt, not beneath the metadata line at 11pt; empty-state headline/caption are 18pt/13pt, not 20pt/15pt; and the empty-state character is noted as an unbuilt placeholder rather than documented as if the "fresh start" pose already ships. The never-truncate paused-directive rule, Start pill spec, waypoint-clause omission, and "Start a Journey" CTA copy were correct in v1.4 and are unchanged.

> **v1.5 change log.** Added §07 "Stat tile grid" and "Reached-waypoint timeline" — the chosen KAN-14 journey-stats treatment (mockup Variant A, "Stat Tiles"), picked at Gate 2 with three amendments over the mockup: tile values render at one uniform size (no scale-down-to-fit a long value; it wraps instead), the map frame is unchanged from KAN-7 (no new frame/sizing shipped with this feature), and the days-on-road tile's label reads "DAYS ON JOURNEY." Variants B ("Quiet Ledger") and C ("Eyebrow Rows") are dead; not documented.

> **v1.6 change log.** Ported §07, Terrain & cartography — the visual vocabulary for rendering authored map regions (mountains, forests, rivers, lakes, ocean/coast, ground cover, trek path/roads, settlements) as faceted SwiftUI Canvas art, plus eight new `terrain/*` color tokens (merged into §02). This is Jira KAN-17, Phase 0 of the Faceted Map System epic, approved in a prior design pass and integrated here without redesign. §06 (Journey map) now points to §07 rather than duplicating its rendering detail, the same way it will once real terrain art ships. Because §07 was newly inserted, everything that followed it shifts down one: the section formerly called "§07 Core components" (and every changelog entry above referencing it by that number) is now **§08**, "§08 Layout tokens" is now **§09**, and "§09 Developer handoff notes" is now **§10**. Internal cross-references inside those sections were updated to match; the two places the approved terrain text pointed at "the button treatment" for its hard offset shadow were re-anchored to the §09 Layout-tokens hard-drop-shadow token instead, since buttons themselves lost their drop shadow in KAN-8 (§08) and no longer have one to borrow from.

> **v1.7 change log.** Codified four visual rulings Justin made at the KAN-18 Gate 1 render review (Phase 1 of the Faceted Map System epic), amending §07 (Terrain & cartography) and §08 (Core components) to match what Dan's `TerrainRenderer` / `TerrainGlyph` / `TerrainPalette` already draw on this branch: **(1)** the journey's destination waypoint now always shows its Cinzel name chip in every state — reached, next, or further-unreached — not only when it happens to be reached or "next." This **replaces** the prior §08 rule that "next" was the only waypoint always labelled; that wording is gone, not left alongside the new one. **(2)** The soft-form facet recipe (§07.1, and by reference §07.3.4 Lakes) is corrected to match the design PDF: the highlight/shadow clip is a thin, TAPERING mid-tone seam with non-parallel inner edges that pinches to zero before the far end of the shape — not a full-width hard diagonal. The exact bounding-box-fraction clip polygons Dan implemented are now documented. **(3)** River mouths now melt into the lake or ocean they drain into (§07.3.3, §07.5): the dark bank stroke tapers out before the receiving water and never caps across it, the body runs on into the receiver at the same water tone so fill continuity does the joining, and a sea mouth additionally blends toward the shallow-band tone — no hard edge, cap, or seam at any confluence. **(4)** One visual-grammar sentence added to §07.5: waypoint pins sit on the trek path line itself (the teardrop tip anchors to it), never floating beside it — Jake owns the underlying data rule in the App Concept doc; this is that rule's visual expression.

> **v1.8 change log.** Added §07.7 "World-edge border" (Gate 3 ruling, KAN-20): when the camera can see the authored world's edge, its bounds are traced with a visible border line — 3pt ink, matching the map-frame linework in §09 — drawn above terrain and below pins/chips, with the world edge itself ruled **square-cornered** (distinct from the UI map frame's 18pt radius). Outside the line is bare parchment letterbox, no terrain. Former §07.7 "Handoff notes" is renumbered §07.8; nothing in it changed.

> **v1.9 change log.** Ported the KAN-23 organic-detail pass (Justin's "the drawing trumps the rules" pilot-map ruling, App Concept doc) into §07: **(1)** §07.5's river-termination rule is rewritten — a river's source may now rise anywhere on land (an upland spring, partway up a range, or off-canvas), never in water, and it ends in a lake, at the coastline (melting per §07.3.3), or by exiting the map edge as an off-map drainage (drawn full-width to the world border and clipped there, §07.7); the prior wording ("a river always starts off-canvas or in a mountain range, and always ends either in a lake or abruptly at the coastline") is gone, not left alongside the new rule. Mouths still melt (§07.3.3) — an off-map exit is a clean edge-clip, not a melt. **(2)** New organic-detail visual language, purely stylistic (the underlying generator remains Jake's): §07.3.5 coasts gain multi-octave "organic displacement" (coves/headlands plus finer wobble, wander capped at ~2 real miles, pinned to zero at river mouths and shoreside villages, one 0–1 roughness knob); §07.3.3 rivers gain layered meanders (on-canvas drawn length up to ~1.5× the authored line, several true bends) and small tributaries (1.3–3 mi thin side-streams, melting into the main stem at a confluence with the same no-cap mouth recipe as §07.3.3's river mouths); §07.3.7 trek-path and road linework gain a subtle hand-wave (~0.12 mi amplitude, easing to zero at every waypoint) so traced segments never render ruler-straight. **(3)** §07.3.1 notes that short ranges/hill-chains (15–300 mi, the App Concept doc's KAN-23-loosened bound) currently render with the same mountain glyph at lower stature — a dedicated hills glyph stays an open future design option, not shipped here. **(4)** §07.5's "villages sit next to water" is downgraded from a hard placement rule to a design **preference**: the App Concept doc's ≤40-mile settlement cap is a sanity guard against absurd inland distance, not an aesthetic mandate, so a legitimate inland market or road town is not a violation.

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

### Terrain & water tokens

Added for the faceted cartography system (§07). Terrain tokens are **material colors, not UI colors** — they never appear on chrome, only inside the map Canvas. Each hex below is the shape's *mid tone*; the facet recipe in §07.1 derives the highlight and shadow tones from it at render time, same as the character rig, so only one hex per token needs to ship.

| Display name | Token | Hex | Use |
|---|---|---|---|
| Fjord Blue | `terrain/water` | `#4C7EA6` | rivers, lakes, ocean fill — the single hue that re-tints the whole map |
| Pine Canopy | `terrain/forest` | `#3F6B3C` | conifer canopy facets |
| Cairn Grey | `terrain/stone` | `#8C8574` | mountain body facets |
| Frost Cap | `terrain/snow` | `#EDE8DC` | snow-cap facets on scattered tall peaks |
| Dune Tan | `terrain/sand` | `#D9C08A` | dune mounds, desert ground cover |
| Plains Wash | `terrain/grass` | `#9CAD5E` | plains ground-cover wash + grass tufts |
| Marsh Olive | `terrain/marsh` | `#748C56` | marsh ground-cover blob + reed strokes |
| Roof Terracotta | `terrain/roof` | `#B65C3F` | settlement roof facets |

`terrain/water` is deliberately a distinct hue from `accent/secondary` (Haven Blue) — the map's water reads as *material*, the UI's blue reads as *interactive*. Keeping them separate means re-tinting the map for a new biome never accidentally re-tints links and buttons.

### Deepdark (dark) mode

Swap `bg/parchment` → `#12201A`, `ink` → `#E6E2D3`, `surface/card` → `#1D3327`. **Accent hues (green, gold, blue, red) stay identical** — only surfaces and ink invert. Trigger by system appearance, or inside cave milestones such as The Deepdelve.

**Terrain tokens follow the same rule as accents: hue stays put.** A cave-biome map (e.g. inside The Deepdelve) is a *reskin*, not a recolor of facet geometry — shift only lightness/hue on the existing `terrain/*` tokens (darken `terrain/stone` and `terrain/water` roughly the way a shadow facet does, dim `terrain/grass`/`terrain/sand` toward the surrounding dark parchment), never touch the shape recipes in §07.3. `terrain/snow` and `terrain/sand` simply won't appear in an underground region — that's an authoring choice for the region record, not a token override.

> Waypoint-driven appearance is flagged as an open architectural question in the App Concept doc. Don't implement the cave trigger — for characters or terrain — until Jake resolves how it interacts with `JourneyTheme`.

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

**This section covers the trail line and waypoint pins.** What sits *underneath* them — the faceted mountains, forests, rivers, lakes, coastline, ground cover, roads, and settlements that make the map a place instead of a line on parchment — is specified in full in §07, Terrain & cartography. The dot-dash trail above and the trek-path recipe in §07.3.7 are the same stroke; §07 just gives it a name in the fixed draw order.

---

## 07 · Terrain & cartography

Eight terrain elements, one fixed vocabulary, drawn back-to-front in a strict order every time. This section is visual style only: facet geometry, sizes, color tokens, and placement *look* (what reads as "right"). The map's actual coordinate space, region-record data model, scatter-generator algorithm, and camera/zoom behavior are Jake's — see the App Concept doc's map model. A map here is always **authored regions rendered per the App Concept doc's map model**; this section only says what each region type looks like once rendered.

No Tolkien or other real-world proper nouns anywhere on a map — waypoints, regions, and any future named landmark follow the naming rules in the App Concept doc (Ember Spire, Thistledown, and their kin only).

### 07.1 · The terrain facet rule

Terrain shares the character rig's core trick (§04) with one addition: **angular forms split down the center ridge; soft forms use the corner-clip.**

- **Angular** (mountains, conifers): the shape's silhouette splits along its own ridge line into a light half and a dark half — highlight facet (+8–10% L) on the side toward the top-left light source, shadow facet (−12% L) on the far side. This is a ridge split, not a corner clip.
- **Soft** (lakes, dunes, marsh blobs): use the character rig's corner-clip — a highlight facet clipped near the top of the shape, a shadow facet clipped near the bottom, both within the shape's own bounding box. **The two facets' inner edges are not parallel.** They cross near one side of the shape and pull apart near the other, so the mid-tone base band visible between them is a thin seam that **tapers** across the shape and pinches out to nothing before the far end — never a full-width hard diagonal running the whole silhouette (that earlier reading was wrong; see the Gate 1 ruling below). As bounding-box fractions (origin `0,0` top-left, `1,1` bottom-right): highlight = `polygon(0 0, 100% 0, 100% 42%, 0 66%)`, shadow = `polygon(100% 38%, 100% 100%, 18% 100%, 0 74%)`. The mid band is widest — about 8% of the shape's height — at the side where the two polygons sit farthest apart, narrowing to zero at the opposite end. This is the kit's clip recipe; §07.3.4 (Lakes) is the primary place it's seen, but it governs every "soft" shape this rule lists.
- Every shape still gets **flat facets only** — 2–3 stacked `Path` fills per glyph, no gradients, no blur, no soft shadows. Mountains additionally get a **hard offset shadow** (a second, darker copy of the triangle, drawn first, nudged down-right) rather than a shadow facet on the ground beneath them — this is the one place terrain uses an offset-shadow trick, borrowed from the hard drop shadow token defined in §09 (Layout tokens) rather than expressed as a facet. (Buttons themselves no longer carry a drop shadow as of KAN-8 — see §08 — so this note anchors to the layout token, not to the button treatment.)
- Light direction is fixed top-left across the entire map, matching the character rig — never per-glyph.

### 07.2 · Terrain color tokens

Full token table lives in §02 under "Terrain & water tokens." The short version: eight tokens (`terrain/water`, `terrain/forest`, `terrain/stone`, `terrain/snow`, `terrain/sand`, `terrain/grass`, `terrain/marsh`, `terrain/roof`), each a single mid-tone hex that the §07.1 facet rule lightens/darkens at render time. `terrain/water` is the one hue used for every river, lake, and ocean on a map — re-tint that single token and the whole map's water shifts together, which is what makes a seasonal or biome reskin a one-line change instead of a repaint. Reskins (autumn palette, a cave biome, a desert region) shift only the lightness/hue of these tokens — **facet geometry in §07.3 never changes.**

### 07.3 · Element anatomy

Sizes are logical points, meant for iPhone screens; all geometry below is expressed as a shape-stack description you'd hand to a SwiftUI `Canvas` draw pass (`context.fill(Path(...), with: .color(...))` per facet), not as per-glyph SwiftUI views — a map may hold hundreds of glyphs and a `Canvas` context is what keeps that cheap.

**07.3.1 · Mountains** (~16–52pt tall)
Bottom-anchored triangle. Ridge split down the center: `terrain/stone` base, highlight half toward the light, shadow half away from it. A second, fully-dark copy of the same triangle sits behind it, offset down-right, as a hard flat shadow (no blur — same rule as the hard drop shadow token in §09, Layout tokens). On a scattered few of the *tallest* peaks only, add a snow cap: the same two-facet ridge-split triangle in `terrain/snow`, sized to ~46% of the peak's width and pinned to its apex. Not every peak gets one — snow caps are the exception, not the rule, or the range reads as uniformly white.

A **short range or hill-chain** (15–300 real miles long, the App Concept doc's KAN-23-loosened bound) currently renders with this same mountain glyph, just at a lower stature and lighter scatter than a great massif — there is no separate hills glyph yet; a dedicated, lower/rounder hill glyph remains an open design option for a future pass, not something this pass ships.

**07.3.2 · Conifers / forests** (~10–26pt tall)
Short ink trunk + a ridge-split triangle canopy in `terrain/forest`. A single conifer is barely a glyph — the forest is the unit. See §07.4 for how many and how they're arranged. An autumn or other seasonal reskin swaps the canopy's green triad for a gold/rust triad without changing the triangle geometry.

**07.3.3 · Rivers**
One centerline path, stroked three times in the same pass, thickest-to-thinnest: a dark bank stroke (13pt, darkened `terrain/water`), the water body (9pt, `terrain/water`), and a thin highlight ribbon (3pt, lightened `terrain/water`) nudged up-left off the centerline — the ribbon is the river's own highlight facet, just expressed as an offset stroke instead of a clipped fill. Round caps throughout. Taper the stroke wider toward the mouth (lake or coastline) than the source, so the river visibly reads as flowing downhill/downstream rather than being a uniform ribbon.

**Mouths melt, they never cap.** Where a river meets a lake or the ocean, the join must read as one continuous body of water, not two materials butted against each other. The dark bank stroke tapers away to nothing over the last stretch before the receiving water and never caps across it — by the time the river's body reaches the shoreline, the bank simply isn't there anymore. The body itself runs a short way past its authored end, into the receiving water, on the exact same `terrain/water` tone the receiver is filled with at that point — it's fill continuity, not a drawn edge, that makes the join, so there is no hard edge, cap, or seam at a confluence. At a **sea** mouth, the body's tone additionally blends toward the pale shallow-band tone (§07.3.5) over that same final stretch, since that's the water it's actually meeting there; a **freshwater** (lake) mouth needs no such blend, since it's already melting into the lake's own base fill. Water is one continuous material wherever it meets itself.

**Meanders and tributaries (KAN-23 organic pass).** A river's centerline carries layered meander detail, not one lazy curve: the drawn path snakes through several true bends along its length, and its total on-canvas length runs up to roughly **1.5× the authored straight-line distance** — enough wander to read as a real river finding its way across terrain, not a ruler bowed slightly. A river may also throw off a handful of **tributaries**: thin side-streams, roughly 1.3–3 miles long, drawn as a narrower version of the same three-stroke recipe above (bank/body/highlight, all scaled down together), always shown flowing *into* the main stem, never the reverse. Where a tributary reaches the main river, it melts into it at the confluence using the exact same no-cap mouth recipe described above — the dark bank tapers away, the body runs on in the receiver's tone — there is no separate "tributary joint" treatment; a tributary confluence and a river's own mouth are the same visual event at a smaller scale.

**07.3.4 · Lakes**
An asymmetric-radius blob (never a perfect circle/ellipse) in `terrain/water`, corner-clip facets per §07.1's tapering-seam recipe — a thin mid-tone band that narrows and pinches out before the far end, never a full-width hard diagonal. A pale ~2.5pt shoreline rim (lightened `terrain/water`, near `terrain/snow`) traces the blob's edge as foam/shallows. A tarn variant is small and round; an inlet variant is wide and shallow with a heavier shadow facet. Where a river drains into a lake, the two melt together per §07.3.3's mouth recipe — see there.

**07.3.5 · Ocean / coast**
Never a gradient. Three stacked depth bands: the coastline silhouette itself, then two more copies of that same path offset inland and progressively lightened — each a flat `terrain/water` fill at a different lightness, no blend between them. A pale surf stroke (lightened `terrain/water`, thin, matching the lake shoreline rim) traces the true coastline on top of the bands. Coastline paths curve inward for bays, outward for headlands — never a straight edge.

**Organic coastline displacement (KAN-23 organic pass).** The coastline silhouette itself (not just its depth-band copies) carries multi-octave displacement along its length — several layered noise frequencies stacked so the line reads as a mix of broad coves and headlands plus finer wobble, rather than one smooth wave. Wander off the authored line is capped at roughly **2 real miles** in either direction, so displacement adds organic roughness without silently redrawing the coastline's authored shape. Displacement is **pinned to zero** — the authored line and the displaced line coincide exactly — at river mouths and at shoreside villages, so a river's melt-recipe join (above) and a village's water-adjacency both land on geography that actually matches what was authored there, never on a wandering approximation of it. A single **roughness knob**, 0–1, scales how much of the capped displacement is applied — 0 renders the authored line as drawn, 1 uses the full ~2-mile wander — the same spirit as the density/jitter/feather knobs in §07.4.

**07.3.6 · Ground cover** (plains / dunes / marsh)
- *Plains:* a low-opacity `terrain/grass` wash filling the region, plus small triangle grass tufts scattered across it (same scatter logic as forests, at a lower density — texture, not a forest).
- *Dunes:* overlapping half-ellipse mounds in `terrain/sand`, each ridge-split into a windward highlight facet and a lee (downwind) shadow facet.
- *Marsh:* a muted `terrain/marsh` blob (corner-clip facets, same as a lake) with small pill-shaped water glints and a few leaning reed strokes in `terrain/marsh`'s shadow tone. Marsh draws over plains ground cover and under rivers in the fixed order (§07.5).

**07.3.7 · Trek path & roads**
The trek path is the same ink dot-dash stroke defined in §06: `StrokeStyle(lineWidth: 3, dash: [8, 6])`, round caps — it's drawn once, as terrain, and §06's map view is just the camera looking at it. A plain road is one solid 3pt ink stroke; a major road is two parallel 3pt ink strokes. All three share the ink token — none of them use a terrain color.

All three also carry a subtle **hand-wave** displacement (KAN-23 organic pass) along their centerline — roughly **±0.12 mile amplitude** — so a traced segment never renders as a perfectly straight ruler-line. The wave eases to **zero amplitude exactly at every waypoint**, so pins still anchor cleanly to the path per §07.5 rather than the path wandering out from under them right where it matters most.

**07.3.8 · Settlements**
A village is a tight cluster of 3–5 tiny homes (~11–16pt each), each home a cream wall (`surface/card`) + a faceted roof in `terrain/roof` (ridge-split, per §07.1) + a 1–2pt ink border, base-anchored like the mountains. Clusters are small enough to read as "a place," not a scatter — see §07.4 for why settlements don't follow the same feathered-mass treatment as ranges and forests.

Waypoint pins and their Cinzel name chips (§06) are not part of this vocabulary — they're UI, not terrain, and always draw last, above every element in §07.5's order. Pin body state (reached/next/upcoming) and which pins carry a static name chip — always the destination, always the single "next" — are specified in §08's "Waypoint & marker states," not here.

### 07.4 · The scatter aesthetic — hard contract

> Ranges, forests, and villages are **soft-edged masses of many tiny jittered glyphs** — never rows, never rectangles, never a handful of large icons standing in for a whole forest or range. Every glyph in a mass is small enough that the mass reads as *texture*, not as a collection of individually-noticed objects.

This is non-negotiable across every element that scatters (mountains, forests; settlements scatter too, just at a much smaller count):

- **Jitter.** Position and size are both randomized per glyph within the region — no glyph sits on a grid, no two glyphs are identically sized.
- **Feather.** Density and glyph size taper from the region's center outward: denser and larger near the center, sparser and smaller toward the rim. A range or forest fades out, it doesn't stop.
- **Density.** Moderate, not packed — mountains and settlements in particular should feel like there's breathing room between glyphs, not a solid wall of triangles or roofs.
- **Count.** A forest region is on the order of 30–50 conifers scattered across a soft elliptical area. A settlement is 3–5 homes — deliberately far too few to feather; a village is a cluster, not a mass, and reads as a place rather than a texture.
- **Draw order within a scatter:** nearer (lower on screen) glyphs draw on top of farther ones, same as the region-level draw order in §07.5 — this alone avoids needing per-glyph z-index bookkeeping.

The generator that actually produces jittered/feathered placement from a region record is Jake's (App Concept doc); this contract is what its output must *look like* regardless of how it's implemented.

### 07.5 · Placement look-rules

These are visual grammar — how elements relate to each other on the page — not the data model that enforces them:

- Rivers meander: alternating curves, never a straight line — see §07.3.3 for the fuller layered-meander and tributary treatment. **A river's source may rise anywhere on land** — an upland spring, partway up a mountain range, or off-canvas — the only rule a source obeys is that it never starts *in* water (KAN-23; this supersedes the earlier "a river always starts off-canvas or in a mountain range" wording, which is gone, not left alongside it). **A river ends one of three ways**: in a lake, at the coastline (melting into it per §07.3.3's mouth recipe), or by exiting the authored map edge as an **off-map drainage** — drawn at full width all the way to the world border and clipped there (§07.7), rather than tapering to a point mid-canvas. A river never appears to continue under an ocean fill mid-land.
- At any confluence — river into lake, river into ocean, river into a tributary, or water meeting itself anywhere on the map — the join **melts** per §07.3.3's mouth recipe: no hard edge, cap, or seam where two water fills meet. An off-map exit is the one exception: it's a clean edge-clip at the world border, not a melt — there's no receiving water there to melt into.
- Roads and the trek path stay on land. They never cross a lake or ocean fill.
- Villages **prefer** to sit near water — a river bank, a lake shore, or a coastline — as a design preference, not a hard placement rule (KAN-23). The App Concept doc's ≤40-mile settlement-to-water cap is a sanity guard against a village placed absurdly far inland, not an aesthetic "must hug the shore" mandate — a legitimate market or road town sited well inland (up to that cap) is not a violation of this look-rule, it's geography the preference simply doesn't happen to apply to.
- Waypoint pins sit **on** the trek path line itself — the teardrop tip anchors to the path, never floating beside it. (The App Concept doc owns the data rule that puts waypoints on the path; this is that rule's visual expression.)
- Waypoint pins and their Cinzel chips (§06) sit above every terrain element, always, regardless of what's underneath them. See §08's "Waypoint & marker states" for which pins carry a name chip by default — the destination waypoint always does, alongside whichever single waypoint is currently "next."

### 07.6 · Fixed draw order

Back to front, always, no exceptions:

**ocean/coast → ground cover (plains/dunes/marsh) → lakes → rivers → forests → mountains → roads/trek path → settlements → world-edge border → labels/pins**

Respecting this order is what lets a map be an unordered bag of region records with no per-element z-index to maintain — draw them in this sequence and it's always correct.

### 07.7 · World-edge border (Gate 3 ruling, KAN-20)

When the camera can see the edge of the authored world — the full-journey overview, or a pan that reaches a map boundary — trace the authored bounds with a visible border line, so the world's edge reads as a deliberate edge of the page, not terrain that simply runs out. This is linework, styled to match the existing frame language rather than inventing a new stroke: same weight and token as the map frame in §09 — **3pt `ink` border**. The UI map frame's **18pt radius belongs to that frame** (the rounded chrome around the map viewport), not to this line. The world edge itself is **square-cornered**: the authored world is an authored rectangle of content, not a rounded card, and a hard corner reads as "the drawn world stops here," legible as a distinct thing from the rounded UI viewport it sits inside.

Draw order: above every terrain element in §07.6's sequence (last, after settlements) and below labels/pins — waypoint pins and their chips still draw on top of everything, including this line, per §07.5/§07.6.

Outside the line is bare `bg/parchment` letterbox — no terrain, no fill, nothing rendered. The renderer already clips terrain to the authored bounds; this border only makes that existing clip edge visible.

**Deepdark.** Like the trek path and every other piece of terrain linework, the border is drawn in the `ink` token — it inverts with the rest of Deepdark's linework (§02) automatically, never a fixed literal.

### 07.8 · Handoff notes

**Rendering.** SwiftUI `Canvas` draw passes only — shape stacks per glyph, not a view per glyph. A forest of 40 conifers is 40 small `Path` fills inside one `Canvas`, never 40 `ConiferView` instances in a `ForEach`.

**Colors.** Asset-catalog token names only (`terrain/water`, `terrain/forest`, etc., per §02) — never a literal, never an inline hex, same rule as everywhere else in this doc.

**No gradients, no blur, ever.** Depth on terrain comes entirely from stacked flat facets and, on mountains only, a hard offset shadow — never a `LinearGradient`, never `.blur()`.

**Static.** Terrain has no animation of any kind. Pan/zoom camera interaction is planned separately (a later phase in the App Concept doc) and is a camera change, not a terrain change — the glyphs themselves never move or animate.

**Sits beside the character rig, not on top of it.** Terrain and the wayfarer are two independent faceted systems sharing one facet rule and one light direction — a character standing on a map is a compositing question for the view, not a terrain concern.

---

## 08 · Core components

**Progress bar** — h22 · border 3 ink · radius 999 · fill `accent/primary` + hatch. Label reads `342 / 1,800 mi`.

**Buttons** — radius 12 · border 3 · fill `journey.theme.accentColorToken` + crisp 3pt ink stroke, no shadow (KAN-8 — the hard drop shadow read as a doubled border at button size). Press state: translate down 2pt, no shadow to collapse. Labels: "Start Journey," "View Map."

**Milestone badges** — earned: `accent/reward` border. Locked: dashed border, 60% opacity.

**Stat card** — radius 14 · border 2 · Cinzel numerals, Nunito labels. Eyebrow "TODAY," a step numeral, and a caption pairing distance with share-of-journey.

**Stat tile grid (KAN-14).** The journey map's derived-stats block (Started / Days on Journey / Avg. Pace / Projected Finish, or Finished on a completed journey), rendered as a 2×2 grid of §08 stat cards — same radius 14 · border 2 · eyebrow label + Cinzel numeral spec as above, one tile per stat. **Tile values render at one uniform size across the grid — never individually scaled down to fit.** A long value (e.g. a far-future projected-finish date) wraps within its tile instead of shrinking, so every tile in the grid reads at the same visual weight; no tile is allowed to look "louder" than its neighbors just because its value happens to be short. The days-on-road tile's eyebrow label is **"DAYS ON JOURNEY."** A tile whose stat is below the data floor (pace/projection, per the App Concept doc's Ruling 7) shows a muted "Not enough data yet" caption in place of a numeral rather than a blank or zeroed value. The map frame itself is unchanged from KAN-7 — this feature adds the tile grid and the reached-waypoint timeline below the existing map/progress bar, it does not resize or restyle the map.

**Reached-waypoint timeline (KAN-14).** The map's per-instance log of reached waypoints, below the stat tile grid: one row per reached waypoint, each with a tick dot on a connecting vertical ink rail (echoing the map's own dot-dash trail), the waypoint name, its date reached, and time taken since the previous waypoint. **Every row's tick renders filled and checked, with no exception** — presence in this log already means the waypoint was reached, so the tick communicates that fact uniformly. A waypoint crossed before crossing-tracking existed (no recorded `crossedAt`) is **never** shown with an empty or unchecked tick, which would visually contradict a log titled "reached" — instead its date line reads "date not recorded," and its time-taken line degrades the same way, as plain text. The tick is never the carrier of missing-data information; only the text is.

**Waypoint & marker states (KAN-7)** — the token/opacity language a journey map uses to tell reached from upcoming, regardless of whether a given screen renders waypoints as pins, badges, or dots. Pin/badge *shape* is still open pending the KAN-7 mockup direction; this table is the part that's shared across all of them. Whatever shape ships, it draws above the terrain layer beneath it — labels and pins are always last in §07's fixed draw order (§07.6); this table only governs the states of the pins themselves, not what's underneath them:

| State | Fill | Stroke | Opacity | Notes |
|---|---|---|---|---|
| Reached / passed | `journey.theme.accentColorToken` | 3pt ink (2pt if a smaller badge) | 100% | Optional small ink checkmark/glyph. |
| Next (the single upcoming waypoint) | `journey.theme.accentColorToken`, or `accent/reward` for the badge/ring itself | 3pt ink + an `accent/reward` emphasis ring or larger scale | 100% | One of two waypoints whose name label is always shown, not just on tap — the other is the destination (see below). There is ever exactly one "next." |
| Further unreached | none (outline only) | 2pt ink, dashed | 60% | Same locked language as milestone badges (§08). No name label by default — **except** the destination waypoint, which always shows its chip even while further-unreached (see below). |
| Completed-journey final waypoint | `accent/reward` | 3pt ink | 100% | Marker (Wren) is parked here, posed "fresh" (raised brows, no forward lean) with an `accent/reward` ring or pixel glyph attached — must read as *stopped*, distinct from mid-route "determined"/"worn out" walking poses. |

**Destination label rule (Gate 1 ruling, KAN-18).** The journey's destination waypoint — the final one, e.g. Ember Spire — always shows its Cinzel name chip, in every state: reached, next, or further-unreached. This replaces the earlier rule that "next" was the *only* waypoint always labelled; now next **and** the destination both are, and there is no longer a state in which the destination's name is tap-to-reveal. The chip is additive only — it never changes the destination's pin *body*, which still follows its row above exactly like any other waypoint in that state (an unreached destination keeps the dashed-outline, 60%-opacity treatment from the "Further unreached" row; its name chip simply floats above that outline instead of being withheld).

Marker position is always continuous distance-weighted interpolation between the two bracketing waypoints — never snapped to the nearer one. At 0% it sits on the first waypoint; at 100% (or `isCompleted`) it's pinned to the last.

**Status stamp (KAN-10).** A wax-seal-style badge pinned to a journey card's top-trailing corner, reporting lifecycle status (Active / Paused / Completed) without occupying the card's primary content flow. Renders **straight — no rotation or tilt**, unlike the original mockup, which tilted it for a wax-seal read; the chosen direction keeps the card calm. Shape: `RoundedRectangle`, radius 8, filled `surface/card`. Label: eyebrow-style caps ("ACTIVE" / "PAUSED" / "COMPLETE"), Nunito 700, 10pt, +0.08em kerning, `ink`. Padding 9 horizontal / 5 vertical. No drop shadow (consistent with §08 buttons/§09 — a shadow at this scale reads as a doubled border).

Per-status stroke, 3pt unless noted:
- **Active** — `accent/primary` stroke.
- **Paused** — `ink` stroke at reduced opacity (the stamp itself is muted, not just its stroke color — treat the whole stamp at ~60% opacity to read as dormant against an Active card).
- **Completed** — `accent/reward` stroke, 4pt (the one status that steps up stroke weight), plus the §05 pixel Emberstone glyph (6×6 grid, strict cells, no anti-aliasing) inline before the label. This is the only status with an icon — it's the celebratory one and should read as an award, not a fourth text label.

**Kebab (•••) action menu (KAN-10).** Secondary lifecycle actions (Pause, Resume, Restart) collapse behind a single kebab button so the card surface stays to name, status, progress, and the primary "View Map" action. Kebab button: 32×32 square, radius 10, `surface/card` fill, 3pt `ink` stroke, centered `ellipsis` glyph.

Tapping opens an anchored dropdown below the kebab whose leading edge aligns to the kebab's leading edge and extends trailing (x = kebab.minX), clamped to stay ≥12pt from the screen's trailing edge: `surface/card` fill, radius 12, 3pt `ink` stroke, fixed width 190. Rows are label + leading icon, Nunito 600, 13pt, `ink`, 12pt horizontal / 9pt vertical padding, separated by a 1pt `ink`-at-15%-opacity hairline (no divider after the last row). A row representing an action currently unavailable (e.g. "Resume" while another journey is active) renders its full row — icon, label, text — at 40% opacity rather than being hidden, so the option's existence is never a surprise.

**Destructive confirmation overlay (KAN-10).** Reserved for irreversible, discard-language actions (e.g. Restart, which zeroes accumulated progress). Full-bleed dimmed scrim: `ink` at 45% opacity covering the whole screen/card context behind it. Centered card: max width 340, radius 16, `surface/card` fill, 3pt `ink` stroke, 20pt padding, content left-aligned. Header row pairs a warning glyph (SF Symbol `exclamationmark.triangle.fill` in `accent/alert`) with a serif title ("Restart *Journey Name*?"), Cinzel-register 700, 18pt, `ink`. Body copy states plainly what is lost and that it cannot be undone — Nunito 600, 14pt, `ink`. Footer is two buttons per the §08 button spec: **Cancel** (`surface/card` fill — visually recessive) and the destructive action (`accent/alert` fill, e.g. "Discard & Restart") — always in that left-to-right order, destructive action never defaulted/auto-focused.

**Catalog row (KAN-11).** The compact row used to list available journeys on the store/catalog screen (mockup Variant B, "Compact Manifest"), rendered as a free-standing card: `surface/card` fill, radius 12, 2pt `ink` stroke, 14pt horizontal internal padding, rows separated by an 8pt gap (not a hairline divider — the card edge already separates rows visually). Leading accent: a narrow vertical sliver, ~10×34, radius 6, filled `journey.theme.accentColorToken`, 2pt `ink` stroke — a plain color mark carrying the journey's identity, no artwork or glyph inside it. There is no separate reserved gutter for a future premium/featured marker; the sliver itself is the reserved slot — a later marker either replaces or is layered onto the sliver (e.g. swaps its fill, or adds a small glyph beside it). If a future marker ever needs more footprint than the sliver affords, that's a deliberate reflow to make at that time, not something pre-reserved today. Next, a leading-aligned two-line text stack: journey name (Nunito 700, 15pt, `ink`) on the first line, a metadata caption (Nunito 600, 12pt, `ink` at reduced opacity) on the second reading `distance · N waypoints` — the waypoint-count clause is omitted entirely (not shown as "0 waypoints" or a placeholder dash) when the count is 0, leaving just the distance. Trailing: a Start pill per the §08 button spec (radius 999, 3pt `ink` border, filled `journey.theme.accentColorToken`), right-aligned and vertically centered.

**Row status captions (KAN-11).** Inline, non-badge status language for catalog rows — distinct from the §08 status stamp used on journey cards elsewhere in the app. An active journey's row carries a trailing caption, near the row's trailing edge: "ACTIVE," Nunito 700, 10pt, kerning 0.8, `accent/primary`. A paused journey's row instead carries its paused directive (e.g. "Resume to keep this journey moving") beneath the metadata line, Nunito 600, 12pt, `ink` at reduced opacity. **The paused directive must never truncate.** It does not get a fixed single-line height with ellipsis truncation; let it wrap to a second line and let the row grow to fit rather than clip it. This is a deliberate departure from the row's otherwise-fixed single height — a paused row's height is intrinsic to its directive copy.

Both the "ACTIVE" caption and the paused row's trailing "PAUSED ›" marker (Nunito 700, 10pt, kerning 0.8, `ink` at reduced opacity, chevron indicating it leads somewhere) are not static labels — they're quiet, understated tappable controls that pop back to Your Journeys so the user can manage that journey's lifecycle from the catalog. Keep the visual treatment quiet (no button chrome, no fill, no border — text-and-chevron only) so the row still reads primarily as a catalog listing, but give each a minimum 44×44pt hit target and a VoiceOver label of "Active — manage on Your Journeys" / "Paused — manage on Your Journeys" respectively, per Jake's ruling.

**Catalog empty-state CTA (KAN-11).** Shown in place of the row list when no journeys exist yet (mockup Variant A). A centered column, vertically centered in the available space: a placeholder mark today (the character rig's "fresh start" pose per §04 is the intended long-term treatment but is not yet built as real art — implement the pose as soon as it exists rather than shipping the placeholder indefinitely) above a serif headline (Cinzel 700, 18pt, `ink`), a one-line supporting caption below it (Nunito 600, 13pt, `ink`), then a primary button per the §08 button spec labeled **"Start a Journey."** Since no journey exists yet to source a `journey.theme` accent from, the button fills `accent/primary`.

---

## 09 · Layout tokens

**Spacing scale (pt):** 4-pt base — 4 / 8 / 12 / 16 / 24 / 32

**Radii & strokes:**
- Cards — 14–16 radius, 2pt hairline border
- Buttons / bars — 12 / 999 radius, 3pt ink border
- Map frame — 18 radius, 3pt ink border
- Hard drop shadow — `.shadow(color: ink, radius: 0, x: 0, y: 4)` — **no blur**
- Character facets — no border, no shadow

---

## 10 · Developer handoff notes

**Progress.** `progress = min(1.0, journey.distanceAccumulated / journey.totalDistance)`, both meters, where `distanceAccumulated` comes from HealthKit `distanceWalkingRunning` via the shared delta-based update. Steps are a display stat only and never feed progress. See the App Concept doc — that document owns this.

**Waypoints.** Names and distances are journey data (bundled JSON or SwiftData records), seeded from the table in the App Concept doc. Never Swift literals in view code.

**Terrain.** Full detail lives in §07 — Canvas-only rendering, `terrain/*` tokens, fixed draw order, and the scatter hard-contract. The short version: no gradients, no per-glyph views, no literals, and never hand-place a forest — that's the generator's job (App Concept doc).

**Colors.** Ship as Asset Catalog colorsets keyed by token name, each with a light and a Deepdark variant. Views reference `Color("accent/primary")` or `journey.theme.accentColor` — never `Color.red`, never a hex literal.

**Character rig.** Layered vector, runtime-swappable facet colors and brow/posture states.

**Fonts.** Bundle Cinzel + Nunito, or map to SF Pro Rounded + a serif display. Never body copy in the display face.

**Pixel glyphs.** 1× grid, integer scaling only.

**Naming.** Every proper noun in this document is original to JourneyTracker. Do not reintroduce names from existing books, films, or games — see the App Concept doc's naming section.
