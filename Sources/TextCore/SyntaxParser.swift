import Foundation

/// Stack equality for incremental repair — mirrors `stack_t::operator==`
/// (parse.cc): rule, scope, while/end patterns, parent chain.
extension GrammarStack: Equatable {
    public static func == (lhs: GrammarStack, rhs: GrammarStack) -> Bool {
        if lhs.rule.ruleID != rhs.rule.ruleID { return false }
        if lhs.scope != rhs.scope { return false }
        if lhs.whilePattern?.source != rhs.whilePattern?.source { return false }
        if lhs.endPattern?.source != rhs.endPattern?.source { return false }
        if (lhs.parent == nil) != (rhs.parent == nil) { return false }
        if let lp = lhs.parent, let rp = rhs.parent, lp != rp { return false }
        return true
    }
}

/// Per-line grammar state for a document (4.S2). Parses each line with the
/// engine's `Grammar`, keeps the per-line stacks and scope maps, and repairs
/// incrementally: after an edit, re-parses from the edited line until the
/// stack converges with the previously parsed state (the C++ `buffer_t`
/// repair model).
public final class SyntaxParser {

    public private(set) var grammar: Grammar

    public private(set) var text = ""
    public private(set) var lines: [String] = []
    public private(set) var states: [GrammarStack] = []
    public private(set) var scopes: [[Int: Scope]] = []

    public init(grammar: Grammar) {
        self.grammar = grammar
    }

    /// Swap the grammar (4.S6: load a bundle grammar) and re-parse the
    /// current text from scratch.
    public func setGrammar(_ newGrammar: Grammar) {
        grammar = newGrammar
        if !text.isEmpty {
            reload(text)
        }
    }

    /// Full (re)parse — after opening a document or replacing its content.
    public func reload(_ newText: String) {
        text = newText
        lines = Self.splitLines(newText)
        states = []
        scopes = []
        var state = grammar.seed()
        for (index, line) in lines.enumerated() {
            let result = grammar.parseLine(line, stack: state, firstLine: index == 0)
            state = result.stack
            states.append(state)
            scopes.append(result.scopes)
        }
    }

    /// Apply an edit and repair incrementally: update the text, then re-parse
    /// the affected line range `fromLine...endLine` (inclusive) plus any lines
    /// until the stack converges with the previously parsed state.
    public func updateText(_ newText: String, fromLine: Int, endLine: Int) {
        text = newText
        reparse(fromLine: fromLine, endLine: endLine)
    }

    /// Incremental repair. Lines in `fromLine...endLine` (the edit's affected
    /// range) are always re-parsed; beyond `endLine` the repair stops as soon
    /// as the stack converges with the previous parse, keeping existing state.
    public func reparse(fromLine: Int, endLine: Int) {
        guard fromLine >= 0, fromLine < lines.count else { return }
        // Lines before fromLine are untouched; re-split from fromLine.
        let rest = Self.splitLines(String(text.dropFirst(prefixLengthUpTo(line: fromLine))))
        lines.replaceSubrange(fromLine..., with: rest)

        let oldStates = states
        let oldCount = oldStates.count

        // Resize the parallel arrays to match the new line count.
        if states.count > lines.count {
            states.removeSubrange(lines.count...)
            scopes.removeSubrange(lines.count...)
        }
        while states.count < lines.count {
            states.append(grammar.seed())
            scopes.append([:])
        }

        var state = fromLine > 0 ? states[fromLine - 1] : grammar.seed()
        var line = fromLine
        while line < lines.count {
            let result = grammar.parseLine(lines[line], stack: state, firstLine: line == 0)
            state = result.stack
            let converged = line > endLine && line < oldCount && result.stack == oldStates[line]
            states[line] = result.stack
            scopes[line] = result.scopes
            line += 1
            if converged {
                break
            }
        }
    }

    /// Scope map for a line, or empty.
    public func scopes(forLine line: Int) -> [Int: Scope] {
        line >= 0 && line < scopes.count ? scopes[line] : [:]
    }

    /// Split a string into lines, each retaining its trailing newline.
    private static func splitLines(_ text: String) -> [String] {
        var res: [String] = []
        let ns = text as NSString
        var i = 0
        while i < ns.length {
            let eol = ns.range(of: "\n", options: [], range: NSRange(location: i, length: ns.length - i))
            let lineEnd = eol.location == NSNotFound ? ns.length : eol.location + 1
            res.append(ns.substring(with: NSRange(location: i, length: lineEnd - i)))
            i = lineEnd
        }
        return res
    }

    private func prefixLengthUpTo(line: Int) -> Int {
        var length = 0
        for l in 0..<min(line, lines.count) {
            length += lines[l].utf16.count
        }
        return length
    }
}

/// The built-in grammar used until bundles ship (4.S6). A small
/// `.tmLanguage`-shaped plist dictionary covering comments, strings,
/// numbers, keywords, and function names — the loader (`Grammar(plist:)`)
/// is the same code path real bundle grammars will use.
public enum BuiltInGrammar {
    public static let plist: [String: Any] = [
        "scopeName": "source.simple",
        "patterns": [
            ["include": "#comments"],
            ["include": "#strings"],
            ["include": "#numbers"],
            ["include": "#keywords"],
            ["include": "#builtins"],
            ["include": "#functions"],
        ],
        "repository": [
            "comments": [
                "patterns": [
                    ["name": "comment.line", "match": "//.*$"],
                    ["name": "comment.block", "begin": "/\\*", "end": "\\*/"],
                ],
            ],
            "strings": [
                "patterns": [
                    [
                        "name": "string.quoted.double",
                        "begin": "\"",
                        "end": "\"",
                        "patterns": [["name": "constant.character.escape", "match": "\\\\."]],
                    ],
                    ["name": "string.quoted.single", "begin": "'", "end": "'"],
                ],
            ],
            "numbers": [
                "patterns": [
                    ["name": "constant.numeric", "match": "\\b(0x[0-9a-fA-F]+|\\d+(\\.\\d+)?)\\b"],
                ],
            ],
            "keywords": [
                "patterns": [
                    [
                        "name": "keyword.control",
                        "match": "\\b(function|if|else|elif|return|for|while|class|import|from|let|var|const|true|false|null|def|end)\\b",
                    ],
                ],
            ],
            "builtins": [
                "patterns": [
                    ["name": "support.function", "match": "\\b(print|echo|len|range|type|input)\\b"],
                ],
            ],
            "functions": [
                "patterns": [
                    ["name": "entity.name.function", "match": "\\b[a-zA-Z_][a-zA-Z0-9_]*\\s*(?=\\()"],
                ],
            ],
        ],
    ]
}
