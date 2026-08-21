import XCTest
@testable import TextCore

/// Port of Frameworks/parse/tests — the grammar-engine suites that gate
/// 4.T2/4.T1: `t_anchors` (2), `t_begin_while` (1), `t_capture_rules` (1).
/// The `markup`/`scopes_for` harness mirrors tests/support.h.
final class GrammarTests: XCTestCase {

    // MARK: - Harness (tests/support.h)

    private func scopesFor(_ buf: String, grammar: Grammar) -> [Int: Scope] {
        var res: [Int: Scope] = [:]
        var state = grammar.seed()
        let ns = buf as NSString
        var i = 0
        while i < ns.length {
            let eol = ns.range(of: "\n", options: [], range: NSRange(location: i, length: ns.length - i))
            let lineEnd: Int
            if eol.location == NSNotFound {
                lineEnd = ns.length
            } else {
                lineEnd = eol.location + 1
            }
            let line = ns.substring(with: NSRange(location: i, length: lineEnd - i))
            let result = grammar.parseLine(line, stack: state, firstLine: i == 0)
            state = result.stack
            for (pos, scope) in result.scopes {
                res[i + pos] = scope
            }
            i = lineEnd
        }
        return res
    }

    private func markup(_ buf: String, grammar: Grammar) -> String {
        let scopes = scopesFor(buf, grammar: grammar)
        if scopes.isEmpty {
            return buf
        }
        let sorted = scopes.sorted { $0.key < $1.key }
        let ns = buf as NSString
        var res = Scope.xmlDifference(Scope(), sorted[0].value, open: "«", close: "»")
        for (idx, pair) in sorted.enumerated() {
            let from = pair.key
            let to = idx + 1 < sorted.count ? sorted[idx + 1].key : ns.length
            res += ns.substring(with: NSRange(location: from, length: to - from))
            let next = idx + 1 < sorted.count ? sorted[idx + 1].value : Scope()
            res += Scope.xmlDifference(pair.value, next, open: "«", close: "»")
        }
        return res
    }

    // MARK: - t_anchors.cc

    private func anchorTestGrammar() -> Grammar {
        let grammar: [String: Any] = [
            "name": "Test",
            "scopeName": "test",
            "patterns": [
                ["name": "bof", "match": "\\Axy"],
                ["name": "bom", "match": "\\Gxy"],
                ["name": "eof", "match": "xy\\z"],
                [
                    "begin": "\\[",
                    "end": "\\]",
                    "patterns": [
                        ["name": "bom", "match": "\\Axy"],
                        ["name": "bom", "match": "\\Gxy"],
                        ["name": "bom", "match": "xy\\z"],
                    ],
                ],
            ],
        ]
        return Grammar(plist: grammar)!
    }

    private func anchorInCapturesTestGrammar() -> Grammar {
        let grammar: [String: Any] = [
            "name": "Test",
            "scopeName": "test",
            "patterns": [
                ["match": "> (.+)", "name": "gt", "captures": ["1": ["patterns": [["include": "#captures"]]]]],
                ["match": "(.+) <", "name": "lt", "captures": ["1": ["patterns": [["include": "#captures"]]]]],
                ["match": ".+\\z", "name": "tail", "captures": ["0": ["patterns": [["include": "#captures"]]]]],
                ["match": "\\A.+", "name": "head", "captures": ["0": ["patterns": [["include": "#captures"]]]]],
                ["match": ".+", "name": "line", "captures": ["0": ["patterns": [["include": "#captures"]]]]],
            ],
            "repository": [
                "captures": [
                    "patterns": [
                        ["match": "\\A\\w+", "name": "b-buf"],
                        ["match": "^\\w+", "name": "b-line"],
                        ["match": "\\G\\w+", "name": "b-cap"],
                        ["match": "\\w+\\z", "name": "e-buf"],
                        ["match": "\\w+$", "name": "e-line"],
                        ["match": "\\w+\\Z", "name": "e-cap"],
                    ],
                ],
            ],
        ]
        return Grammar(plist: grammar)!
    }

