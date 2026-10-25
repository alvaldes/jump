# jump-text-search

Objective: a text search mode that finds visible text in the focused window through Accessibility and jumps to the chosen match.
Branch: `feat/text-search` (from `main` 634a026, worktree `../jump-worktrees/text-search`) · Delivery: ask-on-risk · Test runner: `swift test --package-path Packages/JumpKit` (also in CI); latency via `jump-bench` and the app log.

## Specs

- S1 (user): "Buscar texto visible en pantalla y saltar a él." Source: Accessibility only first — user: "dale con solo Accessibility primero"; OCR is a later, opt-in step (not in this feature).
- S2 (user approved "dale, con todo lo que propusiste"): shortcut **⌘⇧F** by default, configurable in Settings like the other two shortcuts.
- S3 (approved proposal): a search box opens at the top center of the focused window in < 50 ms (the hint-mode target, spec §3.9); visible text is collected in the background while the user types.
- S4 (approved proposal): matching ignores case and diacritics; only visible text counts (static text, text field/area values, control titles), not hidden descriptions of icons (AXDescription). Every match is highlighted with the current hint theme colors.
- S5 (approved proposal): navigation — typing edits the query (Delete removes the last character); **Return** jumps to the selected match; **Tab / Shift-Tab** move the selection in reading order (wrapping); **Esc** cancels; the hotkey again closes it. The selection starts at the first match in reading order.
- S6 (approved proposal): jumping clicks on the matched word with the same modifiers as hints (Shift = right click, ⌘ = double click, ⌥ = move the pointer only); in an editable text field/area it places the caret at the start of the match instead.
- S7: the mode ends like the others: focus leaving the target window, keyboard loss, Esc, hotkey; it never runs at the same time as hint or scroll mode (shared overlay and keyboard).
- S8: collection is bounded (deadline and node cap) and never blocks the main thread; web areas use the `AXStaticTextSearchKey` search predicate (spike: 15 ms vs 160 ms walk); word frames come from `AXBoundsForRange` only for matches, falling back to the element frame.
- Assumption: the status line in the box shows "Searching…" while collecting, "No matches", or "n of m".

## Tasks

- [x] T1 · S1, S3–S8 · delegated (writer A, parallel) · core in JumpKit: `TextMatcher` (pure), search key/input state machine, `TextSearchMode<Node>` controller with fakes-based lifecycle tests, `ModeSwitcher` exclusion, AX `TextCollector` (collect, word bounds, caret placement, jump action) · 6c73902, 8680dd6, 88a68f6 · RED (stubs) → GREEN; 248 pass after merging T2
- [x] T2 · S3, S4 · delegated (writer B, parallel) · overlay: `HintOverlay: SearchOverlayPresenting`, search box + highlights drawn in the theme (one draw pass) · 8548439 · RED (missing types) → GREEN; mutation run caught 4 breaks; 207 pass · gap: showSearch key/ordering only live (T4)
- [x] T3 · S2, S6, S7 · inline · app wiring: ⌘⇧F shortcut + Settings recorder, `JumpApp` / `ModeSwitcher` wiring, menu entry · see git log · Release build succeeds
- [ ] T4 · S3, S8 · inline · live test with the user + latency from the log

## Log

- L1 (2026-10-25): "dale, con todo lo que propusiste" (approving the text search proposal: ⌘⇧F, search box, case/diacritic-insensitive visible-text matching with theme highlights, Return/Tab/Shift-Tab/Esc, click on the word with hint modifiers, caret in text fields). Earlier: "dale con solo Accessibility primero"; backlog item "Buscar texto visible en pantalla y saltar a él."
- L2: Spike (commit 352e9bb, cherry-picked from a351258, `jump-bench text`): AX walk 18–160 ms per window; web predicate 15 ms; AXBoundsForRange 0.1–0.3 ms per call (Ghostty unsupported); AX also returns invisible labels (AXDescription). Shared contract committed first in `Search/SearchTypes.swift` so T1 and T2 run in parallel with disjoint files. Route: two writers (Writer trigger (a): two independent units, disjoint surfaces, several minutes each; plus the long-session context backstop).
- L3: T1 gaps (writer): ⌥-typed characters arrive as the base key (KeyPress ignores modifiers; diacritic-insensitive matching hides most cases); large text areas list matches scrolled out of view (no AXVisibleCharacterRange yet); web text fields only via the combined search-key query; Return during collection is ignored. Live read-only probe: Xcode 31 texts/165 ms, Zen 266/94 ms, System Settings 14/95 ms, Ghostty one area without word bounds. Reading-order grouping now shared (`ReadingOrder.sorted`), hint behavior unchanged.
