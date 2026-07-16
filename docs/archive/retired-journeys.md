# Retired journeys (KAN-45)

Journeys removed from the live catalog but preserved here for a future return.
Restoring one is a copy-back: re-add its `TemplateSeed` to `SeedData.catalog`,
remove its name from `SeedData.retiredTemplateNames`, move its notification CSV
back to `JourneyTracker/Notifications/Content/`, and re-add its
`NotificationContentProvider.slugByJourneyName` entry.

Retired 2026-07-16. Neither journey ever had an authored faceted map or real
background-image assets (`ember_spire_bg` / `lantern_road_bg` were forward
references) — both rendered the KAN-7 pin-and-route fallback. The KAN-20 debug
fixtures (`EmberSpireScaleFixture`, `SampleJourneyMap`, `TerrainSpecimenScene`)
reuse Ember Spire *names* but are standalone and intentionally kept.

---

## The Road to Ember Spire

Fantasy · 1,800 miles · accent `accent/primary` · path `ink` ·
background `ember_spire_bg` · marker `marker_wren`

Notification sheet: [`ember-spire.csv`](ember-spire.csv)
(rows were PROVISIONAL — character identity under review, KAN-25)

| Waypoint | Cumulative miles | x | y |
|---|---|---|---|
| Thistledown | 0 | 0.12 | 0.88 |
| Crosswater | 120 | 0.28 | 0.78 |
| Silvergate | 460 | 0.20 | 0.60 |
| The Deepdelve | 660 | 0.40 | 0.52 |
| Whisperwood | 720 | 0.58 | 0.55 |
| The Windmark | 1040 | 0.52 | 0.38 |
| Whitewatch | 1540 | 0.70 | 0.24 |
| Ember Spire | 1800 | 0.82 | 0.12 |

```swift
TemplateSeed(
    name: "The Road to Ember Spire",
    type: .fantasy,
    totalMiles: 1_800,
    backgroundImageName: "ember_spire_bg",
    markerImageName: "marker_wren",
    accentColorToken: "accent/primary",
    pathColorToken: "ink",
    waypoints: [
        ("Thistledown",    0,    0.12, 0.88),
        ("Crosswater",     120,  0.28, 0.78),
        ("Silvergate",     460,  0.20, 0.60),
        ("The Deepdelve",  660,  0.40, 0.52),
        ("Whisperwood",    720,  0.58, 0.55),
        ("The Windmark",   1040, 0.52, 0.38),
        ("Whitewatch",     1540, 0.70, 0.24),
        ("Ember Spire",    1800, 0.82, 0.12),
    ]
),
```

## The Lantern Road

Fantasy · 20 miles · accent `accent/secondary` · path `ink` ·
background `lantern_road_bg` · marker `marker_wren`

Notification sheet: [`lantern-road.csv`](lantern-road.csv)

| Waypoint | Cumulative miles | x | y |
|---|---|---|---|
| Wickgate | 0 | 0.14 | 0.86 |
| Foglow Bridge | 3 | 0.24 | 0.76 |
| Palefire Hollow | 17 | 0.74 | 0.26 |
| Lanternrest | 20 | 0.86 | 0.14 |

```swift
TemplateSeed(
    name: "The Lantern Road",
    type: .fantasy,
    totalMiles: 20,
    backgroundImageName: "lantern_road_bg",
    markerImageName: "marker_wren",
    accentColorToken: "accent/secondary",
    pathColorToken: "ink",
    waypoints: [
        ("Wickgate",         0,  0.14, 0.86),
        ("Foglow Bridge",    3,  0.24, 0.76),
        ("Palefire Hollow",  17, 0.74, 0.26),
        ("Lanternrest",      20, 0.86, 0.14),
    ]
),
```

## Restore checklist

1. Copy the `TemplateSeed` back into `SeedData.catalog` (order in the array is
   presentation-irrelevant; the catalog is keyed by name).
2. Delete the name from `SeedData.retiredTemplateNames` — otherwise the seed
   pass deletes the template again on next launch.
3. `git mv docs/archive/<slug>.csv JourneyTracker/Notifications/Content/`.
4. Re-add the name → slug entry in
   `NotificationContentProvider.slugByJourneyName`.
5. Un-archive its section in `docs/JourneyTracker_App_Concept.md` and refresh
   the KAN-4 Jira mirror.
