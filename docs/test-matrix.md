# Test-Compatibility Matrix

The core contract of this project: **the Swift implementation must pass the original
TextMate test suites**, ported to Swift XCTest and run in CI. This file inventories
every suite, classifies it, and tracks its status. A phase is "done" only when its
slice of this matrix is 100% green.

## Classification

- **Port now** — pure C++ logic, translate verbatim to XCTest.
- **AppKit-bound** — `.mm`/GUI suites; port/adapt during the AppKit phase (drift documented).
- **C++-internal** — tests C++ internals with no Swift equivalent; re-expressed against
  the Swift equivalent structure or explicitly superseded (recorded).
- **Out of scope** — subsystem not part of the modernization (e.g. SCM, updater);
  listed here with rationale, never silently dropped.

Legend: `[ ]` not started · `[~]` in progress · `[x]` green · `—` not applicable.

## Core frameworks (Phase 0–4 gates)

| Framework | Test files | Cases | Classification | Porting task | Status | Notes |
|---|---|---|---|---|---|---|
| `buffer` | 3 (`t_buffer.mm`, `t_indexed_map.cc`, `t_storage.cc`) | 27 | Port now (.cc) + AppKit-bound (.mm) | 0.T3 (storage/indexed_map, 9) · 2.T2 (`t_buffer.mm`) | 0.T3: [x] · 2.T2: [ ] | `t_storage.cc` = 5 cases, `t_indexed_map.cc` = 4 — both green (0.T3, 16 ported tests); `.mm` needs AppKit (2.T2) |
| `text` | 13 (`t_utf8`, `t_decode`, `t_encode`, `t_ctype`, `t_format`, `t_indent`, `t_split`, `t_tokenize`, `t_transcode`, `t_trim`, `t_wrap`, `t_case`, `t_ranker`) | 34 | Port now | 1.T2 (utf8/decode/encode/ctype subset) · rest: Phase 3–4 | utf8/decode/encode/ctype: [x] · rest: [ ] | `t_utf8` (5), `t_decode` (2), `t_encode` (1), `t_ctype` (1) = 9 cases ported to Swift (10 XCTest methods) and green in 1.T2; `t_format`/`t_indent`/`t_split`/`t_tokenize`/`t_transcode`/`t_trim`/`t_wrap`/`t_case`/`t_ranker` deferred to Phase 3–4 |
| `undo` | 0 (no dedicated suite) | 0 | — | verified via `buffer`/`editor` cases | — | Undo behavior covered by ported buffer/editor tests |
| `scope` | 3 | 13 | Port now | 4.T1 | [ ] | Grammar stack |
| `regexp` | 8 | 41 | Port now | 4.T1 | [ ] | Largest suite; Onigmo semantics |
| `parse` | 4 | 4 | Port now | 4.T1 | [ ] | Grammar parsing |
| `bundles` | 2 | 5 | Port now | 4.T3 | [ ] | Depends on grammar-engine spike 4.T2 |
| `layout` | 4 (`t_basic_tree_delta.cc`, `t_basic_tree_numeric.cc`, `t_basic_tree_range.cc`, `gui_layout.mm`) | 10 | Port now (.cc) + AppKit-bound (.mm) | 2.T2 | [ ] | `basic_tree` suites ported against Swift equivalent |
| `editor` | — | 9 | Port now | 2.T2 | [ ] | Selection/undo semantics — undo engine behavior now covered by Swift `UndoTests` (9) and selection behavior verified in-app (2.S2); the `.cc` suite itself still to port |

## Remaining frameworks — full inventory (task 0.T5)

All remaining suites (88 test files total across `Frameworks/`, 291+ cases) are
enumerated here when 0.T5 lands. Known non-core frameworks with tests include:
`io`, `plist`, `file`, `ns`, `OakFoundation`, `OakAppKit`, `OakTextView`,
`OakFilterList`, `OakTabBarView`, `OakSystem`, `network`, `scm`, `updater`,
`SoftwareUpdate`, `HTMLOutput`, `Find`, `BundleEditor`, `BundlesManager`,
`DocumentWindow`, `FileBrowser`, `MenuBuilder`, `Command`, `CommitWindow`,
`Preferences`, `encoding`, `theme`, `selection`, `command`, `regexp`, `scope`,
`parse`, `bundles`, `editor`, `layout`, `buffer`, `text`, `undo`, `settings`,
`authorization`, `crash`, `license`, `OakDebug`, `plist`, `cf`, `io`, `ns`,
`file`, `network`, `updater`, `scm`, `HTMLOutputWindow`, `OakCommand`.

Classification guidance for the full pass:
- Core text pipeline (storage, text, editor, layout, scope/parse/regexp/bundles) → port.
- UI shell (Oak*AppKit, DocumentWindow, FileBrowser, Find, BundlesManager…) → port
  during/after their UI phase, or out-of-scope if not part of the MVP roadmap.
- Network/SCM/updater/HTMLOutput/SoftwareUpdate → **out of scope** (not in roadmap),
  documented with rationale.
- `OakDebug`, `authorization`, `crash`, `license`, `settings` → utilities; port as needed.

## Out-of-scope disposition

| Framework(s) | Rationale | Status |
|---|---|---|
| `scm`, `network`, `updater`, `SoftwareUpdate`, `HTMLOutput`, `HTMLOutputWindow` | Not part of the bare-editor MVP roadmap | [ ] (confirm in 4.T4) |
| `OakAppKit`/`OakTextView` internals not needed by the Swift UI | Swift/AppKit replaces the ObjC UI shell | [ ] (confirm in 4.T4) |

## Progress

| Phase | Gate slice | Result |
|---|---|---|
| 0 | 9/9 (storage + indexed_map) | ✅ green — 16 ported tests + 6 engine tests |
| 1 | utf8/decode/encode/ctype 9/9 (+ buffer .cc done in Phase 0) | ✅ utf8/decode/encode/ctype green (9 cases, 10 Swift tests); +18 engine tests (9 position mapping, 9 undo) → 50 total |
| 2 | 19+/19+ (layout + editor + `t_buffer.mm`) | pending — UI stories 2.S1/2.S2/2.S4 delivered (engine render, selection, engine undo in app); the layout/editor `.cc` port itself is 2.T2 |
| 3 | encoding/transcode + `io`/`file` subsets | pending |
| 4 | 58/58 (regexp + scope + parse) + 5/5 (bundles) | pending |
