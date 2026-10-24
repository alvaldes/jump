# jump-web-perf

Objective: roadmap step 5 of `my-idea.md` — "Web areas + Chromium/Electron support" — plus reaching the native latency target, which the user made a hard priority.
Branch: `feat/web-perf` (stacked on `feat/actions`) · Delivery: ask-on-risk · Test runner: `swift test --package-path Packages/JumpKit` · Bench: `swift run -c release --package-path Packages/JumpKit jump-bench <App> [runs] [--warm]`.

## Specs

- S1 (spec §3.9 + user): "Shortcut → hints visible, native apps < 50 ms". User: "recuerda que hay que llegar al objetivo de 50, esto es super importante."
- S2 (spec §3.4): "Web areas: if `AXWebArea` supports `AXUIElementsForSearchPredicate`, run one visible-only search (Button, CheckBox, Control, Graphic, Link, RadioGroup, TextField) instead of walking the tree. Keep Vimac's per-key fallback."
- S3 (spec §3.4): "Chromium/Electron: set `AXManualAccessibility` (Electron) / `AXEnhancedUserInterface` (Chrome) lazily on the target pid only, remember which pids were touched, and restore them when JUMP quits."
- S4 (spec §3.9): "Shortcut → hints visible, browsers/Electron < 150 ms (hard deadline, partial results allowed)".

## Tasks

- T1 · S1 · inline · cut AX round-trips: role-decided actionability, custom actions ignored, list rows as one target, row sampling, batched children · pending commit
- T2 · S1 · inline · overlay + AX client warm-up, end-to-end latency log · pending commit
- T3 · S1 · inline · jump-bench developer tool (spaced runs by default) · pending commit
- T4 · S2 · inline · web-area search predicate traversal · pending
- T5 · S3, S4 · inline · Chromium/Electron accessibility enabler · pending

## Log

- L1 (2026-10-24): "Hay combinaciones de teclas que ya tengo reservada puede ser por eso que la x no estaba llegando, de todas maneras sigamos con el paso 5. Y recuerda que hay que llegar al objetivo de 50, esto es super importante."
- L2: Process note: this document was created after the first perf edits (should have been before the first write).
- L3: Measurements (release, Finder ~ list view, 2 displays). Baseline: 598 nodes, 1,780 IPC calls, 81 ms warm / 52-83 ms spaced; app end-to-end 59-70 ms (128 ms first). Rejected experiments: parallel subtree scan (65→60 ms; target app serializes AX on its main thread), user-interactive QoS queue (no measurable gain, reverted). Kept: batched AXChildren (81→65), role-decided actions + custom "Name:" actions ignored, rows as one target (42 ms warm, 138→86 hints: also fixes the duplicate-hint-per-row bug), no children prefetch under AXScrollArea (2,473-item folder 56.8→49.5), row sampling (598→116 nodes), leading-label rows (Settings 190→140 nodes), overlay backing-store + text warm-up and AX client warm-up at launch.
- L4: End-to-end now (Release, "on screen after"): Finder 21-28 ms, System Settings 33-51 ms, Notes 23-32 ms; first activation after launch 33-40 ms (was 74-80). Bench runs are spaced by default because back-to-back runs are ~30% optimistic.
- L5: Behavior changes (deliberate, for S1): list rows are one hint at their leading side (cells/labels no longer separate hints); toolbar items exposing only custom actions get no hint; tables whose first 3 rows hold no control (or only a leading label button) hint later rows without reading them — a control appearing only after row 3 gets no own hint (its row does).
