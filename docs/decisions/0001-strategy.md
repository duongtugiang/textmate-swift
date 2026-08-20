# ADR 0001 — Modernization strategy

Status: accepted
Date: 2026-08-20

## Context

TextMate (~92k LOC) is Objective-C++: C++ for low-level data structures
(`buffer`, `text`, `parse`, `layout`, `editor`) and Objective-C++ for the GUI.
It builds with a custom ninja/`rave` system and depends on boost, capnproto,
sparsehash, ragel, and Onigmo. We want a simpler, Swift-native codebase.

## Decisions

1. **Greenfield Swift rewrite** — a fresh project rather than an in-place port.
   Reason: converting 92k LOC in place fights Swift idioms and keeps the custom
   build system indefinitely. A rewrite lets us ship a working core fast.
2. **Bridge the C++ core** — keep `buffer`/`text`/`layout` and expose them through
   a thin C-style/Objective-C++ bridge instead of reimplementing in Swift. Reason:
   these are the hard-won, well-tested performance-critical pieces.
3. **AppKit (`NSView`)** for the text area — custom rendering control, matching
   TextMate's own approach; SwiftUI is unsuitable for custom text layout.
4. **Bare-editor MVP** — open, edit, select, undo/redo, save. Everything else
   (syntax highlighting, folding, snippets, bundles) is deferred and staged.

## Consequences

- We carry C++ + a bridge layer for the foreseeable future; Swift interop with
  templates is limited, so bridge APIs must be small and concrete.
- Fast time-to-first-working-editor; low-risk incremental feature growth.
