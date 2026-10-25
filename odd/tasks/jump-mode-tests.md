# jump-mode-tests

Objective: automated tests for the hint-mode and scroll-mode controller lifecycles, flagged by every review since step 2.
Branch: `test/mode-controllers` (from `main` df3d151) · Delivery: ask-on-risk · Test runner: `swift test --package-path Packages/JumpKit` (also in CI).

## Specs

- S1 (user): "dale, arranca con los tests de los controladores" — after: "Tests del ciclo de vida de los controladores (hints y scroll): requiere inyectar el overlay, el puntero y el escáner."
- S2: controller logic moves into JumpKit behind injected dependencies (overlay, pointer, keyboard/app events, scanner, actions, scroll driver); the app target keeps only AppKit wiring. Observable behavior unchanged.
- S3: hint-mode tests: untrusted / own app / no window; show hints; typed label performs the action (modifiers choose it); Esc, typo, hotkey, app switch dismiss; dismiss during scan shows nothing.
- S4: scroll-mode tests: enter / no targets / app changed during search / overlay cannot take keys; accessibility areas leave the pointer alone, wheel areas move and restore it; held keys start and only their release stops; modifiers ignored; Tab, gg, G; failure falls back to wheel and resumes a held scroll, stale failures ignored; app switch and keyboard loss exit; mutual exclusion with hint mode.
- Assumption: hint mode also exits on keyboard loss (same stuck-input risk as scroll mode had).

## Tasks

- [x] T1 · S2 · inline · shared mode protocols, key decoding, live AppKit adapters · see git log · decoding RED→GREEN
- [x] T2 · S2, S4 · inline · ScrollMode in JumpKit + tests · 72e7b2d · 16 lifecycle tests; mutations (any key-up stops, no app recheck) caught
- [x] T3 · S2, S3 · inline · HintMode in JumpKit + tests · see git log · 14 lifecycle tests; mutations (modifiers ignored, keeps listening) caught
- [x] T4 · S2 · inline · app wiring uses the JumpKit modes; mode coordination · d39fa62 · ModeSwitcher test; Release builds; app launches cleanly

## Log

- L1 (2026-10-24): "dale, arranca con los tests de los controladores"
- L2: Tests 104 → 135. Lifecycle tests characterize moved logic, so they passed first; each suite was mutation-tested (2 deliberate breaks each, all detected, code restored). Two of my own test expectations were wrong (labels are sorted: with "sa" the first element gets A) and were fixed. Behavior change (assumption in specs): hint mode now also exits when the overlay loses the keyboard. Old HintModeController/ScrollModeController deleted; app-wide work moved to AppServices. Not exercised live with keys (user test).
- L3: Native review approved and acknowledged (lineage review-032a73105fcb8a12). It found two vacuous tests (cancellation tests awaited a nil task, so removing the cancellation guard still passed) and a stale deferred key-loss callback that could end a restarted session. Fixed: tests keep the original task before the second press (mutation without the guard now fails 2 tests in each mode); AppKitModeInput ignores deferred checks from an earlier session. CI on the branch green before this fix. 135/135 tests.
