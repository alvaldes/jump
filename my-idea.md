# JUMP

Keyboard-driven screen navigation for macOS. Press a global shortcut, every actionable element on screen gets a short label (hint), type the label, and JUMP performs the action. No mouse, no trackpad.

- **License:** GPL-3.0 (open source; reuses and modernizes code from Vimac, which is GPL-3.0).
- **Status:** design draft — nothing implemented yet.

---

## 1. References

We do not reinvent the wheel. Each reference has a specific role:

| Reference | What it is | What we take from it |
|---|---|---|
| [Vimac](https://github.com/nchudleigh/vimac) | Open-source predecessor of Homerow. Swift, GPL-3.0. Last commit 2022-12-31. | **Primary code base**: AX scanning, hint heuristics, label algorithm, overlay panel, event tap, scroll mode. Port and modernize. |
| [Homerow](https://www.homerow.app) | Vimac's commercial successor (paid, no license). | Product and UX benchmark only. No code. |
| [HRM](https://github.com/wontaeyang/hrm) | Native Swift menu bar app (home row mods), macOS 14+. | Modern reference for CGEventTap handling, menu bar agent structure, SPM build, Homebrew distribution. |
| [Surfingkeys](https://github.com/brookhong/Surfingkeys) | Browser extension. | Hint interaction ideas (filtering, multi-action modifiers). |
| [No Mouse Mode](https://nomousemode.com/) | Keyboard navigation product. | UX benchmark. |
| [21st.dev](https://21st.dev) | React/Tailwind component gallery. | **Visual language only** (hint tags, settings UI). Translated to SwiftUI/AppKit; no web code is used. |

---

## 2. Scope

### MVP

1. Menu bar agent (`LSUIElement = true`), no Dock icon.
2. Accessibility permission onboarding.
3. Configurable global shortcut to enter **hint mode**.
4. Scan the frontmost app's focused window (plus menu bar) and label actionable elements.
5. Type a label to act on the element:
   - no modifier → primary action (press / left click)
   - `Shift` → right click
   - `Cmd` → double click
   - `Opt` → move the cursor only
6. `Esc` exits; `Delete` removes the last typed character; `Space` rotates overlapping hints.
7. Settings: shortcut, hint characters, launch at login.

### After MVP

- **Scroll mode** (`h j k l d u gg G` on the largest scroll area; ported from Vimac).
- Hold-key activation (e.g. hold `Space`) and key-sequence activation (e.g. `fd`).
- Menu bar extras and Notification Center scanning.
- Text search mode (jump to visible text).
- Hint themes.
- Auto-updates (Sparkle 2).

### Out of scope

- Mac App Store. Apps using the Accessibility API cannot run sandboxed. Distribution is Developer ID + notarization, GitHub Releases and a Homebrew cask.
- Analytics or telemetry of any kind.

---

## 3. Technical design

### 3.1 Platform & tooling

| Area | Choice | Replaces (Vimac) |
|---|---|---|
| Language | Swift 6, strict concurrency | Swift 5 |
| Minimum OS | macOS 26 (decided; no backwards compatibility) | macOS 10.14 |
| UI | SwiftUI (`MenuBarExtra`, `Settings`) + AppKit for the overlay | Storyboards, Preferences pod |
| Async | `async`/`await`, `TaskGroup`, actors, `AsyncStream` | RxSwift 5, raw `Thread` |
| Dependencies | SPM only | CocoaPods + Carthage |
| Hotkeys | [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) | MASShortcut |
| Login item | `SMAppService.mainApp` | LaunchAtLogin (helper app) |
| Updates | Sparkle 2 + EdDSA (post-MVP) | Sparkle 1 on AppCenter (retired) |
| Settings | One `@Observable` model backed by `UserDefaults` | Two parallel settings systems |
| AX access | Thin in-house typed wrapper over `AXUIElement` | AXSwift 0.2 (force casts) |

### 3.2 Modules

```
JUMP
├── App            entry point (@main SwiftUI App + NSApplicationDelegateAdaptor), menu bar, settings
├── Permissions    AXIsProcessTrustedWithOptions, deep link to System Settings, trust-change observer
├── Activation     global hotkey, (later) hold-key and key-sequence listeners via CGEventTap
├── Accessibility  AX wrapper, scanner, element filtering, web-area search, Chromium/Electron enabler
├── Hints          label generator, hint model, input state machine
├── Overlay        one non-activating NSPanel per screen, hint rendering
├── Actions        AXPress / synthesized mouse events
└── Geometry       AX (top-left) <-> AppKit (bottom-left) conversion, multi-monitor
```

### 3.3 Hint mode flow

1. Shortcut pressed → read frontmost app and its `AXFocusedWindow` (skip JUMP itself).
2. Scan in parallel (`async let`): focused window and app menu bar. Global deadline (e.g. 150 ms); return whatever is ready.
3. Filter, generate labels, show overlays on every screen the window touches.
4. Overlay panel becomes key; a local key monitor consumes input.
5. Label matched → hide overlay → perform action. No match → exit.

### 3.4 Scanning (from Vimac, modernized)

- Fetch `AXRole`, `AXPosition`, `AXSize` in **one batched call** (`AXUIElementCopyMultipleAttributeValues`), plus the action list.
- **Do not** use `kAXBoundsForRangeAttribute`: it applies to text ranges, not elements.
- Children: `AXVisibleRows` for `AXTable`/`AXOutline`, `AXChildren` otherwise.
- Intersect each frame with its ancestors' clip rect; prune fully clipped subtrees.
- **Actionable rule** (Vimac): not `AXWindow`/`AXScrollArea`, and has an AX action other than `AXShowMenu`, `AXScrollToVisible`, `AXShowDefaultUI`, `AXShowAlternateUI`. An `AXRow` without actionable descendants is also actionable.
- **Web areas:** if `AXWebArea` supports `AXUIElementsForSearchPredicate`, run one visible-only search (Button, CheckBox, Control, Graphic, Link, RadioGroup, TextField) instead of walking the tree. Keep Vimac's per-key fallback.
- **Chromium/Electron:** set `AXManualAccessibility` (Electron) / `AXEnhancedUserInterface` (Chrome) lazily on the target pid only, remember which pids were touched, and restore them when JUMP quits.
- New over Vimac: depth and element caps, cooperative cancellation, a dedicated AX actor off the main thread, per-app messaging timeout.

### 3.5 Labels

- Port Vimac's `AlphabetHints` (Vimium `hintStrings`): prefix-free labels of near-equal length.
- Default characters: home-row biased, user configurable (Vimac default: `sadfjklewcmpgh`).
- New over Vimac: assign shorter labels by spatial proximity / reading order instead of traversal order.

### 3.6 Actions

1. Primary action: `AXUIElementPerformAction(kAXPressAction)` first. It does not move the cursor and works on partially covered elements.
2. Fallback and modifier actions: synthesized `CGEvent` mouse events at the element center, posted to `.cghidEventTap`, with explicit `mouseEventClickState` and cleared modifier flags (from Vimac's `Utils`).
3. Text fields: focus (`AXFocused = true`) instead of clicking.

### 3.7 Overlay

- `NSPanel`: `.nonactivatingPanel`, clear background, `ignoresMouseEvents`, `.statusBar` level, `.canJoinAllSpaces` + `.fullScreenAuxiliary`.
- **One panel per `NSScreen`** (Vimac used a single window and had multi-monitor bugs).
- AX coordinates are top-left based on the primary screen; convert with the primary screen's `frame.maxY`. Covered by unit tests.
- Render all hints in a single layer-backed view (or SwiftUI `Canvas`), not one view per hint, so hundreds of hints stay smooth.

### 3.8 Visual design

- Inspired by 21st.dev: compact pill-shaped hint tags, monospaced type (SF Mono), high contrast, soft shadow.
- Matched-prefix characters dimmed as you type.
- Liquid Glass materials (`glassEffect`), matching the glass keycap logo. No fallback needed (macOS 26 minimum).
- Light/dark aware.

### 3.9 Performance targets

| Metric | Target |
|---|---|
| Idle CPU | ~0% (no polling) |
| Idle memory | < 40 MB |
| Shortcut → hints visible, native apps | < 50 ms |
| Shortcut → hints visible, browsers/Electron | < 150 ms (hard deadline, partial results allowed) |

These are goals to measure with `os_signpost`, not guarantees: large AX trees (Electron, Xcode) are the bottleneck.

---

## 4. Assets

- `logo.png` (1024×1024, glass keycap with "J") → `AppIcon` asset catalog. To check: macOS icon grid and padding, a light-mode variant, and an Icon Composer version for macOS 26.
- Menu bar icon: a monochrome template image derived from the logo.

---

## 5. Roadmap

| Step | Deliverable |
|---|---|
| 0 | Repo setup: SPM + Xcode project, GPL-3.0 `LICENSE` with Vimac attribution, README, CI (build + tests). |
| 1 | Menu bar agent + Accessibility onboarding. |
| 2 | Global shortcut + AX scanner (native apps) with tests for geometry and filtering. |
| 3 | Label generator + overlay (multi-monitor). |
| 4 | Input state machine + actions (AXPress, click fallbacks). |
| 5 | Web areas + Chromium/Electron support. |
| 6 | Settings UI, launch at login, icon. → **MVP release** (notarized, Homebrew cask). |
| 7+ | Scroll mode, hold-key activation, Sparkle 2, themes. |

---

## 6. Open decisions

1. ~~Minimum macOS version~~ → decided: macOS 26.
2. ~~Default activation shortcut~~ → decided: `Cmd-Shift-Space`.
3. ~~Project generator~~ → decided: XcodeGen (`project.yml` committed, `.xcodeproj` generated and git-ignored).
4. ~~Bundle identifier~~ → decided: `com.alvaldes.jump`.
5. ~~Developer ID~~ → decided: no paid account for now. Local builds signed with a free Apple Development (personal team) certificate so the Accessibility permission survives rebuilds; Developer ID + notarization added before the first public release.
