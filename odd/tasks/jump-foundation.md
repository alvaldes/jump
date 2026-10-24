# jump-foundation

Objective: roadmap steps 0–1 of `my-idea.md` — repository scaffold and a menu bar agent with Accessibility onboarding.
Branch: `feat/foundation` · Delivery: ask-on-risk · Test runner: `xcodebuild test -scheme JUMP -destination 'platform=macOS'` (XCTest/Swift Testing).

## Specs

- S1 (step 0): "Repo setup: SPM + Xcode project, GPL-3.0 `LICENSE` with Vimac attribution, README, CI (build + tests)." Project generated with XcodeGen (`project.yml` committed, `.xcodeproj` git-ignored). Bundle id `com.alvaldes.jump`. Minimum macOS 26. CI deferred (assumption: no runner with Xcode 27 verified yet).
- S2 (step 1): "Menu bar agent + Accessibility onboarding." `LSUIElement = true`, no Dock icon. Check `AXIsProcessTrustedWithOptions`, prompt, deep link to System Settings, observe trust changes.
- S3: Local builds signed with a free Apple Development (personal team) certificate so the Accessibility permission survives rebuilds; team id kept out of git so contributors use their own.

## Tasks

- T1 · S1, S3 · inline · repo scaffold, XcodeGen project, signing config, LICENSE, README · pending
- T2 · S2 · inline · menu bar app + AccessibilityPermission with tests · pending

## Log

- L1 (2026-10-24): "listo, ya instalé Xcode" — after decisions: macOS 26 only, shortcut Cmd-Shift-Space, XcodeGen, bundle id com.alvaldes.jump, no paid Apple Developer account yet. Earlier request: "Dime qué más, qué otras preguntas quedan para responderlas y ya empecar".
- L2: Environment: Xcode 27.1 (macOS 27 SDK), xcodegen 2.46.0, 0 codesigning identities.
