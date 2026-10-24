# jump-settings

Objective: roadmap step 6 of `my-idea.md` — "Settings UI, launch at login, icon."
Branch: `feat/settings` (stacked on `feat/web-perf`) · Delivery: ask-on-risk · Test runner: `swift test --package-path Packages/JumpKit`.

## Specs

- S1 (spec §2 MVP 7): "Settings: shortcut, hint characters, launch at login."
- S2 (spec §3.1): "Login item | `SMAppService.mainApp`"; "Settings | One `@Observable` model backed by `UserDefaults`"; "UI | SwiftUI (`MenuBarExtra`, `Settings`)".
- S3 (spec §4): "`logo.png` (1024×1024, glass keycap with "J") → `AppIcon` asset catalog." "Menu bar icon: a monochrome template image derived from the logo."
- Assumption: hint characters are normalized (lowercased, duplicates and non-letters removed) and need at least 2 characters; invalid input keeps the previous value.
- Out of scope: the release itself (publishing is the user's decision), notarization (no paid Apple Developer account yet), Icon Composer `.icon` variant.

## Tasks

- T1 · S1, S2 · inline · JumpSettings model (hint characters) with validation + persistence, tested · pending
- T2 · S1, S2 · inline · Settings window: shortcut recorder, hint characters, launch at login (SMAppService) · pending
- T3 · S3 · inline · AppIcon asset catalog from logo.png + menu bar template icon · pending

## Log

- L1 (2026-10-24): "dale, sigue con el paso 6"
