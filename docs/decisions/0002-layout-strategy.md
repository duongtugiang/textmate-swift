# ADR 0002 — Text layout strategy: Swift-native, validated by the 2.T3 perf gate

Status: accepted
Date: 2026-08-21

## Context

ADR 0001 left two options open for the performance-critical text pipeline
(`buffer` / `text` / `layout`): **bridge the C++ core** (keep the original
Objective-C++ code behind a thin Swift bridge) or **Swift-native** (rewrite in
Swift, validated behaviorally against the original test suites). Gate **2.T3**
(issue #21) was defined to settle this empirically: measure the render path on a
large document and compare against the original's documented behavior before
committing to a layout strategy.

Since ADR 0001, the whole engine was rewritten in Swift — piece-tree storage
with a treap (`PieceStorage`), O(log n) byte/newline/UTF-16 aggregates, an
O(log n) line index (`Buffer`), the grammar/scope/parse engine, and a custom
AppKit renderer (`EditorView`) that draws directly from the piece tree. The
remaining open question was whether the C++ `layout` code would be needed to
hit interactive performance on ≥10 MB documents (roadmap 2.S3 / #16).

## Baseline methodology

`Sources/Benchmarks` (SwiftPM executable, not part of the app) measures the
exact code paths the editor uses on an 11.5 MB / 120,000-line corpus
(code-like text). Deterministic RNG (SplitMix64) makes runs reproducible:

```sh
swift run -c release Benchmarks
```

| Benchmark | Measured (median) | Notes |
|---|---|---|
| construct (open path, 11.5 MB) | 151 ms | ~76 MB/s, one-time |
| lineLookup ×20k (caret/selection Y) | 15.5 ms | ~1.29M lookups/s, O(log n) |
| positionLookup ×20k (caret X) | 145 ms | ~7 µs/op (line + UTF-16 column) |
| visibleRender ×50 windows (60 lines) | 3.15 ms | **0.063 ms per visible window** |
| lineRangeAll ×120k (selection spans) | 314 ms | 2.6 µs/line, never on the hot path |
| randomEdit ×10k ops (typing) | 32 ms | 3.2 µs per insert+erase pair |

## C++ baseline

The original repository has no formal perf harness (the layout test suites are
functional, not benchmarks). Its documented behavior serves as the target: the
original re-lays-out only the lines affected by an edit and renders the visible
region in single-digit milliseconds, which is what makes ≥10 MB documents
scroll smoothly at 60 fps (a 16.6 ms frame budget).

The Swift numbers clear that bar by two orders of magnitude on the render path:
0.063 ms per 60-line visible window vs. the multi-ms C++ budget, and 3.2 µs per
random edit against a requirement that only the *affected lines* re-layout.
Position/line lookups are O(log n) via the treap and stay flat as the document
grows; nothing in the render path touches the whole document.

## Decision

**Stay Swift-native. No C++ bridge for the text pipeline.** ADR 0001's
decision #2 ("bridge the C++ core") is superseded for `buffer` / `text` /
`layout` / `parse`: the Swift engine meets the interactive-performance target
with a fraction of the code, no interop layer, and full test-suite compatibility
(102 tests green, 30+ ported from the original suites).

## Consequences

- The Swift codebase remains self-contained: no boost/capnp/sparsehash/ragel
  native dependencies, no ObjC++ bridge, one build system (SwiftPM + XcodeGen).
- Future perf work (2.S3 smooth-scrolling polish) tunes the Swift renderer
  (e.g. dirty-region tracking, avoiding per-line attributed-string allocation)
  rather than importing C++ code.
- The benchmark is the regression gate for perf-sensitive changes; run it
  before landing render-path edits.
