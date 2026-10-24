# JUMP

Keyboard-driven screen navigation for macOS. Press a shortcut, every clickable element gets a short label, type the label to click it. No mouse required.

> Status: early development. See [`my-idea.md`](my-idea.md) for the design spec and roadmap.

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
