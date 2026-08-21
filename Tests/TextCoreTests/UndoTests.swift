import XCTest
@testable import TextCore

/// Tests for Buffer's command-based undo/redo (roadmap 1.S2 / issues #10, #17):
/// insert/erase/replace commands, caret return values, and typing coalescing.
final class UndoTests: XCTestCase {

    func testUndoInsert() {
        var buffer = Buffer("hello")
        buffer.insert(" world", at: 5)
        XCTAssertEqual(buffer.content, "hello world")
        XCTAssertTrue(buffer.canUndo)
        XCTAssertFalse(buffer.canRedo)

        XCTAssertEqual(buffer.undo(), 5) // caret back to the insert point
        XCTAssertEqual(buffer.content, "hello")
        XCTAssertFalse(buffer.canUndo)
        XCTAssertTrue(buffer.canRedo)

        XCTAssertEqual(buffer.redo(), 11) // caret after the re-inserted text
        XCTAssertEqual(buffer.content, "hello world")
        XCTAssertTrue(buffer.canUndo)
        XCTAssertFalse(buffer.canRedo)
    }

    func testUndoErase() {
        var buffer = Buffer("hello world")
        buffer.erase(5..<11)
        XCTAssertEqual(buffer.content, "hello")

        XCTAssertEqual(buffer.undo(), 11) // caret at end of restored text
        XCTAssertEqual(buffer.content, "hello world")

        XCTAssertEqual(buffer.redo(), 5)
        XCTAssertEqual(buffer.content, "hello")
    }

    func testUndoReplace() {
        var buffer = Buffer("the quick fox")
        buffer.replace(4..<9, with: "slow")
        XCTAssertEqual(buffer.content, "the slow fox")

        buffer.undo()
        XCTAssertEqual(buffer.content, "the quick fox")
        buffer.redo()
        XCTAssertEqual(buffer.content, "the slow fox")
    }

    func testUndoCoalescingTyping() {
        var buffer = Buffer()
        buffer.insert("a", at: 0)
        buffer.insert("b", at: 1)
        buffer.insert("c", at: 2)
        XCTAssertEqual(buffer.content, "abc")
        XCTAssertEqual(buffer.undoDepth, 1) // one coalesced command

        buffer.undo()
        XCTAssertEqual(buffer.content, "")
        XCTAssertEqual(buffer.undoDepth, 0)
        XCTAssertNil(buffer.undo())
    }

    func testBreakUndoCoalescing() {
        var buffer = Buffer()
        buffer.insert("a", at: 0)
        buffer.breakUndoCoalescing() // e.g. the caret moved
        buffer.insert("b", at: 1)
        XCTAssertEqual(buffer.undoDepth, 2)

        buffer.undo() // removes just "b"
        XCTAssertEqual(buffer.content, "a")
        buffer.undo() // removes "a"
        XCTAssertEqual(buffer.content, "")
    }

    func testNoCoalescingAcrossDelete() {
        var buffer = Buffer("abc")
        buffer.erase(1..<2) // delete "b"
        buffer.insert("X", at: 1)
        XCTAssertEqual(buffer.undoDepth, 2)
        buffer.undo()
        XCTAssertEqual(buffer.content, "ac")
        buffer.undo()
        XCTAssertEqual(buffer.content, "abc")
    }

    func testNewEditClearsRedo() {
        var buffer = Buffer("abc")
        buffer.erase(1..<3)
        buffer.undo()
        XCTAssertTrue(buffer.canRedo)
        buffer.insert("X", at: 0)
        XCTAssertFalse(buffer.canRedo)
        XCTAssertNil(buffer.redo())
    }

    func testUndoEraseRestoresTextForRedo() {
        var buffer = Buffer("hello world")
        buffer.erase(0..<6) // "hello "
        XCTAssertEqual(buffer.content, "world")
        buffer.undo()
        XCTAssertEqual(buffer.content, "hello world") // erased text restored
        buffer.redo()
        XCTAssertEqual(buffer.content, "world") // erase reapplied
    }

    func testUndoDoesNotAffectContentEquality() {
        var edited = Buffer("abc")
        edited.insert("d", at: 3)
        let plain = Buffer("abcd")
        XCTAssertEqual(edited, plain) // equality ignores undo state
    }
}
