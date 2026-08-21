// Reproducible rendering-perf baseline (roadmap 2.T3 / issue #21).
//
// Measures the exact code paths the editor uses on a ≥10 MB document:
//   - construct      building the Buffer from text chunks (open path)
//   - lineLookup     lineIndex(atUtf8Offset:)   — caret/selection rendering
//   - positionLookup lineColumn(atUtf8Offset:)  — caret X placement
//   - visibleRender  the drawText path: two line lookups + visible substring
//   - lineRangeAll   lineRange(_:) for every line (selection rendering)
//   - randomEdit     insert + erase at random offsets (typing path)
//
// Run:  swift run -c release Benchmarks
// Deterministic RNG (SplitMix64) → results are reproducible across runs.

import Foundation
import Darwin
import TextCore

// Unbuffered stdout so crash traces are visible (stdout is block-buffered
// when piped, and a SIGSEGV discards the buffer).
setvbuf(stdout, nil, _IONBF, 0)

// MARK: - Deterministic RNG (SplitMix64)

struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - Timing

func time(_ body: () -> Void) -> Double {
    let clock = ContinuousClock()
    let start = clock.now
    body()
    let elapsed = start.duration(to: clock.now)
    return Double(elapsed.components.attoseconds) / 1e18 // seconds
}

/// Median of `repeats` runs of `body`, in milliseconds.
func measure(_ name: String, repeats: Int = 5, _ body: () -> Void) -> Double {
    var samples: [Double] = []
    for _ in 0..<repeats {
        samples.append(time(body) * 1000)
    }
    samples.sort()
    let median = samples[samples.count / 2]
    return median
}

// MARK: - Corpus (~10 MB of code-like text)

func makeCorpus() -> String {
    var lines: [String] = []
    lines.reserveCapacity(120_000)
    for i in 0..<120_000 {
        let fn = "func compute_\(i % 1000)_\(i)("
        let body = "  let value = clamp(input\(i % 97) + bias, 0, limit)  // handle case \(i)"
        lines.append("\(fn) { \(body) }\n")
    }
    return lines.joined()
}

// MARK: - Benchmarks

func benchConstruct(_ corpus: String) -> Double {
    measure("construct", repeats: 3) {
        var buffer = Buffer()
        // Chunked inserts like the document-open path.
        let chunks = stride(from: 0, to: corpus.count, by: 4096).map { offset -> String in
            let start = corpus.index(corpus.startIndex, offsetBy: offset)
            let end = corpus.index(start, offsetBy: min(4096, corpus.distance(from: start, to: corpus.endIndex)))
            return String(corpus[start..<end])
        }
        for chunk in chunks {
            buffer.insert(chunk, at: buffer.utf8Length)
        }
    }
}

func benchLineLookup(_ buffer: Buffer) -> Double {
    var rng = SplitMix64(seed: 42)
    let offsets = (0..<20_000).map { _ in Int(rng.next() % UInt64(buffer.utf8Length)) }
    return measure("lineLookup") {
        var sink = 0
        for offset in offsets {
            sink &+= buffer.lineIndex(atUtf8Offset: offset)
        }
        precondition(sink >= 0)
    }
}

func benchPositionLookup(_ buffer: Buffer) -> Double {
    var rng = SplitMix64(seed: 43)
    let offsets = (0..<20_000).map { _ in Int(rng.next() % UInt64(buffer.utf8Length)) }
    return measure("positionLookup") {
        var sink = 0
        for offset in offsets {
            let (line, column) = buffer.lineColumn(atUtf8Offset: offset)
            sink &+= line &+ column
        }
        precondition(sink >= 0)
    }
}

/// The drawText path from EditorView: for each scroll position, two line
/// lookups + one substring of the visible region + per-line split. No actual
/// CG drawing (that is bounded by screen pixels, not document size).
func benchVisibleRender(_ buffer: Buffer) -> Double {
    let visibleLines = 60
    var rng = SplitMix64(seed: 44)
    let maxLine = buffer.lineCount - visibleLines
    let scrollLines = (0..<50).map { _ in Int(rng.next() % UInt64(maxLine)) }
    return measure("visibleRender") {
        var sink = 0
        for firstLine in scrollLines {
            let lastLine = firstLine + visibleLines
            let byteStart = buffer.lineRange(firstLine).lowerBound
            let byteEnd = buffer.lineRange(lastLine).upperBound
            let text = buffer.substring(byteStart..<byteEnd)
            var lineCount = 0
            var index = text.startIndex
            while index < text.endIndex {
                if text[index] == "\n" { lineCount += 1 }
                index = text.index(after: index)
            }
            sink &+= lineCount
        }
        precondition(sink > 0)
    }
}

