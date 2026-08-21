# Handoff — TextMate → Swift (textmate-swift)

Read this first. It is the complete state of the project so a fresh session can
pick up and continue without re-deriving anything. Written after **v0.3.0**
(Phase 4 complete, 126 tests green, backlog empty).

---

## 1. What this project is

A from-scratch Swift/AppKit re-implementation of [TextMate](https://github.com/textmate/textmate)
(the original C++/ObjC repo is checked out at `../textmate` — **read-only
reference**). The strategy (ADR 0001) is **Swift-native**: port the engine into
a `TextCore` SwiftPM library, port the original test suites as the executable
spec, and build a new AppKit UI on top — no C++ bridge. ADR 0002 (after the
2.T3 perf gate) confirmed Swift-native layout: 0.063 ms per 60-line visible
window on an 11.5 MB doc, two orders of magnitude under the C++ frame budget.

## 2. Repo layout

```
textmate-swift/
├── Package.swift                  # SwiftPM: TextCore (lib) + Benchmarks (exe) + TextCoreTests
├── project.yml                    # XcodeGen source for the app target (TextMateSwift.app)
├── .github/workflows/
│   ├── ci.yml                     # swift build + swift test + xcodebuild (macos-14)
│   └── release.yml                # tag → xcodebuild → codesign/notarize (secrets-guarded) → dmg → release
├── Sources/
│   ├── TextCore/                  # THE ENGINE (pure Swift, unit-tested, no AppKit)
│   │   ├── Buffer.swift           #   piece-tree buffer (treap) — insert/erase/substring, line index,
│   │   │                          #   byte↔UTF-16↔line/column mapping, command-based undo w/ coalescing
│   │   ├── PieceStorage.swift     #   treap with O(log n) position aggregates
│   │   ├── IndexedMap.swift       #   offset-keyed sorted map
│   │   ├── TextEncoding.swift     #   UTF-8/16/32 + Windows-1252/MacRoman/Latin-1 detection & transcode
│   │   ├── TextScope.swift        #   scope chain, selector rank (exact formula + backtracking)
│   │   ├── TextRegex.swift        #   Onigmo anchor semantics (\A \G \z \Z ^ $) emulated over ICU
│   │   ├── TextGrammar.swift      #   tmLanguage grammar engine (per-line parse loop, begin/while/end)
│   │   ├── SyntaxParser.swift     #   incremental reparse w/ convergence repair, fold accessor
│   │   ├── TextFolds.swift        #   grammar fold markers + indented-block folding algorithm
│   │   ├── TextPlist.swift        #   old-style ASCII plist parser (.tmLanguage/.tmBundle)
│   │   ├── TextFormatString.swift #   format_string engine (node-based, deferred case changes, …)
│   │   ├── TextSnippets.swift     #   snippet engine (fields/mirrors/choices, dependency graph, stack)
│   │   ├── TextBundles.swift      #   BundleItem/BundleIndex, query, scope_variables, requirements
│   │   └── TextPath.swift         #   path utilities
│   ├── TextMateSwift/             # THE APP (AppKit, document-based)
│   │   ├── main.swift             #   menu construction (File/Edit/Bundles/Window)
│   │   ├── TextDocument.swift     #   NSDocument subclass — open/save/encoding/dirty
│   │   ├── DocumentController.swift
│   │   ├── EditorWindowController.swift
│   │   ├── EditorView.swift       #   custom NSView: renders from Buffer, caret/selection/folds/find/snippets
│   │   ├── FindBar.swift          #   ⌘F find bar (live highlights, next/prev, replace/replace-all)
│   │   └── Syntax.swift           #   app-side scope→color theme + grammar loader
│   ├── Benchmarks/main.swift      #   reproducible render-perf benchmark (swift run -c release Benchmarks)
│   └── Tests/TextCoreTests/       #   all ported + new tests (126)
├── ROADMAP.md                     #   phase index — the backlog source of truth
├── HANDOFF.md                     #   ← you are here
├── progress.html                  #   append-only log: why/what/how per commit
└── docs/
    ├── decisions/0001-strategy.md #   Swift-native port, no bridge
    ├── decisions/0002-layout-strategy.md
    ├── test-matrix.md             #   all 88 C++ suites inventoried (ported / dispositioned)
    ├── release.md                 #   how to cut a release
    ├── feature-comparison.md      #   ours vs original TextMate (menus + editing surface)
    └── next-versions.md           #   prioritized backlog for v0.4+ (mirrors the GitHub issues)
```

The **original** repo lives at `../textmate` (relative to `textmate-swift/`).
When porting something, find the C++ in `Frameworks/<name>/src|tests` and the
menu/UI in `Applications/TextMate/src` (e.g. the full main-menu table is
`AppController.mm -mainMenu`).

## 3. Build / test / run / release

```sh
cd textmate-swift
swift build && swift test          # engine — 126 tests, all green
swift run -c release Benchmarks    # render-perf baseline (2.T3)
xcodegen generate                  # app (only needed when file set changes)
xcodebuild -project TextMateSwift.xcodeproj -scheme TextMateSwift -configuration Release build
open Build/Products/Release/TextMateSwift.app
```

Release (see docs/release.md):
```sh
git tag v0.4.0 && git push origin v0.4.0   # Release workflow: build → sign → dmg → GitHub Release
```
The signed/notarized leg needs Apple secrets (Settings → Secrets); without them
the pipeline publishes an **unsigned** dmg with `BUILD_INFO.txt` stating so.

**Git hygiene:** the user's git identity is `hvt914@outlook.com` (fixed via
filter-branch). Never attribute work to anyone else. Keep commits small,
conventional (`feat/fix/docs/chore` + scope), and append a `progress.html`
entry for every user-visible commit. **Never rewrite pushed history.**