    func testAnchors() {
        let grammar = anchorTestGrammar()
        XCTAssertEqual(markup("xy xy\nxy xy\n[xy xy\nxy xy]\nxy xy", grammar: grammar),
                       "«test»«bof»xy«/bof» xy\nxy xy\n[«bom»xy«/bom» xy\nxy xy]\nxy «eof»xy«/eof»«/test»")
        XCTAssertEqual(markup("xy xy", grammar: grammar),
                       "«test»«bof»xy«/bof» «eof»xy«/eof»«/test»")
        XCTAssertEqual(markup("xy xy\n", grammar: grammar),
                       "«test»«bof»xy«/bof» xy\n«/test»")
        XCTAssertEqual(markup("[xy xy]", grammar: grammar),
                       "«test»[«bom»xy«/bom» xy]«/test»")
    }

    func testAnchorInCaptures() {
        let grammar = anchorInCapturesTestGrammar()
        XCTAssertEqual(markup("foo\n", grammar: grammar),
                       "«test»«head»«b-buf»foo«/b-buf»«/head»\n«/test»")
        XCTAssertEqual(markup("> foo\n", grammar: grammar),
                       "«test»«gt»> «b-cap»foo«/b-cap»«/gt»\n«/test»")
        XCTAssertEqual(markup("foo <\n", grammar: grammar),
                       "«test»«lt»«b-buf»foo«/b-buf» <«/lt»\n«/test»")
        XCTAssertEqual(markup("\nfoo\n", grammar: grammar),
                       "«test»\n«line»«b-line»foo«/b-line»«/line»\n«/test»")
        XCTAssertEqual(markup("\nfoo", grammar: grammar),
                       "«test»\n«tail»«b-line»foo«/b-line»«/tail»«/test»")
        XCTAssertEqual(markup("\nfoo bar", grammar: grammar),
                       "«test»\n«tail»«b-line»foo«/b-line» «e-buf»bar«/e-buf»«/tail»«/test»")
    }

    // MARK: - t_begin_while.cc

    private func beginWhileTestGrammar() -> Grammar {
        let grammar: [String: Any] = [
            "scopeName": "mdown",
            "patterns": [
                ["include": "#block"],
            ],
            "repository": [
                "block": [
                    "patterns": [
                        ["include": "#heading"],
                        ["include": "#quote"],
                        ["include": "#list"],
                        ["include": "#raw"],
                        ["include": "#par"],
                    ],
                    "repository": [
                        "heading": ["name": "hn", "begin": "(^|\\G)#+ ", "end": "\\n",
                                    "patterns": [["include": "#inline"]]],
                        "quote": ["name": "q", "begin": "(^|\\G)> ", "while": "\\G> ",
                                  "patterns": [["include": "#block"]]],
                        "list": ["name": "li", "begin": "(^|\\G) [*] ", "while": "\\G   ",
                                 "patterns": [["include": "#block"]]],
                        "raw": ["name": "pre", "begin": "(^|\\G)    ", "while": "\\G    ",
                                "patterns": []],
                        "par": ["name": "p", "begin": "(?=\\S)", "end": "$",
                                "patterns": [["include": "#inline"]]],
                    ],
                ],
                "inline": [
                    "patterns": [
                        ["include": "#emph"],
                    ],
                    "repository": [
                        "emph": ["name": "em", "begin": "_", "end": "_", "patterns": []],
                    ],
                ],
            ],
        ]
        return Grammar(plist: grammar)!
    }

