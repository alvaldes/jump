# jump-hint-themes

Objective: selectable hint themes, a Liquid Glass option and a configurable hint size, chosen in Settings.
Branch: `feat/hint-themes` (from `main` ecc1187, worktree `../jump-worktrees/hint-themes`) · Delivery: ask-on-risk · Test runner: `swift test --package-path Packages/JumpKit` (also in CI).

## Specs

- S1 (user, approving the proposed table): "me gusta esto" — themes Dark (current look, default), Light, System (follows macOS light/dark), Accent (system accent color), Classic (Vimium yellow). Same shape for every theme; only colors change.
- S2: every theme keeps label text readable: contrast ratio of text against fill of at least 4.5:1, including every system accent color (Accent picks black or white text).
- S3 (user): "ademas me gustaria agregrar un tema liquid glass o una opcion para activar liquid glass con estos temas" — decision: a Liquid Glass toggle that applies to any theme (glass tinted with the theme's color), off by default.
- S4 (user): "algo que tambien debe tener es poder configurar el tamanno de los hint" — decision: a size setting (label font size, default 11 pt = current), pills scale with it.
- S5: choices persist across launches and apply to the next hints shown; invalid stored values fall back to the defaults.
- S6: the < 50 ms hotkey → hints target (spec §3.9) still holds with the default appearance; Liquid Glass latency is measured and reported.

## Tasks

- [ ] T1 · S1, S2, S4, S5 · inline · HintTheme palettes + size in JumpKit, settings persistence, Settings UI, overlay wiring
- [ ] T2 · S3, S5, S6 · inline · Liquid Glass rendering path (NSGlassEffectView per visible hint) + toggle; latency measured live

## Log

- L1 (2026-10-25): "me gusta esto pero ademas me gustaria agregrar un tema liquid glass o una opcion para activar liquid glass con estos temas. Ademas algo que tambien debe tener es poder configurar el tamanno de los hint"
- L2: Current look lives in `HintsView.Style` (one draw pass for every hint). Glass cannot be drawn in that pass: NSGlassEffectView is a compositor effect, so T2 needs one view per visible hint, which risks the 50 ms target with hundreds of hints. Hint-mode `lastSummary` / log `total` include `overlay.show`, so it measures that cost.
