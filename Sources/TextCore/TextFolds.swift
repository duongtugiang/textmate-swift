import Foundation

/// Per-line information consumed by the fold algorithm (4.S3) — a port of
/// `folds_t::value_t` from `layout/src/folds.{h,cc}`.
public struct LineFoldInfo {
    /// Leading-whitespace indent in columns (tab = tabSize).
    public var indent = 0
    /// Line matches the grammar's `foldingStartMarker`.
    public var startMarker = false
    /// Line matches the grammar's `foldingStopMarker`.
    public var stopMarker = false
    /// Line begins an indented block (default: more indented than the
    /// previous non-empty line; grammars can override with
    /// `foldingIndentedBlockStart`).
    public var indentStartMarker = false
    /// For indented blocks, the indent level that *closes* the block (the
    /// previous non-empty line's indent) — equal-indent block lines must not
    /// close it, so the stack compares against the parent's level.
    public var indentStartLevel: Int?
    /// Line is ignored by indented-block folding.
    public var ignoreLine = false
    /// Line is blank (only whitespace).
    public var emptyLine = false
}

/// The fold engine — `folds_t::foldable_ranges()` ported to line indices.
public enum TextFolds {

    /// Foldable ranges as `startLine..<lastHiddenLine + 1`: the start-marker
    /// line stays visible, lines `startLine + 1 ... lastHiddenLine` hide.
    public static func foldableRanges(_ info: [LineFoldInfo]) -> [Range<Int>] {
        var result: [(start: Int, end: Int)] = []

        var regularStack: [(line: Int, indent: Int)] = []
        var indentStack: [(line: Int, indent: Int)] = []
        var emptyLineCount = 0
        let count = info.count

        for n in 0..<count {
            let line = info[n]

            while !indentStack.isEmpty,
                  !line.emptyLine, !line.ignoreLine,
                  line.indent <= indentStack.last!.indent {
                let start = indentStack.last!.line
                let end = n - 1 - emptyLineCount
                if start < end { result.append((start, end)) }
                indentStack.removeLast()
            }

            emptyLineCount = line.emptyLine && !line.indentStartMarker ? emptyLineCount + 1 : 0

            if line.startMarker {
                regularStack.append((n, line.indent))
            } else if line.indentStartMarker {
                indentStack.append((n, line.indentStartLevel ?? line.indent))
            } else if line.stopMarker {
                for i in stride(from: regularStack.count, to: 0, by: -1) where regularStack[i - 1].indent == line.indent {
                    let start = regularStack[i - 1].line
                    if start < n - 1 { result.append((start, n - 1)) }
                    regularStack.removeSubrange(0..<i)
                    break
                }
            }
        }

        for entry in indentStack {
            if entry.line < count - 1 { result.append((entry.line, count - 1)) }
        }

        result.sort { $0.start < $1.start }

        // Outermost-only pass (port of the C++ nesting filter).
        var nestingStack: [Int] = []
        var unique: [(start: Int, end: Int)] = []
        for range in result {
            while !nestingStack.isEmpty && unique[nestingStack.last!].end <= range.start {
                nestingStack.removeLast()
            }
            if !nestingStack.isEmpty && unique[nestingStack.last!].end < range.end { continue }
            nestingStack.append(unique.count)
            unique.append(range)
        }
        return unique.map { $0.start..<(max($0.end, $0.start) + 1) }
    }

    /// Leading-whitespace indent in columns (tab expands to `tabSize`).
    public static func leadingIndent(_ line: String, tabSize: Int = 4) -> Int {
        var columns = 0
        for scalar in line.unicodeScalars {
            if scalar == " " { columns += 1 }
            else if scalar == "\t" { columns += tabSize - (columns % tabSize) }
            else { break }
        }
        return columns
    }

    /// Per-line fold info for a document (grammar markers + indented folding).
    /// `startPattern`/`stopPattern` come from the grammar's root
    /// `foldingStartMarker`/`foldingStopMarker` (the legacy path the C++
    /// uses); when no markers are given, indented-block folding is the
    /// default (production TextMate ships that default in app preferences).
    public static func lineInfo(
        lines: [String],
        startPattern: String?,
        stopPattern: String?,
        tabSize: Int = 4
    ) -> [LineFoldInfo] {
        let startRegex = startPattern.flatMap { try? NSRegularExpression(pattern: $0) }
        let stopRegex = stopPattern.flatMap { try? NSRegularExpression(pattern: $0) }

        var result: [LineFoldInfo] = []
        var previousIndent = 0
        var previousHadContent = false

        for line in lines {
            var info = LineFoldInfo()
            let ns = line as NSString
            if let startRegex, startRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) != nil {
                info.startMarker = true
            }
            if let stopRegex, stopRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) != nil {
                info.stopMarker = true
            }
            info.indent = leadingIndent(line, tabSize: tabSize)
            info.emptyLine = line.unicodeScalars.allSatisfy { $0 == " " || $0 == "\t" }

            // Default indented-block folding: a non-empty line that is more
            // indented than the previous non-empty line starts a block. The
            // block closes at the previous non-empty line's indent level
            // (`indentStartLevel`), so equal-indent block lines don't close it
            // (blank lines keep the reference indent).
            if !info.emptyLine, !info.stopMarker {
                if previousHadContent && info.indent > previousIndent {
                    info.indentStartMarker = true
                    info.indentStartLevel = previousIndent
                }
                previousIndent = info.indent
                previousHadContent = true
            }

            if info.startMarker || info.stopMarker {
                info.indentStartMarker = false
                info.indentStartLevel = nil
            }
            result.append(info)
        }
        return result
    }
}
