# JUMP

Keyboard-driven screen navigation for macOS. Press a shortcut, every clickable element gets a short label, type the label to click it. No mouse required.

> Status: early development (v0.3.0, not yet notarized). See [`my-idea.md`](my-idea.md) for the design spec and roadmap.

## Features

| Shortcut | Mode | What it does |
|---|---|---|
| ⌘⇧Space | Hints | Labels every clickable element of the focused window. Type a label to click it. |
| ⌘⇧J | Scroll | Scrolls the focused window without the mouse: `h j k l`, `d u`, `gg G`, `Tab` to change area, `Esc` to leave. |
| ⌘⇧F | Text search | Finds visible text in the focused window. `Tab` / `Shift-Tab` move between matches, `Return` jumps, `Esc` leaves. |

All three shortcuts can be changed in Settings.

- **Actions with modifiers.** Holding a modifier while typing a label (or pressing `Return` in text search) chooses the action: none clicks (or places the caret in a text field), `Shift` right-clicks, `⌘` double-clicks, `⌥` only moves the pointer. Clicks wait until the modifier is released, so apps never see it.
- **Text search** reads text through Accessibility. Matching ignores case and accents, and only counts what is on screen.
- **OCR fallback (optional).** For windows without usable Accessibility text (terminals, PDFs, images), JUMP can recognize text on screen. It is off by default and needs the Screen Recording permission, requested only when you turn it on. Captures never leave memory.
- **Appearance.** Five hint themes (Dark, Light, System, Accent, Classic) with readable contrast, label size from 9 to 20 pt, and Liquid Glass (Off, Regular, Clear).
- **App.** Three menu bar icons, optional Dock icon (official or glyph), launch at login.
- **Leaves the mode when focus moves**, whether by mouse, ⌘-Tab, ⌘\` or a window manager such as AeroSpace.

## Permissions

- **Accessibility** (required): to read and act on other apps' elements.
- **Screen Recording** (optional): only for the OCR fallback.

## Requirements

- macOS 26 or later
- Xcode 27 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Build

```sh
xcodegen generate        # creates JUMP.xcodeproj (not committed)
open JUMP.xcodeproj
```

Core logic lives in the `JumpKit` Swift package and is tested without launching the app:

```sh
swift test --package-path Packages/JumpKit
```

### Code signing (important for development)

JUMP needs the Accessibility permission, and macOS ties that permission to the app's code signature. The default ad-hoc signature changes on every build, so the permission is lost after each rebuild.

To keep it, sign with your own (free) Apple Development certificate:

1. Xcode → Settings → Accounts → add your Apple ID.
2. `cp Config/Signing.local.xcconfig.example Config/Signing.local.xcconfig`
3. Set your `DEVELOPMENT_TEAM` in that file (it is git-ignored).
4. `xcodegen generate`

## Project layout

```
JUMP/                 macOS app target (SwiftUI menu bar agent)
Packages/JumpKit/     core logic as a Swift package (testable without the app)
Config/               shared and local build settings
project.yml           XcodeGen project definition
```

## Credits

JUMP builds on ideas and code from [Vimac](https://github.com/nchudleigh/vimac) by Dexter Leng and contributors (GPL-3.0), the open-source predecessor of [Homerow](https://www.homerow.app).

## License

[GPL-3.0](LICENSE)
