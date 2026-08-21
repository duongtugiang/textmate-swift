import XCTest
@testable import TextCore

/// Port of `Frameworks/editor/tests/t_snippets.cc` (test_repopulating_mirrors)
/// plus direct tests of the snippet engine core.
final class SnippetTests: XCTestCase {

    func testRepopulatingMirrors() {
        let plistSrc = "{ content = \"${1/.+/-/}${1:x}${1/.+/-/}\"; }"
        let snippetText = extractSnippet(from: plistSrc)
        var editor = SnippetEditor()
        let selection = editor.dispatch(snippetText, at: 0)
        XCTAssertEqual(editor.string, "-x-")
        XCTAssertEqual(selection.from.offset, 1)   // [1-2]
        XCTAssertEqual(selection.to.offset, 2)

        // Delete the selected field content.
        let deleteCaret = editor.replace(range: TextFormatString.Range(1, 2), with: "")
        XCTAssertEqual(editor.string, "")
        XCTAssertEqual(deleteCaret, 0)             // [0]

        // Inserting into the empty field repopulates the mirrors.
        let insertCaret = editor.replace(range: TextFormatString.Range(0, 0), with: "y")
        XCTAssertEqual(editor.string, "-y-")
        XCTAssertEqual(insertCaret, 2)             // [2]
    }

    func testMirrorUpdateOnTyping() {
        var editor = SnippetEditor()
        // \u$0 with /g uppercases each matched character (C++ semantics).
        _ = editor.dispatch("(${1:name}) ${1/./\\u$0/g}", at: 0)
        XCTAssertEqual(editor.string, "(name) NAME")
        _ = editor.replace(range: TextFormatString.Range(1, 5), with: "foo")
        XCTAssertEqual(editor.string, "(foo) FOO")
    }

    func testTabNavigation() {
        var editor = SnippetEditor()
        _ = editor.dispatch("${1:one} ${2:two} ${3:three}", at: 0)
        XCTAssertEqual(editor.string, "one two three")
        // Current field is the smallest index > 0 → $1 = [0-3]
        XCTAssertEqual(editor.caret, 3)

        XCTAssertTrue(editor.stack.next())
        XCTAssertEqual(editor.caret, 7)            // $2 = [4-7]
        XCTAssertTrue(editor.stack.next())
        XCTAssertEqual(editor.caret, 13)           // $3 = [8-13]

        XCTAssertTrue(editor.stack.previous())
        XCTAssertEqual(editor.caret, 7)            // back to $2
        XCTAssertTrue(editor.stack.previous())
        XCTAssertEqual(editor.caret, 3)            // back to $1

        XCTAssertTrue(editor.stack.next())
        XCTAssertEqual(editor.caret, 7)            // $2 again
        XCTAssertTrue(editor.stack.next())
        XCTAssertEqual(editor.caret, 13)           // $3 again
        XCTAssertTrue(editor.stack.next())
        XCTAssertEqual(editor.caret, 13)           // $0 at end
        XCTAssertFalse(editor.stack.next())        // stack exhausted
    }

    func testNestedFields() {
        var editor = SnippetEditor()
        // ${2:a} is the field; the second ${2:b} is a mirror replicating it.
        _ = editor.dispatch("${1:${2:a}${2:b}}", at: 0)
        XCTAssertEqual(editor.string, "aa")
        XCTAssertEqual(editor.caret, 2)            // current = outer $1 → [0-2]
        XCTAssertTrue(editor.stack.next())
        XCTAssertEqual(editor.caret, 1)            // $2 field = [0-1]
        XCTAssertTrue(editor.stack.next())
        XCTAssertEqual(editor.caret, 2)            // $0 at end
    }

    func testChoices() {
        let snippet = TextFormatString.parseSnippet("${1|one,two,three|}")
        XCTAssertEqual(snippet.string, "one")
        XCTAssertEqual(snippet.fields[1]?.choiceList(), ["one", "two", "three"])
    }

    func testTransformPlaceholderPromotedToField() {
        // A transform with no owning field becomes a field (its transform is
        // dormant — the field text is what the user types).
        var editor = SnippetEditor()
        _ = editor.dispatch("${1/.+/[$0]/}x", at: 0)
        XCTAssertEqual(editor.string, "x")
        _ = editor.replace(range: TextFormatString.Range(0, 0), with: "ab")
        XCTAssertEqual(editor.string, "abx")
    }

    func testVariablesInSnippet() {
        let snippet = TextFormatString.parseSnippet("Hello ${1:world}, $TM_FILENAME")
        // Variables are not set during parse — $TM_FILENAME expands to "".
        XCTAssertEqual(snippet.string, "Hello world, ")
    }

    private func extractSnippet(from plistSrc: String) -> String {
        // Old-style plist `{ content = "..."; }` — pull the quoted value.
        guard let open = plistSrc.firstIndex(of: "\""), let close = plistSrc[plistSrc.index(after: open)...].firstIndex(of: "\"") else {
            return plistSrc
        }
        return String(plistSrc[plistSrc.index(after: open)..<close])
    }
}