    func testBeginWhile() {
        let grammar = beginWhileTestGrammar()
        let buf =
            "# Heading\n"
            + "\n"
            + "> Quoted\n"
            + "> \n"
            + "> > Double Quoted\n"
            + "> >  * First item\n"
            + "> >    still first\n"
            + "> >  * Second item\n"
            + "> >  * Third item\n"
            + "> >  * Fourth item\n"
            + "> >    \n"
            + "> >        Raw _in_ item\n"
            + "> >        More raw\n"
            + "> >    \n"
            + "> >    same _item_.\n"
            + "> >    \n"
            + "> >    # Heading in _that_ item\n"
            + "> > # Heading in quote\n"
            + "> Back to _quote_.\n"
            + "And normal text.\n"

        let res =
            "«mdown»«hn»# Heading\n"
            + "«/hn»\n"
            + "«q»> «p»Quoted«/p»\n"
            + "> \n"
            + "> «q»> «p»Double Quoted«/p»\n"
            + "«/q»> «q»> «li» * «p»First item«/p»\n"
            + "«/li»«/q»> «q»> «li»   «p»still first«/p»\n"
            + "«/li»«/q»> «q»> «li» * «p»Second item«/p»\n"
            + "«/li»«/q»> «q»> «li» * «p»Third item«/p»\n"
            + "«/li»«/q»> «q»> «li» * «p»Fourth item«/p»\n"
            + "«/li»«/q»> «q»> «li»   \n"
            + "«/li»«/q»> «q»> «li»   «pre»    Raw _in_ item\n"
            + "«/pre»«/li»«/q»> «q»> «li»   «pre»    More raw\n"
            + "«/pre»«/li»«/q»> «q»> «li»   \n"
            + "«/li»«/q»> «q»> «li»   «p»same «em»_item_«/em».«/p»\n"
            + "«/li»«/q»> «q»> «li»   \n"
            + "«/li»«/q»> «q»> «li»   «hn»# Heading in «em»_that_«/em» item\n"
            + "«/hn»«/li»«/q»> «q»> «hn»# Heading in quote\n"
            + "«/hn»«/q»> «p»Back to «em»_quote_«/em».«/p»\n"
            + "«/q»«p»And normal text.«/p»\n"
            + "«/mdown»"

        XCTAssertEqual(markup(buf, grammar: grammar), res)
        XCTAssertEqual(markup("> _first\n> second_\n> third\nfourth", grammar: grammar),
                       "«mdown»«q»> «p»«em»_first\n> second_«/em»«/p»\n> «p»third«/p»\n«/q»«p»fourth«/p»«/mdown»")
        XCTAssertEqual(markup("> > _first\n> > second_\n> > third\nfourth", grammar: grammar),
                       "«mdown»«q»> «q»> «p»«em»_first\n> > second_«/em»«/p»\n«/q»> «q»> «p»third«/p»\n«/q»«/q»«p»fourth«/p»«/mdown»")
    }

    // MARK: - t_capture_rules.cc

    private func captureTestGrammar() -> Grammar {
        let grammar: [String: Any] = [
            "name": "Test",
            "scopeName": "test",
            "patterns": [
                [
                    "match": "^leak",
                    "name": "main",
                    "captures": [
                        "0": ["patterns": [["begin": "leak", "end": "(?=not)possible", "name": "capture"]]],
                    ],
                ],
                [
                    "match": "^((?:.{0,20}\\s*)|(.{21,}\\s*))$",
                    "captures": [
                        "1": ["patterns": [["match": "\\G(fixup|squash)!", "name": "$1"]]],
                        "2": ["name": "warn"],
                    ],
                ],
            ],
        ]
        return Grammar(plist: grammar)!
    }

    func testCaptures() {
        let grammar = captureTestGrammar()
        XCTAssertEqual(markup("Lorem ipsum.", grammar: grammar),
                       "«test»Lorem ipsum.«/test»")
        XCTAssertEqual(markup("fixup! Lorem ipsum.", grammar: grammar),
                       "«test»«fixup»fixup!«/fixup» Lorem ipsum.«/test»")
        XCTAssertEqual(markup("Lorem ipsum dolor sit amet.", grammar: grammar),
                       "«test»«warn»Lorem ipsum dolor sit amet.«/warn»«/test»")
        XCTAssertEqual(markup("fixup! Lorem ipsum dolor sit amet.", grammar: grammar),
                       "«test»«fixup»«warn»fixup!«/warn»«/fixup»«warn» Lorem ipsum dolor sit amet.«/warn»«/test»")
        XCTAssertEqual(markup("leaking", grammar: grammar),
                       "«test»«main»«capture»leak«/capture»«/main»ing«/test»")
    }
}
