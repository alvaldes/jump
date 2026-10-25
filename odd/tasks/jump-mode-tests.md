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

- T1 · S2 · inline · shared mode protocols, key decoding, live AppKit adapters · pending
- T2 · S2, S4 · inline · ScrollMode in JumpKit + tests · pending
- T3 · S2, S3 · inline · HintMode in JumpKit + tests · pending
- T4 · S2 · inline · app wiring uses the JumpKit modes; mode coordination · pending

## Log

- L1 (2026-10-24): "dale, arranca con los tests de los controladores"
