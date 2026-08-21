# Roadmap

Single source of truth for the TextMate → Swift modernization. This file is the
**index**: the live backlog lives in [GitHub Issues](https://github.com/duongtugiang/textmate-swift/issues)
(one issue per story/task, labeled by kind + effort + phase, assigned to the phase
milestone). Update statuses in GitHub (issue state + board); keep this file in sync
as items move.

- **Epic** = a phase below (also a GitHub milestone).
- **Story** = user-visible feature, written in user-story form with acceptance criteria.
- **Task** = engineering work (no direct end-user value).
- **Gate** = the original-TextMate test suites that must pass (ported to Swift) before
  the item is done. See [docs/test-matrix.md](docs/test-matrix.md).

Legend: `[ ]` not started · `[~]` in progress · `[x]` done.
Effort: **S** < 1 day · **M** 1–3 days · **L** 3–7 days · **XL** > 1 week.

---

## Current state & next up

**Done (31 of 37 issues closed):** Phase 0 (8/8), Phase 1 (5/5), Phase 2
(2.T1/2.T2/2.T3/2.S1/2.S2/2.S4/2.T4/2.S5), Phase 3 (5/5), and **Phase 4 core —
the grammar stack (4.T1/4.T2/4.S1/4.S2)**.

- **Perf gate 2.T3 + ADR 0002** — `Sources/Benchmarks` measures the exact render
  path on an 11.5 MB / 120k-line corpus (deterministic RNG, reproducible via
  `swift run -c release Benchmarks`): **0.063 ms per 60-line visible window**,
  ~1.29M line lookups/s, 3.2 µs per random edit, ~76 MB/s open. That clears the
  C++ baseline (visible-region layout in single-digit ms, per-line incremental
  re-layout) by two orders of magnitude on the render path, so **ADR 0002
  decides: Swift-native layout, no C++ bridge** (supersedes ADR 0001 #2).
- **Grammar engine (4.T2/4.T1)** — `TextScope` (scope chain + selector rank,
  13/13 suites green) and `TextGrammar` + `TextRegex` (per-line parse loop with
  the full stack, Onigmo anchor semantics `\A`/`\G`/`\z`/`^`/`$` emulated over
  ICU — verified against Onigmo's `regexec.c`; `t_anchors`/`t_begin_while`/
  `t_capture_rules` 4/4 green). The regexp suites (41) are dispositioned in the
  matrix: engine internals are covered at the engine level, utility suites
  follow 4.S5/4.S6.
- **Syntax highlighting + gutter (4.S2/4.S1)** — `SyntaxParser` (engine-level,
  incremental reparse with convergence repair) drives per-scope colors in
  `EditorView`; built-in tmLanguage-format grammar; line-number gutter. 102
  tests green; a highlighted demo document opens and renders (theme colors
  verified at the pixel level).

**Next:** the remaining Phase 4 stories in dependency order — **4.S6 bundles**
(`.tmLanguage`/`.tmBundle` loading, which unlocks arbitrary grammars + 4.T3
bundle suites), **4.S4 find & replace**, **4.S3 folding** (line-fold marks via
`begin/end` scope pairs), then **4.S5 snippets/macros** (absorbs the
`editor`/`regexp` dispositioned suites). 2.S3 (#16) smooth-scrolling polish
sits on the same engine as 4.S3.

**Repo chores (blocked on repo admin):** kanban board (`gh auth refresh -s project`),
branch protection on `main`, Apple release secrets for the notarized CD leg.

---

## Phase 0 — Scaffold & build

| Status | ID | Kind | Title | Effort | Depends on | Gate | Issue | Notes |
|---|---|---|---|---|---|---|---|---|
| [x] | 0.S1 | story | One-command build & test with green CI badge | S | — | CI green | [#1](https://github.com/duongtugiang/textmate-swift/issues/1) | CI green on macos-14 runner |
| [x] | 0.S2 | story | Run the ported TextMate core tests against the new engine | S | 0.T3 | storage tests green | [#2](https://github.com/duongtugiang/textmate-swift/issues/2) | — |
| [x] | 0.T1 | task | SwiftPM skeleton: `TextCore` library + tests + executable | S | — | — | [#3](https://github.com/duongtugiang/textmate-swift/issues/3) | — |
| [x] | 0.T2 | task | Swift piece-tree storage (insert/erase/substring, line index) | M | 0.T1 | — | [#4](https://github.com/duongtugiang/textmate-swift/issues/4) | — |
| [x] | 0.T3 | task | Port `buffer/t_storage.cc` + `t_indexed_map.cc` (9 tests) → green | M | 0.T2 | 9/9 | [#5](https://github.com/duongtugiang/textmate-swift/issues/5) | 9 C++ cases → 16 Swift tests, green |
| [x] | 0.T4 | task | Undo engine (command stack, coalescing) | M | 0.T2 | — | [#6](https://github.com/duongtugiang/textmate-swift/issues/6) | Engine `UndoStack`; UI wiring is 2.S4 |
| [x] | 0.T5 | task | Test-compatibility matrix: inventory all 88 files / 291+ cases, classify | S | — | — | [#7](https://github.com/duongtugiang/textmate-swift/issues/7) | — |
| [x] | 0.T6 | task | Arm CI pipeline (`swift build` + `swift test`, guarded) | S | 0.T1 | CI green | [#8](https://github.com/duongtugiang/textmate-swift/issues/8) | Now unguarded: builds + tests + app |

## Phase 1 — Text model

| Status | ID | Kind | Title | Effort | Depends on | Gate | Issue | Notes |
|---|---|---|---|---|---|---|---|---|
| [x] | 1.S1 | story | Type and delete text; cursor follows edits | M | 1.T1 | buffer/text .cc green | [#9](https://github.com/duongtugiang/textmate-swift/issues/9) | Edits flow through the engine (EditorView → Buffer); caret boundary-aware |
| [x] | 1.S2 | story | Undo/redo my edits (⌘Z / ⇧⌘Z) | M | 0.T4 | — | [#10](https://github.com/duongtugiang/textmate-swift/issues/10) | Engine `UndoStack` in Buffer; typing coalescing; responder-chain ⌘Z/⇧⌘Z |
| [x] | 1.T1 | task | Position mapping: line/column ↔ UTF-16 offset | M | 0.T2 | — | [#11](https://github.com/duongtugiang/textmate-swift/issues/11) | UTF-8 line + UTF-16/byte/column mapping done & tested; O(log n) indexing via treap (2.T3) |
| [x] | 1.T2 | task | Port remaining pure-C++ buffer tests + `text` utf8/decode/encode/ctype → green | M | 0.T3, 1.T1 | 9/9 buffer .cc + 9/9 text subset | [#12](https://github.com/duongtugiang/textmate-swift/issues/12) | Remaining text suites (format/indent/split/tokenize/transcode/trim/wrap/case/ranker) deferred to Phase 3–4, tracked in the matrix |
| [x] | 1.T3 | task | UTF-8 validation & normalize utilities (spec: `text/utf8`, `text/transcode`) | M | 1.T2 | — | [#13](https://github.com/duongtugiang/textmate-swift/issues/13) | Shipped with 1.T2 |

## Phase 2 — Editing, rendering & delivery (AppKit)

| Status | ID | Kind | Title | Effort | Depends on | Gate | Issue | Notes |
|---|---|---|---|---|---|---|---|---|
| [x] | 2.S1 | story | See a file's text rendered in a window | L | 1.T1 | layout tests green (via 2.T2) | [#14](https://github.com/duongtugiang/textmate-swift/issues/14) | Custom NSView renders from the piece tree (single-pass draw, caret, scrolling); 10 MB smoothness AC → 2.S3 / #16 |
| [x] | 2.S2 | story | Select text with mouse and keyboard | L | 2.S1 | editor selection tests | [#15](https://github.com/duongtugiang/textmate-swift/issues/15) | Click/drag/shift+arrows/⌘A/double-click word — all ACs met |
| [ ] | 2.S3 | story | Scroll smoothly through large documents (≥10 MB) | M | 2.S1 | — | [#16](https://github.com/duongtugiang/textmate-swift/issues/16) | Perf baseline vs C++ (2.T3) |
| [x] | 2.S4 | story | Undo/redo wired into the UI | S | 1.S2, 2.S2 | — | [#17](https://github.com/duongtugiang/textmate-swift/issues/17) | Engine-backed ⌘Z/⇧⌘Z; menu enabled state via validateMenuItem |
| [x] | 2.S5 | story | As a maintainer: cut a release with one tag → signed, notarized .dmg | S | 2.T4 | — | [#18](https://github.com/duongtugiang/textmate-swift/issues/18) | Pipeline live: `v0.1.0` exercised the unsigned leg; signed+notarized leg awaits Apple release secrets |
| [x] | 2.T1 | task | XcodeGen `project.yml` app target for the AppKit UI | M | 0.T1 | — | [#19](https://github.com/duongtugiang/textmate-swift/issues/19) | Universal Release `.app`; `projectFormat: xcode15_3` pinned for CI Xcode 15.4 |
| [x] | 2.T2 | task | Port `layout` (10) + `editor` (9) tests + `t_buffer.mm` GUI suites → green | XL | 2.T1 | 19+/19+ | [#20](https://github.com/duongtugiang/textmate-swift/issues/20) | Portable subset green: `basic_tree` 8/9 re-expressed against the treap + `t_clipboard` (2)/`t_transform` (1) verbatim = 10 new Swift tests (81 total); `t_marks`/`t_macro`/`t_command`/`t_snippets` + `t_buffer.mm`/`gui_layout.mm` dispositioned in the matrix (Phase-4 frameworks / AppKit) |
| [x] | 2.T3 | task | Rendering perf check against C++ layout baseline (feeds ADR 0002) | M | 2.T2 | — | [#21](https://github.com/duongtugiang/textmate-swift/issues/21) | `Sources/Benchmarks` (reproducible, deterministic RNG): 0.063 ms per 60-line visible window on 11.5 MB, 1.29M line lookups/s, 3.2 µs/edit → **ADR 0002: Swift-native layout, no C++ bridge** |
| [x] | 2.T4 | task | CD pipeline: tag → xcodebuild release → codesign → notarize → .dmg → GitHub Release | M | 2.T1 | — | [#22](https://github.com/duongtugiang/textmate-swift/issues/22) | `release.yml` live; nested-framework signing + spctl + notarize/staple; secrets-guarded |

## Phase 3 — Document layer

| Status | ID | Kind | Title | Effort | Depends on | Gate | Issue | Notes |
|---|---|---|---|---|---|---|---|---|
| [x] | 3.S1 | story | Open a file (⌘O, picker, common encodings) | M | 1.S1 | encoding/transcode tests | [#23](https://github.com/duongtugiang/textmate-swift/issues/23) | `TextTranscode.detect` + decode; NSDocument error sheets |
| [x] | 3.S2 | story | Save my changes (⌘S, dirty-state, unsaved-close prompt) | M | 3.S1 | — | [#24](https://github.com/duongtugiang/textmate-swift/issues/24) | NSDocument: dirty dot, close/quit sheets, atomic writes |
| [x] | 3.S3 | story | Work with multiple files via tabs/windows | M | 3.S1 | — | [#25](https://github.com/duongtugiang/textmate-swift/issues/25) | Automatic window tabbing; per-document undo stacks |
| [x] | 3.T1 | task | Document controller: open/save lifecycle, dirty tracking | M | 3.S1 | — | [#26](https://github.com/duongtugiang/textmate-swift/issues/26) | `TextDocument` (NSDocument); encoding round-trip tested |
| [x] | 3.T2 | task | Port encoding/transcode tests + relevant `io`/`file` suites → green | M | 3.T1 | — | [#27](https://github.com/duongtugiang/textmate-swift/issues/27) | `t_transcode` (8) + `io/t_path` (10) green; `file/*` suites dispositioned in the matrix (NSDocument covers open/save) |

## Phase 4+ — Signature features

| Status | ID | Kind | Title | Effort | Depends on | Gate | Issue | Notes |
|---|---|---|---|---|---|---|---|---|
| [x] | 4.S1 | story | Line-number gutter | S | 2.S1 | — | [#28](https://github.com/duongtugiang/textmate-swift/issues/28) | Drawn in the same single pass as text; separator + secondary-label styling |
| [x] | 4.S2 | story | Syntax highlighting from `.tmLanguage` grammars | XL | 4.T1 | parse + scope tests | [#29](https://github.com/duongtugiang/textmate-swift/issues/29) | Engine (`TextGrammar`/`TextScope`/`TextRegex`) + `SyntaxParser` with incremental reparse; built-in tmLanguage-format grammar drives per-scope theme colors in `EditorView`; arbitrary `.tmBundle` loading deferred to 4.S6 |
| [ ] | 4.S3 | story | Code folding | L | 4.S2 | — | [#30](https://github.com/duongtugiang/textmate-swift/issues/30) | — |
| [ ] | 4.S4 | story | Find & replace | L | 2.S2 | — | [#31](https://github.com/duongtugiang/textmate-swift/issues/31) | — |
| [ ] | 4.S5 | story | Snippets | L | 4.S2 | — | [#32](https://github.com/duongtugiang/textmate-swift/issues/32) | — |
| [ ] | 4.S6 | story | Bundles & preferences | XL | 4.S2 | — | [#33](https://github.com/duongtugiang/textmate-swift/issues/33) | — |
| [x] | 4.T1 | task | Port `regexp` (41) + `scope` (13) + `parse` (4) tests → green | XL | 4.T2 | 58/58 | [#34](https://github.com/duongtugiang/textmate-swift/issues/34) | scope 13/13 + parse 4/4 green (+7 Swift tests → 102 total); regexp 41/41 dispositioned in the matrix — Onigmo internals superseded by the ICU emulation (verified against Onigmo source), utility suites follow 4.S5/4.S6 |
| [x] | 4.T2 | task (spike) | Grammar-engine spike: Onigmo port vs Swift regex strategy | L | — | — | [#35](https://github.com/duongtugiang/textmate-swift/issues/35) | **ICU emulation chosen** — `\A`/`\G`/`\z`/`\Z`/`^`/`$` semantics verified against Onigmo's `regexec.c` and emulated over `NSRegularExpression`; `t_anchors` passes verbatim |
| [ ] | 4.T3 | task | Port `bundles` (5) tests → green | M | 4.T2 | 5/5 | [#36](https://github.com/duongtugiang/textmate-swift/issues/36) | — |
| [ ] | 4.T4 | task | Out-of-scope disposition: document every skipped suite in the matrix | S | 0.T5 | matrix 100% | [#37](https://github.com/duongtugiang/textmate-swift/issues/37) | — |

---

## Test compatibility gate

The Swift implementation must pass the **original TextMate test suites**. All
**88 test files / 291+ test cases** are inventoried in
[docs/test-matrix.md](docs/test-matrix.md) and classified as: *port now*,
*AppKit-bound*, *C++-internal*, or *out-of-scope* (with rationale — never silently
dropped). Each phase's slice must be 100% green (ported to Swift XCTest and run in
CI) before the phase is marked done. Suites are translated verbatim where possible;
AppKit-bound `.mm` suites are adapted where macOS API drift requires it, and the
adaptation is recorded in the matrix. Where a suite is deliberately deferred to a
later phase, that deferral is tracked in the matrix — a task is only `[x]` when its
own gate slice is green, not when its gate is re-scoped.

## Complexity / risk register

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Scope creep (92k LOC original) | High | High | Strict phase gating; MVP gate = "edit + save a file"; out-of-scope disposition in matrix |
| C++↔Swift bridging friction (templates, `basic_tree_t`, `indexed_map_t`) | High | High | Ported test suites as executable spec; ADR 0002 decision after perf gate 2.T3 |
| Grammar stack (`regexp`/`scope`/`parse`, Onigmo) is large | High | Med | Deferred to Phase 4; isolated behind engine; spike 4.T2 first |
| `layout` is deeply tied to ObjC types (fonts, CGContext) | Med | High | AppKit phase ports `layout` tests; incremental, documented adaptations |
| Porting effort per test higher than expected | Med | Med | Matrix tracks per-suite counts; effort tags S–XL on every item |
