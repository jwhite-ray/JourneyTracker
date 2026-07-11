# Mockup render archive

Rendered screenshots of every design-review mockup round, kept permanently
(the disposable SwiftUI mockup *source* files in `Mockups/` are deleted once
a direction is chosen — these renders are the durable record of what the
user chose between).

One folder per ticket. Renders are produced offscreen with `ImageRenderer`
at each Design Review gate and archived here before the losing variants'
source files are removed. Naming: `<Variant><index>_<state>.png`.

| Ticket | Round | Chosen |
|---|---|---|
| KAN-7 | Journey map (A Ink Trail / B Stepping Stones / C Map First) | A |
| KAN-10 | Lifecycle cards (A Eyebrow Row / B Chip Row / C Stamp+Kebab) | C (straight stamp) |
| KAN-11 | Available Journeys store (A Card Stack / B Compact Manifest / C Hero+List) | B, with A's empty state ("Start a Journey" CTA) |
