# jump-web-perf

Objective: roadmap step 5 of `my-idea.md` — "Web areas + Chromium/Electron support" — plus reaching the native latency target, which the user made a hard priority.
Branch: `feat/web-perf` (stacked on `feat/actions`) · Delivery: ask-on-risk · Test runner: `swift test --package-path Packages/JumpKit` · Bench: `swift run -c release --package-path Packages/JumpKit jump-bench <App> [runs] [--warm]`.

## Specs

- S1 (spec §3.9 + user): "Shortcut → hints visible, native apps < 50 ms". User: "recuerda que hay que llegar al objetivo de 50, esto es super importante."
- S2 (spec §3.4): "Web areas: if `AXWebArea` supports `AXUIElementsForSearchPredicate`, run one visible-only search (Button, CheckBox, Control, Graphic, Link, RadioGroup, TextField) instead of walking the tree. Keep Vimac's per-key fallback."
- S3 (spec §3.4): "Chromium/Electron: set `AXManualAccessibility` (Electron) / `AXEnhancedUserInterface` (Chrome) lazily on the target pid only, remember which pids were touched, and restore them when JUMP quits."
- S4 (spec §3.9): "Shortcut → hints visible, browsers/Electron < 150 ms (hard deadline, partial results allowed)".

## Tasks

- [x] T1 · S1 · inline · cut AX round-trips: role-decided actionability, custom actions ignored, list rows as one target, row sampling, batched children · 8d8344e · RED→GREEN per rule
- [x] T2 · S1 · inline · overlay + AX client warm-up, end-to-end latency log · c630524 · measured
- [x] T3 · S1 · inline · jump-bench developer tool (spaced runs by default) · 06aed60
- [x] T4 · S2 · inline · web-area search predicate traversal · 4c1feaf · RED→GREEN
- [x] T5 · S3, S4 · inline · Chromium/Electron accessibility enabler · b044f3d · RED→GREEN, live verified

## Log

- L1 (2026-10-24): "Hay combinaciones de teclas que ya tengo reservada puede ser por eso que la x no estaba llegando, de todas maneras sigamos con el paso 5. Y recuerda que hay que llegar al objetivo de 50, esto es super importante."
- L2: Process note: this document was created after the first perf edits (should have been before the first write).
- L3: Measurements (release, Finder ~ list view, 2 displays). Baseline: 598 nodes, 1,780 IPC calls, 81 ms warm / 52-83 ms spaced; app end-to-end 59-70 ms (128 ms first). Rejected experiments: parallel subtree scan (65→60 ms; target app serializes AX on its main thread), user-interactive QoS queue (no measurable gain, reverted). Kept: batched AXChildren (81→65), role-decided actions + custom "Name:" actions ignored, rows as one target (42 ms warm, 138→86 hints: also fixes the duplicate-hint-per-row bug), no children prefetch under AXScrollArea (2,473-item folder 56.8→49.5), row sampling (598→116 nodes), leading-label rows (Settings 190→140 nodes), overlay backing-store + text warm-up and AX client warm-up at launch.
- L4: End-to-end now (Release, "on screen after"): Finder 21-28 ms, System Settings 33-51 ms, Notes 23-32 ms; first activation after launch 33-40 ms (was 74-80). Bench runs are spaced by default because back-to-back runs are ~30% optimistic.
- L5: Behavior changes (deliberate, for S1): list rows are one hint at their leading side (cells/labels no longer separate hints); toolbar items exposing only custom actions get no hint; tables whose first 3 rows hold no control (or only a leading label button) hint later rows without reading them — a control appearing only after row 3 gets no own hint (its row does).
- L6: Web (Release, end-to-end or bench): Safari HN 842→198 nodes, 90→38 ms (one search call, 2.4 ms); Arc HN 0 web hints → 186 hints, 26 ms (accepts AXManualAccessibility, no AXEnhancedUserInterface needed); Obsidian 3 → 31 hints, 15-20 ms; Zen (Firefox) 146 hints, 96 ms (within the 150 ms browser budget). Finder rejects AXManualAccessibility (-25205), so trying it on every activated app is harmless. Restore on quit: see L9 — the "back to 3 elements" observation does NOT prove the restore. The flag cannot be read back (Arc: unsupported; Obsidian: always 0).
- L7: Not covered: AXEnhancedUserInterface path (no Chrome/Brave/Edge installed to test); force-quit/crash of JUMP leaves flags on (willTerminate is not called on SIGKILL). 70/70 tests.
- L8: Independent verifier: S1-S4 pass, no confirmed blocker. Fixed its probable regression (disclosure triangles hid their row hint and disabled row sampling; RED→GREEN) plus advisories: quit apps are forgotten (pid reuse), overlay prepare() skipped while hints are visible. Open advisories: AX writes on activation run on the main thread (≤0.25 s per hung app); restore does not check whether another tool (VoiceOver) had AXEnhancedUserInterface on; read-only text areas now always get hints; web search call not bounded by the deadline. Recheck: Finder unchanged (86 hints). 72/72 tests.
- L9 (2026-10-24): user asked to fix the four open advisories before step 6. Fixed: (1) flag writes run off the main thread (`enable` is async, writes in a `@concurrent` helper); (2) AXEnhancedUserInterface is read first and left alone (never restored) when already on; (3) AXTextField/AXTextArea need a real action again — Terminal output no longer hinted (live: 3 hints, no text area); (4) the per-key web search fallback stops at the scan deadline. RED→GREEN, 75/75 tests.
- L10: Correction of L6: turning AXManualAccessibility off by hand leaves Obsidian's tree exposed (31 elements before and after), so Electron/Chromium keep or drop the tree on their own schedule and the tree is not evidence of restore. Restore correctness rests on unit tests (only apps JUMP changed get `false`). Also observed: a hotkey ~2 s after launching an Electron app can show a partial tree (3 hints) while it is still being built; the next press shows all (31).
