# jump-scroll

Objective: scroll mode (spec §2 "After MVP": "Scroll mode (`h j k l d u gg G` on the largest scroll area; ported from Vimac)").
Branch: `feat/scroll` (from `main`) · Delivery: ask-on-risk · Test runner: `swift test --package-path Packages/JumpKit`.

## Specs

- S1 (spec §2): "Scroll mode (`h j k l d u gg G` on the largest scroll area; ported from Vimac)". Vimac semantics: `h j k l` scroll left/down/up/right while held; `d`/`u` half a page down/up; `gg` top, `G` bottom; `Tab` next scroll area; `Esc` exits.
- S2 (Vimac): scroll areas are the window's visible `AXScrollArea`s, largest first, then the window itself; the cursor moves to the active area's center (scroll events go to what is under the cursor) and returns to where it was on exit; the active area is outlined.
- S3 (assumption): own global shortcut, default `⌘⇧J` (rebindable in Settings); entering scroll mode closes hint mode and vice versa; switching apps exits.
- S4 (spec §3.9 spirit): entering scroll mode stays well under 50 ms on native apps (the area search does not walk into web content).

## Tasks

- T1 · S1 · inline · ScrollInput key state machine (`gg` sequence), tested · pending
- T2 · S2, S4 · inline · ScrollAreaFinder over AccessibilityNode, tested · pending
- T3 · S1, S2 · inline · Scroller (CGEvent pixel scroll, smooth/half page/edge) + overlay outline · pending
- T4 · S2, S3 · inline · ScrollModeController wiring, shortcut, Settings recorder · pending

## Log

- L1 (2026-10-24): "dale, sigue con el modo scroll"
- L2: Reference: Vimac `ScrollModeActiveScrollAreaViewController.swift` (key sequences with 0.25 s timeout, keyUp stops), `ChunkyScroller.swift` (pixel `scrollWheelEvent2`, smooth at 50 Hz, half page = area height / 2, edges = Int16 max), `QueryScrollAreasService.swift` (AXScrollArea DFS, skip AXWebArea, largest first).
