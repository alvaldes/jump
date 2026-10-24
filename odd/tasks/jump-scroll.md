# jump-scroll

Objective: scroll mode (spec §2 "After MVP": "Scroll mode (`h j k l d u gg G` on the largest scroll area; ported from Vimac)").
Branch: `feat/scroll` (from `main`) · Delivery: ask-on-risk · Test runner: `swift test --package-path Packages/JumpKit`.

## Specs

- S1 (spec §2): "Scroll mode (`h j k l d u gg G` on the largest scroll area; ported from Vimac)". Vimac semantics: `h j k l` scroll left/down/up/right while held; `d`/`u` half a page down/up; `gg` top, `G` bottom; `Tab` next scroll area; `Esc` exits.
- S2 (Vimac): scroll areas are the window's visible `AXScrollArea`s, largest first, then the window itself; the cursor moves to the active area's center (scroll events go to what is under the cursor) and returns to where it was on exit; the active area is outlined.
- S3 (assumption): own global shortcut, default `⌘⇧J` (rebindable in Settings); entering scroll mode closes hint mode and vice versa; switching apps exits.
- S4 (spec §3.9 spirit): entering scroll mode stays well under 50 ms on native apps (the area search does not walk into web content).

## Tasks

- [x] T1 · S1 · inline · ScrollInput key state machine (`gg` sequence), tested · see git log · RED→GREEN
- [x] T2 · S2, S4 · inline · ScrollAreaFinder over AccessibilityNode, tested · see git log · RED→GREEN; bench Finder 19 ms, Settings 27 ms
- [x] T3 · S1, S2 · inline · Scroller (CGEvent pixel scroll, smooth/half page/edge) + overlay outline · a3b32fb · deltas RED→GREEN
- [ ] T4 · S2, S3 · inline · ScrollModeController wiring, shortcut, Settings recorder · 30c3e3f · builds; live test pending (user)

## Log

- L1 (2026-10-24): "dale, sigue con el modo scroll"
- L2: Reference: Vimac `ScrollModeActiveScrollAreaViewController.swift` (key sequences with 0.25 s timeout, keyUp stops), `ChunkyScroller.swift` (pixel `scrollWheelEvent2`, smooth at 50 Hz, half page = area height / 2, edges = Int16 max), `QueryScrollAreasService.swift` (AXScrollArea DFS, skip AXWebArea, largest first).
- L3: The live test with synthesized keys/mouse was declined by the user (it drives their session); T4 stays pending until the user tests it. 90/90 tests, Release build OK.
- L4: Native review (reliability lens) approved and acknowledged (lineage review-d7964d1e05d21f62). Fixed two of its follow-ups (S1 "while held"): only releasing the key that started a scroll stops it; keys with Cmd/Ctrl/Opt are not scroll commands. Added: if the overlay panel cannot become key, scroll mode exits instead of trapping input. Still open: controller lifecycle has no automated test (live test pending on the user); ScrollAreaFinder caps/deadline/zero-size paths untested.
- L5 (2026-10-24): user: "estan contratrias d u gg G j k, hacen lo contrario j va hacia arriba y k va hacia abajo eso esta mal es la reves. Porque pasa eso." Cause: macOS applies the natural-scrolling inversion (com.apple.swipescrolldirection = 1 on this Mac, the macOS default) to synthesized wheel events too; deltas assumed traditional scrolling. Fix: Scroller reads the preference on every scroll and flips the sign when it is on (RED→GREEN, 92/92). Awaiting user re-test.
