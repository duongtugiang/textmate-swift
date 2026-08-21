import Foundation

// MARK: - Onigmo anchor emulation (4.T2 spike decision)

/// The grammar engine (Frameworks/parse) relies on Oniguruma anchors that
/// ICU (NSRegularExpression) does not provide. This wrapper emulates them by
/// rewriting the pattern per search:
///
///  - `\G` (OP_BEGIN_POSITION) — matches at the *search start* (`msa->gpos`).
///    Emulated as a lookbehind of the escaped line prefix up to the search
///    start (`(?<=prefix)`, or `(?<!.)` at offset 0). When NOTGPOS is set the
///    C++ passes `gpos = nullptr` so `\G` never matches → rewritten to `(?!)`.
///  - `\A` (OP_BEGIN_BUF) — matches at buffer start; disabled by NOTBOS
///    (non-first line). Emulated natively by ICU; rewritten to `(?!)` when
///    `firstLine` is false.
///  - `\z` (OP_END_BUF) — matches at buffer end; disabled by NOTEOS (line
///    ends with `\n`). Emulated natively; rewritten to `(?!)` when the line
///    ends with a newline.
///  - `\Z` (OP_SEMI_END_BUF) — buffer end or before the final newline; NOT
///    gated by NOTEOS. ICU's native `\Z` matches this exactly.
///  - `^` (OP_BEGIN_LINE) — matches at buffer start (gated only by NOTBOL,
///    which the engine never sets) or after a newline. ICU's
///    `.anchorsMatchLines` matches this.
///  - `$` (OP_END_LINE) — matches before a newline, or at buffer end when
///    the buffer is not newline-terminated. ICU matches this.
///
/// Verified against Onigmo's `regexec.c` (OP_BEGIN_LINE/OP_END_LINE/
/// OP_BEGIN_BUF/OP_END_BUF/OP_SEMI_END_BUF/OP_BEGIN_POSITION) and TextMate's
/// `regexp.cc` `search()` (gpos = NOTGPOS ? nullptr : from).
public struct TextRegex {

    /// A single regex match over a line, with capture ranges in UTF-16 units
    /// (matching NSRegularExpression's coordinate space).
    public struct Match {
        public var begin: Int
        public var end: Int
        /// Index 0 = whole match; `NSNotFound` = group did not participate.
        public var captureRanges: [NSRange]
        /// The line the match was made against (for nested parses).
        public let line: String

        public init(begin: Int, end: Int, captureRanges: [NSRange], line: String) {
            self.begin = begin
            self.end = end
            self.captureRanges = captureRanges
            self.line = line
        }

        public var isEmpty: Bool { begin == end }

        /// `match_t::empty(i)` — whether capture `i` (default 0) is empty.
        public func isEmpty(_ i: Int) -> Bool {
            begin(i) == end(i)
        }

        /// `match_t::did_match(i)` — whether group `i` participated.
        public func didMatch(_ i: Int) -> Bool {
            i < captureRanges.count && captureRanges[i].location != NSNotFound
        }

        public func begin(_ i: Int) -> Int {
            didMatch(i) ? captureRanges[i].location : end
        }

        public func end(_ i: Int) -> Int {
            didMatch(i) ? captureRanges[i].location + captureRanges[i].length : end
        }

        /// `match_t::operator[]` — capture text, or nil when unmatched.
        public func captureText(_ i: Int) -> String? {
            guard didMatch(i) else { return nil }
            return (line as NSString).substring(with: captureRanges[i])
        }

        /// `match_t::capture_indices()` — string-keyed (begin, end) pairs for
        /// all participating groups, string-sorted like the C++ multimap.
        public func captureIndices() -> [(key: String, begin: Int, end: Int)] {
            var res: [(key: String, begin: Int, end: Int)] = []
            for i in 0..<captureRanges.count where didMatch(i) {
                res.append((String(i), begin(i), end(i)))
            }
            res.sort { $0.key < $1.key }
            return res
        }

        /// `match_t::captures()` — name → text map (used by format expansion).
        public func captures() -> [String: String] {
            var res: [String: String] = [:]
            for i in 0..<captureRanges.count {
                if let text = captureText(i) {
                    res[String(i)] = text
                }
            }
            return res
        }
    }

    public let source: String

    public init(_ source: String) {
        self.source = source
    }

