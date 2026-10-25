# jump-scroll-hardening

Objective: close the open scroll-mode review follow-ups.
Branch: `feat/scroll-hardening` (from `main` 61c6b1f) · Delivery: ask-on-risk · Test runner: `swift test --package-path Packages/JumpKit`.

## Specs

- S1: "Si una escritura por accesibilidad falla a mitad de camino, no pasa sola a la rueda." → a failed accessibility read/write switches the active area to wheel events (pointer moved to the area) and a held scroll continues.
- S2: "Preparar cada área corre en el hilo principal: con una app colgada podría trabar a JUMP un instante." → no accessibility IPC on the main thread in scroll mode; controls are prepared during the background scan.
- S3: "Faltan tests de varias partes." → tests for AccessibilityWriter drop-vs-queue, ScrollAreaFinder limits (depth, nodes, deadline), zero-size wrappers, window overlapping no screen.
- Assumption: a full ScrollModeController lifecycle test needs dependency injection (overlay, pointer, scanner); proposed separately, not done here.

## Tasks

- [x] T1 · S3 · inline · writer and finder tests · see git log · characterization tests (pass on first run, pin existing behavior)
- [x] T2 · S2 · inline · prepare AXScrollControls in the background scan · 2b799b5 · grep: no AX calls left in ScrollModeController
- [x] T3 · S1 · inline · fall back to wheel on accessibility failure · 2b799b5 · builds; failure path not exercised live (needs an app that rejects writes)

## Log

- L1 (2026-10-24): "funciona bien, mergea scroll a main y súbelo. despues revisa esto: - Si una escritura por accesibilidad falla a mitad de camino, no pasa sola a la rueda. - Preparar cada área corre en el hilo principal: con una app colgada podría trabar a JUMP un instante. - Faltan tests de varias partes."
- L2: 104/104 tests, Release builds. Also fixed a misplaced doc comment (a "- Parameter" line after @concurrent). The ScrollModeController lifecycle still has no automated test: it needs overlay/pointer/scanner injection (proposed separately).
