# jump-overlay

Objective: roadmap step 3 of `my-idea.md` — "Label generator + overlay (multi-monitor)."
Branch: `feat/overlay` (stacked on `feat/scanner`) · Delivery: ask-on-risk · Test runner: `swift test --package-path Packages/JumpKit`.

## Specs

- S1 (spec §3.5): "Port Vimac's `AlphabetHints` (Vimium `hintStrings`): prefix-free labels of near-equal length." "Default characters: home-row biased, user configurable (Vimac default: `sadfjklewcmpgh`)." "assign shorter labels by spatial proximity / reading order instead of traversal order."
- S2 (spec §3.7): "One panel per `NSScreen`"; "`NSPanel`: `.nonactivatingPanel`, clear background, `ignoresMouseEvents`, `.statusBar` level, `.canJoinAllSpaces` + `.fullScreenAuxiliary`"; "Render all hints in a single layer-backed view (or SwiftUI `Canvas`), not one view per hint"; AX → AppKit conversion via `ScreenGeometry`.
- S3 (spec §3.8): "compact pill-shaped hint tags, monospaced type (SF Mono), high contrast, soft shadow." Hint placed at element center; links at bottom-left (Vimac #373).
- S4 (assumption, minimal until step 4's input state machine): hotkey shows hints for the focused window; hotkey again or `Esc` hides them; switching apps hides them.
- Out of scope: typing labels / actions (step 4), dimming matched prefixes (step 4), settings for characters (step 6).

## Tasks

- T1 · S1 · inline · HintLabels generator + reading-order assignment, tested · pending
- T2 · S2, S3 · inline · overlay panels per screen + hint drawing view · pending
- T3 · S4 · inline · hint mode wiring: show/hide, Esc, app switch · pending

## Log

- L1 (2026-10-24): "dale sigue" (after "¿Seguimos con el Paso 3, los labels y el overlay...?")
- L2: Reference: Vimac `AlphabetHints.swift` (BFS queue, slice, sort, reverse, uppercase), `HintsViewController.swift:76-88` (center placement; AXLink at frame origin, bottom-left in AppKit).