    /// The Onigmo anchor semantics for one search.
    public struct SearchOptions {
        /// `\G` enabled (NOTGPOS clear) — `stack->anchor == i`.
        public var gposEnabled: Bool
        /// `\A` enabled (NOTBOS clear) — first line of the buffer.
        public var firstLine: Bool
        /// `\z` disabled (NOTEOS set) — line ends with a newline.
        public var noteos: Bool

        public init(gposEnabled: Bool, firstLine: Bool, noteos: Bool) {
            self.gposEnabled = gposEnabled
            self.firstLine = firstLine
            self.noteos = noteos
        }

        /// `anchor_options(firstLine, isGPos, first, last)`.
        public static func anchors(firstLine: Bool, isGPos: Bool, lineEndsWithNewline: Bool) -> SearchOptions {
            SearchOptions(gposEnabled: isGPos, firstLine: firstLine, noteos: lineEndsWithNewline)
        }
    }

    /// `regexp::search(ptrn, first, last, from, to, options)` — leftmost match
    /// at or after `from`, in UTF-16 units.
    public func search(line: String, from: Int, options: SearchOptions) -> Match? {
        let ns = line as NSString
        guard from <= ns.length else { return nil }
        let rewritten = TextRegex.rewrite(source, searchStart: from, line: line, options: options)
        guard let re = try? NSRegularExpression(pattern: rewritten, options: .anchorsMatchLines) else {
            return nil
        }
        // Search the FULL string (not the range starting at `from`): ICU
        // anchors `\A` to the start of the search range, whereas Onigmo
        // anchors it to the buffer start. Take the leftmost match at/after
        // `from` instead.
        let all = re.matches(in: line, range: NSRange(location: 0, length: ns.length))
        guard let result = all.first(where: { $0.range.location >= from }) else {
            return nil
        }
        var caps: [NSRange] = []
        for i in 0..<result.numberOfRanges {
            caps.append(result.range(at: i))
        }
        return Match(begin: result.range.location, end: result.range.location + result.range.length, captureRanges: caps, line: line)
    }

    // MARK: - Pattern rewriting

    /// Rewrite an Onigmo pattern for ICU, applying the anchor emulation.
    /// The rewrite is per-search because `\G` embeds the escaped line prefix
    /// up to the search start.
    static func rewrite(_ pattern: String, searchStart: Int, line: String, options: SearchOptions) -> String {
        let chars = Array(pattern)
        var out = ""
        var i = 0
        var inClass = false
        while i < chars.count {
            let ch = chars[i]
            if ch == "\\" && i + 1 < chars.count {
                let next = chars[i + 1]
                switch next {
                case "G":
                    if options.gposEnabled {
                        if searchStart == 0 {
                            out += "(?<!.)"  // no char before this offset = offset 0
                        } else {
                            let prefix = (line as NSString).substring(with: NSRange(location: 0, length: searchStart))
                            out += "(?<=" + TextRegex.escapeLiteral(prefix) + ")"
                        }
                    } else {
                        out += "(?!)"  // NOTGPOS: `\G` never matches
                    }
                    i += 2
                    continue
                case "A":
                    out += options.firstLine ? "\\A" : "(?!)"
                    i += 2
                    continue
                case "z":
                    out += options.noteos ? "(?!)" : "\\z"
                    i += 2
                    continue
                case "Z":
                    out += "\\Z"  // ICU native matches Onigmo's OP_SEMI_END_BUF
                    i += 2
                    continue
                default:
                    out += "\\"
                    out.append(next)
                    i += 2
                    continue
                }
            }
            if ch == "[" && !inClass {
                inClass = true
                out.append(ch)
            } else if ch == "]" && inClass {
                inClass = false
                out.append(ch)
            } else if inClass {
                out.append(ch)
            } else {
                out.append(ch)
            }
            i += 1
        }
        return out
    }

    /// Escape literal text for embedding in an ICU pattern. Mirrors
    /// `escape_regexp` (regexp.cc) — note ICU rejects `\>` so we only escape
    /// the classic metacharacter set.
    static func escapeLiteral(_ s: String) -> String {
        var out = ""
        for ch in s.unicodeScalars {
            if "\\^$|()[]{}.*+?".unicodeScalars.contains(ch) {
                out += "\\"
            }
            out.unicodeScalars.append(ch)
        }
        return out
    }
}
