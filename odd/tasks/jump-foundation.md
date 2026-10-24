# jump-foundation

Objective: roadmap steps 0–1 of `my-idea.md` — repository scaffold and a menu bar agent with Accessibility onboarding.
Branch: `feat/foundation` · Delivery: ask-on-risk · Test runner: `xcodebuild test -scheme JUMP -destination 'platform=macOS'` (XCTest/Swift Testing).

## Specs

- S1 (step 0): "Repo setup: SPM + Xcode project, GPL-3.0 `LICENSE` with Vimac attribution, README, CI (build + tests)." Project generated with XcodeGen (`project.yml` committed, `.xcodeproj` git-ignored). Bundle id `com.alvaldes.jump`. Minimum macOS 26. CI deferred (assumption: no runner with Xcode 27 verified yet).
- S2 (step 1): "Menu bar agent + Accessibility onboarding." `LSUIElement = true`, no Dock icon. Check `AXIsProcessTrustedWithOptions`, prompt, deep link to System Settings, observe trust changes.
- S3: Local builds signed with a free Apple Development (personal team) certificate so the Accessibility permission survives rebuilds; team id kept out of git so contributors use their own.

## Tasks

- [x] T1 · S1, S3 · inline · repo scaffold, XcodeGen project, signing config, LICENSE, README · 6b02d63 (docs), f0bdaa3 (project) · CI deferred
- [x] T2 · S2 · inline · menu bar app + AccessibilityPermission with tests · f0bdaa3 · RED (empty target) → GREEN 6/6 · review assess: medium, under_budget (pending in slice)
- [ ] T3 · S2, S3 · manual · user verifies onboarding window + permission grant with a stable signature · pending (needs Signing.local.xcconfig)

## Log

- L1 (2026-10-24): "listo, ya instalé Xcode" — after decisions: macOS 26 only, shortcut Cmd-Shift-Space, XcodeGen, bundle id com.alvaldes.jump, no paid Apple Developer account yet. Earlier request: "Dime qué más, qué otras preguntas quedan para responderlas y ya empecar".
- L2: Environment: Xcode 27.1 (macOS 27 SDK), xcodegen 2.46.0, 0 codesigning identities.
- L3: Built with xcodebuild (BUILD SUCCEEDED, no warnings); bundle LSUIElement=true, min 26.0, adhoc signature. App launched and stayed running; onboarding UI not visually verified (screenshot captured another fullscreen app). Core logic split into Packages/JumpKit so `swift test` runs without launching the app. Next: user sets up signing and verifies T3; then roadmap step 2 (global shortcut + AX scanner).
- L4: Signing set up: Config/Signing.local.xcconfig (team 7UDSYQKV9H, git-ignored); `xcodebuild -allowProvisioningUpdates` created the Apple Development certificate. Designated requirement is now certificate-based, so TCC permission survives rebuilds. T3 awaiting user test.
- L5 (2026-10-24): user reported "el permiso se lo doy pero la ventana no se cierra y sigue apareciendo. Y en el menu aun no aparece access granted". Reproduced: fresh signed launch still showed onboarding (AXIsProcessTrusted false). Causes: (a) stale TCC entries — `tccutil reset` removed two JUMP entries (one from an earlier signature); (b) bug: NSApplication suspends distributed notifications for inactive apps, so the grant was never observed. Fix: poll every 1s only while untrusted + `.deliverImmediately` observer for revocations. RED→GREEN 7/7.
