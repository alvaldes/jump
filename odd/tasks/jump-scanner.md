# jump-scanner

Objective: roadmap step 2 of `my-idea.md` — "Global shortcut + AX scanner (native apps) with tests for geometry and filtering."
Branch: `feat/scanner` (stacked on `feat/foundation`) · Delivery: ask-on-risk · Test runner: `swift test --package-path Packages/JumpKit`.

## Specs

- S1: Global shortcut `Cmd-Shift-Space` (decided default) via KeyboardShortcuts (SPM), user-rebindable later (settings in step 6).
- S2: On shortcut, scan the frontmost app's focused window (skip JUMP itself) off the main thread, returning actionable elements with frames in AX coordinates.
- S3: Filtering per spec §3.4 (Vimac rule): "not `AXWindow`/`AXScrollArea`, and has an AX action other than `AXShowMenu`, `AXScrollToVisible`, `AXShowDefaultUI`, `AXShowAlternateUI`. An `AXRow` without actionable descendants is also actionable."
- S4: Spec §3.4: one batched attribute fetch; `AXVisibleRows` for `AXTable`/`AXOutline`; "Intersect each frame with its ancestors' clip rect; prune fully clipped subtrees"; "depth and element caps, cooperative cancellation, a dedicated AX actor off the main thread, per-app messaging timeout."
- S5: Geometry: AX (top-left, primary screen) → AppKit (bottom-left) conversion, unit tested (spec §3.7).
- S6 (assumption, temporary until the overlay in step 3): scan result visible to the user as "Last scan: N elements in X ms" in the menu and in the unified log.
- Out of scope here: web-area search predicate and Chromium/Electron flags (step 5), menu bar scanning, overlay (step 3).

## Tasks

- [x] T1 · S3, S4 · inline · ElementScanner over an `AccessibilityNode` abstraction, tested with fake trees · cd0f31b · RED→GREEN
- [x] T2 · S5 · inline · ScreenGeometry conversion + tests · 1baf761 · RED→GREEN
- [x] T3 · S2, S4 · inline · live AXUIElement node + focused-window lookup + concurrent scan service · de92f8a · no RED (live AX boundary), verified manually
- [~] T4 · S1, S6 · inline · KeyboardShortcuts dependency (exactVersion 3.1.0), hotkey wiring, menu scan summary · committed · Risk: item 5 · assess: high, review_due · independent verifier running

## Log

- L1 (2026-10-24): "funciona, la ventana se cerró sola. sigamos con el paso 2"
- L2: Reference: Vimac `ElementTree.swift:86-125` (hintable rule), `TraverseGenericElementService.swift` (clip = parent's clipped frame for every element, visible rows for tables). KeyboardShortcuts latest 3.1.0 (2026-09-11), tools 6.2.
- L3: Live check: launched signed build, Finder frontmost, synthesized Cmd-Shift-Space → log "Scanned Finder: 145 elements, 602 nodes visited, 121 ms, truncated: false". 121 ms exceeds the 50 ms native target: actions are fetched in a second IPC per node — optimization candidate. Deviation from S4: used a `@concurrent` function instead of a dedicated AX actor (AX calls are thread-safe; an actor would serialize scans for no benefit). Package.resolved lives in the git-ignored xcodeproj, so the dependency is pinned with exactVersion instead.
- L4: Independent verifier: S1,S2,S3,S5,S6 met; S4 blocker confirmed against SDK header ("Setting the timeout on another accessibility object sets it only for that object") — timeout applied only to the app element. Fixed: AXNode.init sets it per node. Also fixed advisories: truncated row no longer appended (RED→GREEN, 23/23), cancelled scan no longer overwrites newer summary. Recheck: live Finder scan 145 elements, 135 ms.
