import XCTest
@testable import TextCore

/// Tests for the per-line syntax parser (4.S2): full parse scope output and
/// incremental repair equivalence — reparse-from-edit-line must converge to
/// the same scopes as a full reload.
final class SyntaxParserTests: XCTestCase {

    private let sample =
        "// Demo: syntax highlighting\n"
        + "function greet(name) {\n"
        + "    if (name == \"world\") {\n"
        + "        print(\"hello \" + name)\n"
        + "        return 42\n"
        + "    }\n"
        + "}\n"
        + "var count = 0x1F\n"

    private func makeParser() -> SyntaxParser {
        SyntaxParser(grammar: Grammar(plist: BuiltInGrammar.plist)!)
    }

    /// The innermost non-root scope element at a given UTF-16 offset.
    private func innermost(_ scope: Scope?) -> String? {
        scope?.elements.last
    }

    func testFullParseScopes() {
        let parser = makeParser()
        parser.reload(sample)
        XCTAssertEqual(parser.lines.count, 8)

        // Line 0: full-line comment.
        XCTAssertEqual(innermost(parser.scopes(forLine: 0)[0]), "comment.line")

        // Line 1: keyword at 0, function name at 9.
        XCTAssertEqual(innermost(parser.scopes(forLine: 1)[0]), "keyword.control")
        XCTAssertEqual(innermost(parser.scopes(forLine: 1)[9]), "entity.name.function")

        // Line 2: string at 16.
        XCTAssertEqual(innermost(parser.scopes(forLine: 2)[16]), "string.quoted.double")

        // Line 4: number at 15.
        XCTAssertEqual(innermost(parser.scopes(forLine: 4)[15]), "constant.numeric")

        // Line 7: hex number at 12.
        XCTAssertEqual(innermost(parser.scopes(forLine: 7)[12]), "constant.numeric")
    }

    func testBlockCommentSpanningLines() {
        let parser = makeParser()
        parser.reload("let a = 1\n/* open\nstill open\n*/\nlet b = 2\n")
        // Block comment begins on line 1 and continues into line 2.
        XCTAssertEqual(innermost(parser.scopes(forLine: 1)[0]), "comment.block")
        XCTAssertEqual(innermost(parser.scopes(forLine: 2)[0]), "comment.block")
        // ...and ends on line 3 ("*/"), so the closing line is still covered.
        XCTAssertEqual(innermost(parser.scopes(forLine: 3)[0]), "comment.block")
        XCTAssertEqual(innermost(parser.scopes(forLine: 4)[0]), "keyword.control")
    }

    func testIncrementalRepairConvergesToFullReload() {
        let parser = makeParser()
        parser.reload(sample)

        // Edit: change line 3's string content and add a keyword on line 4.
        let edited =
            "// Demo: syntax highlighting\n"
            + "function greet(name) {\n"
            + "    if (name == \"world\") {\n"
            + "        print(\"hi \" + name)\n"
            + "        return 42 and 7\n"
            + "    }\n"
            + "}\n"
            + "var count = 0x1F\n"

        // Apply the edit the way the view does: affected lines are 3 and 4.
        parser.updateText(edited, fromLine: 3, endLine: 4)

        // A full reload must agree.
        let fresh = makeParser()
        fresh.reload(edited)

        XCTAssertEqual(parser.lines.count, fresh.lines.count)
        XCTAssertEqual(parser.states.count, fresh.states.count)
        for i in 0..<fresh.scopes.count {
            XCTAssertEqual(parser.scopes[i], fresh.scopes[i], "line \(i) scopes diverge after incremental repair")
        }
        // The repair stopped early: after line 4 the states converge, so the
        // parser must not have re-parsed the trailing lines (states identical
        // to the pre-edit parse is a stronger claim than needed — here we
        // assert the scopes, which is what rendering needs).
        XCTAssertEqual(innermost(parser.scopes(forLine: 3)[14]), "string.quoted.double")
        XCTAssertEqual(innermost(parser.scopes(forLine: 4)[22]), "constant.numeric")
    }

    func testRepairPreservesUnchangedTrailingLines() {
        let parser = makeParser()
        parser.reload(sample)
        let originalLine7 = parser.scopes[7]

        // Edit only the first line's content.
        let edited = "// changed\n" + String(sample.dropFirst(28))
        parser.updateText(edited, fromLine: 0, endLine: 0)

        XCTAssertEqual(innermost(parser.scopes(forLine: 0)[0]), "comment.line")
        XCTAssertEqual(parser.scopes[7], originalLine7)
    }
}