## 4. Current state (v0.3.0 — Phase 4 complete)

All **37 issues closed**, backlog empty. **126 tests green** in CI.

Engine (TextCore):
- Piece-tree buffer (treap) with O(log n) locate/insert/erase; UTF-8/16/32 +
  legacy-encoding open/save; command-based undo with typing coalescing.
- Grammar stack: TextScope (13/13 suites), TextGrammar+TextRegex (parse 4/4),
  SyntaxParser with incremental reparse.
- Bundles: TextPlist (old-style), TextFormatString (node-based format_string),
  TextBundles (query/scope_variables/requirements) — t_query 4/4 + t_requirements 1/1.
- Snippets: full snippet.cc port — t_format_string 7/7 + t_snippets green.
- TextFolds: grammar markers + indented-block folding.

App (AppKit, document-based):
- File: New/Open/Close/Save/Save As; tabs; dirty tracking; encodings.
- Edit: undo/redo, cut/copy/paste, select-all, word select, mouse+keyboard
  selection, caret navigation (word/line/home/end/vim-less).
- Find & replace (⌘F/⌘G/⇧⌘G, replace, replace-all, case toggle).
- Code folding (⌘⌥[/⌘⌥], gutter controls).
- Syntax highlighting + line-number gutter (built-in grammar + Load Grammar…).
- Snippets (Bundles ▸ Insert Snippet…; Tab/⇧Tab fields; mirrors live-update).
- Window menu (tabs, Merge All Windows).

Menus today: **TextMate, File, Edit, Bundles, Window** — no View/Navigate/Text/
File Browser/Help menus yet (see docs/next-versions.md).

## 5. Architecture notes (what the next session must know)

- **Byte offsets everywhere in the engine.** Buffer positions are UTF-8 byte
  offsets; `NSRange`/UTF-16 conversion happens at the AppKit boundary
  (`lineColumn(atUtf8Offset:)` etc.). Snippet field ranges are byte-based to
  match the C++ `std::string` semantics.
- **EditorView is a custom NSView** rendering directly from the piece tree in
  one draw pass (no NSTextView anywhere). Gutter, folds, find highlights, and
  the caret are all drawn; hit-testing maps view coords → byte offsets.
- **Edits flow through the Buffer's undo stack**; the snippet stack wraps
  edits when active (`snippetReplace` applies the C++ `replace_helper`
  adjustment semantics with the `anchor` offset).
- **Oniguruma semantics over ICU** (ADR 0002, 4.T2): `\A`/`\G`/`\z`/`\Z`/`^`/`$`
  emulated; `\p{^X}` → `\P{X}`; **ICU anchors `^` to the search region, so
  `replace()` iterates the full range** (matches(in:)) to reproduce Oniguruma's
  buffer-anchored `^`. Verified against a standalone-compiled Onigmo.
- **Perf**: `Sources/Benchmarks` (deterministic SplitMix64 RNG). If CI ever
  slows, re-check `.build/<triple>/release` vs `swift run` — `swift build
  --target` compiles but never links the executable.

## 6. Verification habits (established, keep doing)

- Ported suites are translated **verbatim**; deviations recorded in
  docs/test-matrix.md (never silently dropped).
- When a ported test fails, the C++ is the spec — read `../textmate` first,
  compile the exact C++ semantics standalone if needed (Onigmo builds with
  plain clang + `enc/unicode` include path; TextMate's syntax config is
  `ONIG_SYNTAX_RUBY` with `ONIG_OPTION_ASCII_RANGE` off).
- Pixel-verify UI claims: render the view offscreen / screenshot the window
  and analyze pixels (theme colors, caret alignment — a prior caret drift bug
  was found exactly this way; `charWidth` must use the font's true advance).
- `progress.html` is append-only — every user-visible commit gets an entry
  above the marker with why/what/how.
- Keep GitHub in sync as you go: close issues with evidence comments, verify
  CI green, keep ROADMAP/README/matrix current.

## 7. Known gaps / tech debt / gotchas

- **2.S3 (#16) smooth scrolling** is the only unfinished roadmap item (per-pixel
  scrolling, scroll-wheel support in EditorView).
- The Xcode project is generated (`xcodegen generate`) — regenerate after
  adding/removing source files.
- No CI gate for `swift run -c release Benchmarks` drift (baseline numbers are
  in ADR 0002; re-run when the render path changes).
- The signed/notarized CD leg awaits Apple secrets (docs/release.md).
- Kanban board + branch protection on `main` still need repo-admin actions
  (`gh auth refresh -s project`).
- Auto-pairing, autocomplete, multi-caret/column selection, macros,
  commands, comment/uncomment, word wrap, and the View/Navigate/Text menus are
  **not** implemented — the full inventory with acceptance criteria is in
  docs/next-versions.md (mirrored as GitHub issues).

## 8. Next session: where to start

1. Read docs/feature-comparison.md (gap analysis vs original TextMate) and
   docs/next-versions.md (prioritized v0.4+ backlog with acceptance criteria).
2. Recommended first target: **v0.4 — editing essentials** (Text menu +
   comment/uncomment + indent/outdent + line move/duplicate + case changes,
   or the View menu + word wrap + tab size/theme) — each item has its issue
   number in next-versions.md.
3. Follow the verification habits in §6 and keep GitHub/docs in sync.
