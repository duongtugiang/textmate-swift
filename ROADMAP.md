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

## Phase 0 — Scaffold & build

| Status | ID | Kind | Title | Effort | Depends on | Gate | Issue |
|---|---|---|---|---|---|---|---|
| [x] | 0.S1 | story | One-command build & test with green CI badge | S | — | CI green | [#1](https://github.com/duongtugiang/textmate-swift/issues/1) |
| [x] | 0.S2 | story | Run the ported TextMate core tests against the new engine | S | 0.T3 | storage tests green | [#2](https://github.com/duongtugiang/textmate-swift/issues/2) |
| [x] | 0.T1 | task | SwiftPM skeleton: `TextCore` library + tests + executable | S | — | — | [#3](https://github.com/duongtugiang/textmate-swift/issues/3) |
| [x] | 0.T2 | task | Swift piece-tree storage (insert/erase/substring, line index) | M | 0.T1 | — | [#4](https://github.com/duongtugiang/textmate-swift/issues/4) |
| [x] | 0.T3 | task | Port `buffer/t_storage.cc` + `t_indexed_map.cc` (9 tests) → green | M | 0.T2 | 9/9 | [#5](https://github.com/duongtugiang/textmate-swift/issues/5) |
| [x] | 0.T4 | task | Undo engine (command stack, coalescing) | M | 0.T2 | — | [#6](https://github.com/duongtugiang/textmate-swift/issues/6) |
| [x] | 0.T5 | task | Test-compatibility matrix: inventory all 88 files / 291+ cases, classify | S | — | — | [#7](https://github.com/duongtugiang/textmate-swift/issues/7) |
| [x] | 0.T6 | task | Arm CI pipeline (`swift build` + `swift test`, guarded) | S | 0.T1 | CI green | [#8](https://github.com/duongtugiang/textmate-swift/issues/8) |

## Phase 1 — Text model

| Status | ID | Kind | Title | Effort | Depends on | Gate | Issue |
|---|---|---|---|---|---|---|---|
| [ ] | 1.S1 | story | Type and delete text; cursor follows edits | M | 1.T1 | buffer/text .cc green | [#9](https://github.com/duongtugiang/textmate-swift/issues/9) |
| [ ] | 1.S2 | story | Undo/redo my edits (⌘Z / ⇧⌘Z) | M | 0.T4 | — | [#10](https://github.com/duongtugiang/textmate-swift/issues/10) |
| [ ] | 1.T1 | task | Position mapping: line/column ↔ UTF-16 offset | M | 0.T2 | — | [#11](https://github.com/duongtugiang/textmate-swift/issues/11) |
| [ ] | 1.T2 | task | Port remaining pure-C++ buffer tests + `text` utf8/decode/encode/ctype (~20) → green | M | 0.T3, 1.T1 | ~20/~20 | [#12](https://github.com/duongtugiang/textmate-swift/issues/12) |
| [ ] | 1.T3 | task | UTF-8 validation & normalize utilities (spec: `text/utf8`, `text/transcode`) | M | 1.T2 | — | [#13](https://github.com/duongtugiang/textmate-swift/issues/13) |

## Phase 2 — Editing, rendering & delivery (AppKit)

| Status | ID | Kind | Title | Effort | Depends on | Gate | Issue |
|---|---|---|---|---|---|---|---|
| [ ] | 2.S1 | story | See a file's text rendered in a window | L | 1.T1 | layout tests green | [#14](https://github.com/duongtugiang/textmate-swift/issues/14) |
| [ ] | 2.S2 | story | Select text with mouse and keyboard | L | 2.S1 | editor selection tests | [#15](https://github.com/duongtugiang/textmate-swift/issues/15) |
| [ ] | 2.S3 | story | Scroll smoothly through large documents (≥10 MB) | M | 2.S1 | — | [#16](https://github.com/duongtugiang/textmate-swift/issues/16) |
| [ ] | 2.S4 | story | Undo/redo wired into the UI | S | 1.S2, 2.S2 | — | [#17](https://github.com/duongtugiang/textmate-swift/issues/17) |
| [ ] | 2.S5 | story | As a maintainer: cut a release with one tag → signed, notarized .dmg | S | 2.T4 | — | [#18](https://github.com/duongtugiang/textmate-swift/issues/18) |
| [x] | 2.T1 | task | XcodeGen `project.yml` app target for the AppKit UI | M | 0.T1 | — | [#19](https://github.com/duongtugiang/textmate-swift/issues/19) |
| [ ] | 2.T2 | task | Port `layout` (10) + `editor` (9) tests + `t_buffer.mm` GUI suites → green | XL | 2.T1 | 19+/19+ | [#20](https://github.com/duongtugiang/textmate-swift/issues/20) |
| [ ] | 2.T3 | task | Rendering perf check against C++ layout baseline (feeds ADR 0002) | M | 2.T2 | — | [#21](https://github.com/duongtugiang/textmate-swift/issues/21) |
| [ ] | 2.T4 | task | CD pipeline: tag → xcodebuild release → codesign → notarize → .dmg → GitHub Release | M | 2.T1 | — | [#22](https://github.com/duongtugiang/textmate-swift/issues/22) |

## Phase 3 — Document layer

| Status | ID | Kind | Title | Effort | Depends on | Gate | Issue |
|---|---|---|---|---|---|---|---|
| [ ] | 3.S1 | story | Open a file (⌘O, picker, common encodings) | M | 1.S1 | encoding/transcode tests | [#23](https://github.com/duongtugiang/textmate-swift/issues/23) |
| [ ] | 3.S2 | story | Save my changes (⌘S, dirty-state, unsaved-close prompt) | M | 3.S1 | — | [#24](https://github.com/duongtugiang/textmate-swift/issues/24) |
| [ ] | 3.S3 | story | Work with multiple files via tabs/windows | M | 3.S1 | — | [#25](https://github.com/duongtugiang/textmate-swift/issues/25) |
| [ ] | 3.T1 | task | Document controller: open/save lifecycle, dirty tracking | M | 3.S1 | — | [#26](https://github.com/duongtugiang/textmate-swift/issues/26) |
| [ ] | 3.T2 | task | Port encoding/transcode tests + relevant `io`/`file` suites → green | M | 3.T1 | — | [#27](https://github.com/duongtugiang/textmate-swift/issues/27) |

## Phase 4+ — Signature features

| Status | ID | Kind | Title | Effort | Depends on | Gate | Issue |
|---|---|---|---|---|---|---|---|
| [ ] | 4.S1 | story | Line-number gutter | S | 2.S1 | — | [#28](https://github.com/duongtugiang/textmate-swift/issues/28) |
| [ ] | 4.S2 | story | Syntax highlighting from `.tmLanguage` grammars | XL | 4.T1 | parse + scope tests | [#29](https://github.com/duongtugiang/textmate-swift/issues/29) |
| [ ] | 4.S3 | story | Code folding | L | 4.S2 | — | [#30](https://github.com/duongtugiang/textmate-swift/issues/30) |
| [ ] | 4.S4 | story | Find & replace | L | 2.S2 | — | [#31](https://github.com/duongtugiang/textmate-swift/issues/31) |
| [ ] | 4.S5 | story | Snippets | L | 4.S2 | — | [#32](https://github.com/duongtugiang/textmate-swift/issues/32) |
| [ ] | 4.S6 | story | Bundles & preferences | XL | 4.S2 | — | [#33](https://github.com/duongtugiang/textmate-swift/issues/33) |
| [ ] | 4.T1 | task | Port `regexp` (41) + `scope` (13) + `parse` (4) tests → green | XL | 4.T2 | 58/58 | [#34](https://github.com/duongtugiang/textmate-swift/issues/34) |
| [ ] | 4.T2 | task (spike) | Grammar-engine spike: Onigmo port vs Swift regex strategy | L | — | — | [#35](https://github.com/duongtugiang/textmate-swift/issues/35) |
| [ ] | 4.T3 | task | Port `bundles` (5) tests → green | M | 4.T2 | 5/5 | [#36](https://github.com/duongtugiang/textmate-swift/issues/36) |
| [ ] | 4.T4 | task | Out-of-scope disposition: document every skipped suite in the matrix | S | 0.T5 | matrix 100% | [#37](https://github.com/duongtugiang/textmate-swift/issues/37) |

---

## Test compatibility gate

The Swift implementation must pass the **original TextMate test suites**. All
**88 test files / 291+ test cases** are inventoried in
[docs/test-matrix.md](docs/test-matrix.md) and classified as: *port now*,
*AppKit-bound*, *C++-internal*, or *out-of-scope* (with rationale — never silently
dropped). Each phase's slice must be 100% green (ported to Swift XCTest and run in
CI) before the phase is marked done. Suites are translated verbatim where possible;
AppKit-bound `.mm` suites are adapted where macOS API drift requires it, and the
adaptation is recorded in the matrix.

## Complexity / risk register

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Scope creep (92k LOC original) | High | High | Strict phase gating; MVP gate = "edit + save a file"; out-of-scope disposition in matrix |
| C++↔Swift bridging friction (templates, `basic_tree_t`, `indexed_map_t`) | High | High | Ported test suites as executable spec; ADR 0002 decision after perf gate 2.T3 |
| Grammar stack (`regexp`/`scope`/`parse`, Onigmo) is large | High | Med | Deferred to Phase 4; isolated behind engine; spike 4.T2 first |
| `layout` is deeply tied to ObjC types (fonts, CGContext) | Med | High | AppKit phase ports `layout` tests; incremental, documented adaptations |
| Porting effort per test higher than expected | Med | Med | Matrix tracks per-suite counts; effort tags S–XL on every item |
