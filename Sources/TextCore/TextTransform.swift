import Foundation

/// Text transforms ported from `editor/src/transform.cc`.
public enum TextTransform {
    /// The four transposition alternatives from the C++ (word, comma, colon,
    /// comparison), each optionally wrapped in a bracket pair `(...)`, `[...]`,
    /// or `{...}` (bracketed alternatives first so the whole parenthesized
    /// expression — not its interior — becomes lhs/rhs).
    private static let transposePattern = try! NSRegularExpression(
        pattern: #"\A(?:[\{\(\[](\w+)(\W+)(\w+)[\}\)\]]|(\w+)(\W+)(\w+)|[\{\(\[]([^,\s]+?)(\s*,\s*)([^,\s]+?)[\}\)\]]|([^,\s]+?)(\s*,\s*)([^,\s]+?)|[\{\(\[]([^:\s]+?)(\s*:\s*)([^:\s]+?)[\}\)\]]|([^:\s]+?)(\s*:\s*)([^:\s]+?)|[\{\(\[]([^<>!=\s]+?)(\s*[<>!=]\s*)([^<>!=\s]+?)[\}\)\]]|([^<>!=\s]+?)(\s*[<>!=]\s*)([^<>!=\s]+?))\z"#)

    /// Port of `transform::transpose`: swaps the two terms around a comma,
    /// colon, comparison, or word separator (keeping brackets attached to the
    /// expression); falls back to reversing code points for a single line, or
    /// reversing the line order for multi-line input.
    public static func transpose(_ source: String) -> String {
        // Split into lines, each retaining its trailing newline (text::to_lines).
        var lines: [String] = []
        var rest = Substring(source)
        while let nl = rest.firstIndex(of: "\n") {
            lines.append(String(rest[...nl]))
            rest = rest[rest.index(after: nl)...]
        }
        if !rest.isEmpty { lines.append(String(rest)) }
        let hasNewline = !source.isEmpty && source.last == "\n"
        let singleLine = lines.count == 1 || (lines.count == 2 && lines[1].isEmpty)

        if singleLine {
            let body = hasNewline ? String(lines[0].dropLast()) : source
            if let match = transposePattern.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)) {
                // Locate the alternative that matched (three consecutive captures).
                for start in stride(from: 1, through: 22, by: 3) {
                    let lhsRange = match.range(at: start)
                    let opRange = match.range(at: start + 1)
                    let rhsRange = match.range(at: start + 2)
                    if lhsRange.location != NSNotFound, opRange.location != NSNotFound, rhsRange.location != NSNotFound,
                       let lhsR = Range(lhsRange, in: body), let opR = Range(opRange, in: body), let rhsR = Range(rhsRange, in: body) {
                        let lhs = String(body[lhsR]), op = String(body[opR]), rhs = String(body[rhsR])
                        // Bracketed alternatives consumed the bracket pair at both ends.
                        if let first = body.first, let last = body.last, "[({".contains(first), ")]}".contains(last) {
                            return String(first) + rhs + op + lhs + String(last)
                        }
                        return rhs + op + lhs
                    }
                }
            }
            // Reverse code points (diacritics::make_range iterates UTF-8 sequences).
            let reversed = String(String.UnicodeScalarView(body.unicodeScalars.reversed()))
            return hasNewline ? reversed + "\n" : reversed
        } else {
            var result = lines.reversed().joined()
            if !hasNewline {
                let lastLength = lines[lines.count - 1].count
                result.insert("\n", at: result.index(result.startIndex, offsetBy: lastLength))
                result.removeLast()
            }
            return result
        }
    }
}