func benchLineRangeAll(_ buffer: Buffer) -> Double {
    let lines = buffer.lineCount
    return measure("lineRangeAll") {
        var sink = 0
        for line in 0..<lines {
            sink &+= buffer.lineRange(line).lowerBound &+ buffer.lineRange(line).upperBound
        }
        precondition(sink >= 0)
    }
}

func benchRandomEdit(_ buffer: inout Buffer) -> Double {
    var rng = SplitMix64(seed: 45)
    // 5,000 insert + erase pairs per run. The buffer drifts between runs
    // (net ±5000 bytes at random offsets) which is exactly the point —
    // we measure steady-state edit cost at a fixed document scale.
    return measure("randomEdit", repeats: 3) {
        for _ in 0..<5_000 {
            let at = Int(rng.next() % UInt64(buffer.utf8Length))
            buffer.insert("x", at: at)
            let eraseAt = Int(rng.next() % UInt64(buffer.utf8Length))
            if eraseAt < buffer.utf8Length {
                buffer.erase(eraseAt..<(eraseAt + 1))
            }
        }
    }
}

// MARK: - Main

func format(_ ms: Double) -> String {
    if ms < 1 { return String(format: "%.3f ms", ms) }
    return String(format: "%.2f ms", ms)
}

func pad(_ s: String, _ width: Int) -> String {
    s.count >= width ? s : s + String(repeating: " ", count: width - s.count)
}

let corpus = makeCorpus()
print("Corpus: \(corpus.utf8.count / 1_048_576) MB (\(corpus.utf8.count) bytes, "
    + "\(corpus.filter { $0 == "\n" }.count) lines)")

let constructMs = benchConstruct(corpus)
print("construct done")

// Build the benchmark buffer once (outside the timed region).
var buffer = Buffer()
let chunks = stride(from: 0, to: corpus.count, by: 4096).map { offset -> String in
    let start = corpus.index(corpus.startIndex, offsetBy: offset)
    let end = corpus.index(start, offsetBy: min(4096, corpus.distance(from: start, to: corpus.endIndex)))
    return String(corpus[start..<end])
}
for chunk in chunks {
    buffer.insert(chunk, at: buffer.utf8Length)
}
let bytes = buffer.utf8Length
let lineCount = buffer.lineCount
print("buffer built: \(bytes) bytes, \(lineCount) lines")

print("Buffer: \(bytes) bytes, \(lineCount) lines")
print("")

let rows: [(String, Double)] = [
    ("construct (open path)", constructMs),
    ("lineLookup ×20k", benchLineLookup(buffer)),
    ("positionLookup ×20k", benchPositionLookup(buffer)),
    ("visibleRender ×50 windows", benchVisibleRender(buffer)),
    ("lineRangeAll ×\(lineCount)", benchLineRangeAll(buffer)),
]

print("render/lookup benches done")
var mutable = buffer
let editMs = benchRandomEdit(&mutable)
mutable.breakUndoCoalescing()
print("randomEdit done")

print(pad("benchmark", 28) + pad("median", 10))
print(String(repeating: "-", count: 38))
for (name, ms) in rows {
    print(pad(name, 28) + pad(format(ms), 10))
}
print(pad("randomEdit ×10k ops", 28) + pad(format(editMs), 10))

// Derived rates.
let renderPerWindow = rows[3].1 / 50
print("")
print("visible window (60 lines): " + format(renderPerWindow))
print(String(format: "line lookups/s: %.0fk", 20_000 / (rows[1].1 / 1_000) / 1_000))
print(String(format: "edits/s (insert+erase pairs): %.0f", 10_000 / (editMs / 1_000)))
