# Roadmap

Single source of truth for the port. Each item has a status, an effort estimate,
and a note on dependencies. Update statuses as work progresses; keep this file in
the repo so it survives across sessions.

Effort key: **S** < 1 day · **M** 1–3 days · **L** 3–7 days · **XL** > 1 week.

## Legend

- [ ] not started
- [~] in progress
- [x] done

## Phase 0 — Scaffold & build

| # | Task | Effort | Status | Depends on |
|---|---|---|---|---|
| 0.1 | Create Xcode/SwiftPM project skeleton | S | [~] | — |
| 0.2 | Add C++ core as a build target (submodule or vendored) | M | [ ] | 0.1 |
| 0.3 | Write Objective-C++ bridging layer (`buffer`/`text` → Swift) | M | [ ] | 0.2 |
| 0.4 | Smoke test: create/edit a buffer from Swift | S | [ ] | 0.3 |

## Phase 1 — Text model (bridged)

| # | Task | Effort | Status | Depends on |
|---|---|---|---|---|
| 1.1 | Swift wrapper over `ng::buffer_t` (insert/delete/read) | M | [ ] | 0.3 |
| 1.2 | Line index + position ↔ UTF-16 offset mapping | M | [ ] | 1.1 |
| 1.3 | Undo/redo stack | M | [ ] | 1.1 |

## Phase 2 — Editing & rendering (AppKit)

| # | Task | Effort | Status | Depends on |
|---|---|---|---|---|
| 2.1 | Custom `NSView` text renderer (draw glyphs from buffer) | L | [ ] | 1.2 |
| 2.2 | Cursor + selection + mouse/keyboard input | L | [ ] | 2.1 |
| 2.3 | Scrolling + large-document performance check | M | [ ] | 2.1 |
| 2.4 | Wire undo/redo into UI (⌘Z / ⇧⌘Z) | S | [ ] | 1.3, 2.2 |

## Phase 3 — Document layer & app shell

| # | Task | Effort | Status | Depends on |
|---|---|---|---|---|
| 3.1 | Open/save file (UTF-8 + common encodings) | M | [ ] | 1.1 |
| 3.2 | Document controller: tabs / multiple windows | M | [ ] | 2.2 |
| 3.3 | Main menu + basic preferences | M | [ ] | 3.2 |

## Phase 4+ — Signature features (later, in this order)

| # | Task | Effort | Status | Depends on |
|---|---|---|---|---|
| 4.1 | Line-number gutter | S | [ ] | 2.1 |
| 4.2 | Grammar-based syntax highlighting (`parse` + Onigmo) | XL | [ ] | 1.2, 2.1 |
| 4.3 | Folding | L | [ ] | 4.2 |
| 4.4 | Find/replace | L | [ ] | 2.2 |
| 4.5 | Snippets | L | [ ] | 4.2 |
| 4.6 | Bundles & preferences system | XL | [ ] | 4.2 |

## Complexity / risk register

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| C++↔Swift bridging friction (templates, `basic_tree_t`, `indexed_map_t`) | High | High | Expose a small C-style API per framework; keep templates on the C++ side |
| Onigmo/grammar engine is large | High | Med | Defer until Phase 4; isolate behind the bridge |
| `ng::layout_t` is deeply tied to ObjC types (fonts, CGContext) | Med | High | Port incrementally; consider a Swift layout layer later |
| 92k LOC scope creep | High | High | Strictly stage features; MVP gate = "edit + save a file" |
