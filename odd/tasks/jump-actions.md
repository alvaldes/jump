# jump-actions

Objective: roadmap step 4 of `my-idea.md` — "Input state machine + actions (AXPress, click fallbacks)", plus the overlapping-hints follow-up from step 3.
Branch: `feat/actions` (stacked on `feat/overlay`) · Delivery: ask-on-risk · Test runner: `swift test --package-path Packages/JumpKit`.

## Specs

- S1 (spec §2 MVP 5): "Type a label to act on the element: no modifier → primary action (press / left click); `Shift` → right click; `Cmd` → double click; `Opt` → move the cursor only".
- S2 (spec §2 MVP 6): "`Esc` exits; `Delete` removes the last typed character; `Space` rotates overlapping hints." A typed prefix matching no label exits (Vimac `HintModeController.swift:269-292`).
- S3 (spec §3.6): "Primary action: `AXUIElementPerformAction(kAXPressAction)` first." "Fallback and modifier actions: synthesized `CGEvent` mouse events at the element center, posted to `.cghidEventTap`, with explicit `mouseEventClickState` and cleared modifier flags". "Text fields: focus (`AXFocused = true`) instead of clicking."
- S4 (spec §3.8): "Matched-prefix characters dimmed as you type." Non-matching hints disappear.
- S5 (step 3 follow-up L4): overlapping hints (e.g. Finder list rows) are laid out so they do not cover each other when space allows.

## Tasks

- T1 · S1, S2 · inline · HintInput state machine + modifier → action mapping, tested · pending
- T2 · S5 · inline · HintLayout collision avoidance, tested · pending
- T3 · S3 · inline · ElementActions (AXPress, focus, CGEvent clicks) · pending
- T4 · S2, S4 · inline · overlay filtering/dimming/rotation + controller wiring · pending

## Log

- L1 (2026-10-24): "dale, sigue con el paso 4"
