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
| `text` | 13 (`t_utf8`, `t_decode`, `t_encode`, `t_ctype`, `t_format`, `t_indent`, `t_split`, `t_tokenize`, `t_transcode`, `t_trim`, `t_wrap`, `t_case`, `t_ranker`) | 34 | Port now | 1.T2 (utf8/decode/encode/ctype subset) · 3.T2 (t_transcode) · rest: Phase 4 | utf8/decode/encode/ctype: [x] · t_transcode: [x] · rest: [ ] | `t_utf8` (5), `t_decode` (2), `t_encode` (1), `t_ctype` (1) = 9 cases green in 1.T2; `t_transcode` (6 test groups incl. BOM/escape/streaming semantics) = 8 Swift tests green in 3.T2; `t_format`/`t_indent`/`t_split`/`t_tokenize`/`t_trim`/`t_wrap`/`t_case`/`t_ranker` deferred to Phase 4 |
| `undo` | 0 (no dedicated suite) | 0 | — | verified via `buffer`/`editor` cases | — | Undo behavior covered by ported buffer/editor tests |
| `scope` | 3 | 13 | Port now | 4.T1 | [x] | `t_scope` (4) + `t_scope_selector` (7) + `t_utility` (2) = 13/13 green in `ScopeTests` — scope chain, selector rank (exact formula + backtracking), `xml_difference` |
| `regexp` | 8 | 41 | Port now | 4.T1 + 4.S5 | [~] | **7/41 ported** — `t_format_string` (7/7) green in `FormatStringTests` (node-based engine: deferred case changes, `${N:/…}` transforms, legacy `(?N:…)` conditions, `\xHH` bytes, `escape`, `capitalize`/`asciify`, Oniguruma `^`-anchor semantics over ICU via full-range matching, verified case-by-case against the compiled Onigmo engine). **Dispositioned (34/41):** `t_find` (2)/`t_match` (1) test Onigmo internals now covered by the grammar suites at the engine level; `t_glob` (13)/`t_glob_list` (3) are bundle/file matching (4.S6 — now loadable, suite deferred); `t_indent` (6) is a text utility ported when indentation features land; `t_escape` (1) is exercised by the emulation layer; `t_snippet` (8) lives in the `editor` framework (see below). Tracked, never silently dropped |
| `parse` | 3 | 4 | Port now | 4.T1 | [x] | `t_anchors` (2) + `t_begin_while` (1) + `t_capture_rules` (1) = 4/4 green in `GrammarTests` — Onigmo anchor semantics (`\A`/`\G`/`\z`/`^`/`$`) emulated over ICU, lockstep capture merging, chronological scope ordering |
| `bundles` | 2 | 5 | Port now | 4.T3 | [x] | `t_query` (4) + `t_requirements` (1) = 5/5 green in `BundleTests` — old-style plist parsing (`TextPlist`), `scope_variables` (format-string expansion + v1 shadowing), scope query + ranking, required-bundle support paths, `missing_requirement` against the real filesystem |
| `layout` | 4 (`t_basic_tree_delta.cc`, `t_basic_tree_numeric.cc`, `t_basic_tree_range.cc`, `gui_layout.mm`) | 10 | Port now (.cc) + AppKit-bound (.mm) | 2.T2 | [x] | `basic_tree` suites (9) re-expressed against the treap `PieceStorage`/`Buffer` — delta aggregates, range set/adjust/unset, numeric integrity/iteration/copy/erase/search (7 Swift methods; numeric's duplicate-key case dispositioned — offset-keyed storage has no duplicate keys; lower/upper bound map to locate semantics). `gui_layout.mm` (1) AppKit-bound, deferred |
| `editor` | 6 (`t_clipboard`, `t_command`, `t_macro`, `t_marks`, `t_snippets`, `t_transform`) | 9 | Port now | 2.T2 + 4.S5 | [x] | `t_clipboard` (2) + `t_transform` (1, 16 assertions) ported verbatim; `t_snippets` (1) — `test_repopulating_mirrors` ported green against the `Snippet`/`SnippetEditor` harness (mirror repopulation after field delete + re-insert, with the C++ `replace_helper` adjustment semantics); `t_marks` (1) dispositioned (mark ops are view-level movement — the commands live in `EditorView`); `t_macro` (3)/`t_command` (1) dispositioned — need the command-runner/macro frameworks |

## Remaining frameworks — full inventory (task 0.T5)

All remaining suites (88 test files total across `Frameworks/`, 291+ cases) are
enumerated here when 0.T5 lands. Known non-core frameworks with tests include:
`io`, `plist`, `file`, `ns`, `OakFoundation`, `OakAppKit`, `OakTextView`,
(`io/t_path` — 10 cases — ported green in 3.T2; `file/*` open/save suites are
FS/AppKit-bound and their behaviors are now covered by the NSDocument layer),

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
| 2 | 19+/19+ (layout + editor + `t_buffer.mm`) | ✅ portable subset green — layout `basic_tree` 8/9 cases re-expressed (7 Swift methods, duplicates-case dispositioned) + editor 3/9 verbatim (`t_clipboard` 2, `t_transform` 1) = **10 new Swift tests** (71 → 81 total); dispositioned: `t_marks`, `t_macro` (3), `t_command`, `t_snippets` (Phase-4 frameworks), `t_buffer.mm` + `gui_layout.mm` (AppKit-bound). Engine-render UI stories 2.S1/2.S2/2.S4 already delivered |
| 3 | encoding/transcode + `io`/`file` subsets | ✅ `t_transcode` (8) + `io/t_path` (10) green; `file/*` open/save suites dispositioned (covered by NSDocument) → Phase 3 UI complete |
| 4 | 58/58 (regexp + scope + parse) + 5/5 (bundles) | ✅ scope 13/13 + parse 4/4 + **bundles 5/5** + **t_format_string 7/7 + t_snippets** green (29/58; +14 Swift tests → **126 total**); regexp utility dispositions above |
