# jump-search-ocr

Objective: an opt-in OCR fallback for text search, for windows whose Accessibility text is missing or unusable (terminals, PDFs, images, canvases).
Branch: `feat/search-ocr` (from `main` 129030e, worktree `../jump-worktrees/search-ocr`) · Delivery: ask-on-risk · Test runner: `swift test --package-path Packages/JumpKit` (also in CI); latency from the app log.

## Specs

- S1 (user): "dale, arrancá con los tres (1,2,3) en worktrees separados" — item 3 was "OCR opcional para terminales, PDF e imágenes. Es más trabajo y necesita el permiso de Grabación de pantalla." Earlier approved: "OCR as an opt-in fallback … only for apps where Accessibility has no usable text" and "dale con solo Accessibility primero".
- S2: opt-in — a Settings toggle in the text search area, off by default, persisted. Turning it on requests Screen Recording; while not granted, Settings says so and offers to open the Privacy settings; search keeps working with Accessibility only.
- S3 (assumption, announced to the user): when enabled and granted, OCR of the target window runs in parallel with the Accessibility collection, started when the mode opens; it never delays the search box (< 50 ms target) or the main thread.
- S4 (assumption, announced to the user): for each query, matches come from Accessibility when it has at least one; otherwise from OCR. No merging or de-duplication between sources.
- S5: OCR matching follows the same rules (case- and diacritic-insensitive, reading order, Tab/Shift-Tab, statuses); OCR match frames are word-level boxes in AX coordinates (Vision normalized → window frame → global AX).
- S6: jumping to an OCR match clicks at its center with the hint modifiers (Shift right click, ⌘ double click, ⌥ move pointer); there is no caret placement for OCR matches.
- S7 (spike, `odd/tasks/jump-text-search.md` L2 and Engram `jump/text-search-spike`): use the legacy `VNRecognizeTextRequest` `.fast` (the Swift `RecognizeTextRequest` `.fast` returns almost nothing on macOS 27.0.1), capture at 2x (1x loses lines), cache or prefetch the ScreenCaptureKit window lookup (85–120 ms uncached); expected OCR ready ~50–125 ms after mode open.
- S8: Accessibility-only behavior is unchanged when the toggle is off (existing tests keep passing; add one proving it).

## Tasks

- [ ] T1 · S2–S8 · delegated (writer, parallel with fix/search-polish) · settings + permission, recognizer (capture + Vision), OCR source in the search mode, Settings UI and app wiring, tests
- [ ] T2 · S3, S7 · inline · live test with the user + latency

## Log

- L1 (2026-10-25): "dale, arrancá con los tres (1,2,3) en worktrees separados" (1 = text search fixes, 2 = jump-bench warnings, 3 = this OCR fallback). S3/S4 are the parent's announced interpretation of the approved "opt-in fallback".
- L2: Route: one writer (Writer trigger (a): runs in parallel with the fix/search-polish writer, independent behavior, several minutes each). Both touch Modes/TextSearchMode.swift and Search/**, so they use isolated worktrees and the parent merges.
