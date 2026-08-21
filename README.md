# TextMate (Swift)

A from-scratch, simplified modernization of [TextMate](https://github.com/textmate/textmate),
rewritten in Swift. The goal is a clean, maintainable editor that starts with a bare
editor core and grows feature-by-feature.

## Decisions (v0)

| Topic | Decision |
|---|---|
| Strategy | Greenfield Swift rewrite |
| Text engine | Swift-native core, behaviorally validated against the original C++ test suites |
| UI layer | AppKit (`NSView`) for the text area |
| MVP scope | Bare editor: open, edit, select, undo/redo, save |

See [docs/decisions/](docs/decisions/) for rationale (ADR 0002 — C++ bridge vs.
Swift-first — is decided at the Phase 2 perf gate).

## Status

**Phases 0–3 live** — a document-based AppKit editor whose document surface is a
custom `NSView` that renders directly from the `TextCore` piece tree (no `NSTextView`
in the pipeline): multiple files in tabs/windows (NSDocument), encoding-aware open/save
(UTF-8/16/32 with BOMs, Windows-1252, MacRoman, Latin-1), unsaved-changes sheets on
close/quit, engine-backed undo/redo (⌘Z / ⇧⌘Z), cut/copy/paste, mouse + keyboard
selection, word select, caret navigation, and a dirty-state indicator. `TextCore` ships
with piece-tree storage, command-based undo with typing coalescing, UTF-8 utilities,
position mapping (byte ↔ UTF-16 ↔ line/column), charset transcoding, and path
utilities — **68 tests green** (38 ported from the original C++ suites).

The full backlog (18 stories + 19 tasks across 5 phases) lives in
[GitHub Issues](https://github.com/duongtugiang/textmate-swift/issues); the phase
index is [ROADMAP.md](ROADMAP.md).

## Build & run

Requirements: Xcode 15+ (macOS 13+ target), [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
# Engine: build + test
swift build
swift test

# App: generate the Xcode project, then build
xcodegen generate
xcodebuild -project TextMateSwift.xcodeproj -scheme TextMateSwift -configuration Release build
open Build/Products/Release/TextMateSwift.app
```

Large-document smoothness (≥10 MB) and O(log n) position lookup are the next milestone
(tree-backed storage — issues #11, #14, #16).

## Project practices

- **Backlog**: every story/task is a GitHub issue, labeled by kind + effort + phase,
  assigned to a phase milestone. `ROADMAP.md` is the index; `docs/issues/backlog.json`
  is the generation source.
- **Test compatibility gate**: the Swift implementation must pass the original
  TextMate test suites (88 files / 291+ cases), ported to Swift and run in CI.
  Tracking: [docs/test-matrix.md](docs/test-matrix.md).
- **Workflow & Definition of Done**: see [CONTRIBUTING.md](CONTRIBUTING.md) —
  branch-per-issue, conventional commits, PRs that close issues, CI green.
- **CI/CD**: GitHub Actions — CI builds + tests on every push/PR; tagged releases
  produce a signed + notarized `.dmg`. See `.github/workflows/`.
- **Board**: kanban at GitHub Projects (link in the repo sidebar).

## Layout

```
Sources/TextCore/        Swift text engine (storage, undo, encoding)
Sources/TextMateSwift/   AppKit app (window, menu, file actions)
Tests/TextCoreTests/     ported TextMate suites + engine tests
project.yml              XcodeGen source of truth (app + framework targets)
docs/decisions/          architecture decision records
docs/issues/             backlog manifest + issue map
docs/test-matrix.md      original-TextMate test compatibility tracking
ROADMAP.md               phases, milestones, gates, and complexity tracking
```

## License

Derived from TextMate (GPL-3.0-or-later); this project inherits GPL-3.0-or-later.
