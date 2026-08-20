import XCTest
@testable import TextCore

/// Unit tests for the higher-level engine pieces (Buffer, UTF-8, undo).
final class EngineTests: XCTestCase {

    // MARK: - Buffer

    func testBufferInsertEraseSubstring() {
        var buffer = Buffer("Hello, world!")
        XCTAssertEqual(buffer.content, "Hello, world!")
        XCTAssertEqual(buffer.utf8Length, 13)

        buffer.insert("cruel ", at: 7)
        XCTAssertEqual(buffer.content, "Hello, cruel world!")
        XCTAssertEqual(buffer.substring(7..<12), "cruel")

        buffer.erase(5..<12) // remove ", cruel"
        XCTAssertEqual(buffer.content, "Hello world!")

        // Multi-byte UTF-8: offsets are byte offsets, and insertions must be
        // at character boundaries (position 2 of "héllo" is mid-é).
        var unicode = Buffer("héllo")
        XCTAssertEqual(unicode.utf8Length, 6) // é is 2 bytes
        unicode.insert("é", at: 3) // after h + é
        XCTAssertEqual(unicode.content, "hééllo")
        XCTAssertEqual(unicode.utf8Length, 8)
        XCTAssertEqual(unicode.substring(1..<5), "éé")
    }

    func testBufferLines() {
        // alpha(0-4) \n(5) beta(6-9) \n(10) gamma(11-15)
        let buffer = Buffer("alpha\nbeta\ngamma")
        XCTAssertEqual(buffer.utf8Length, 16)
        XCTAssertEqual(buffer.lineCount, 3)
        XCTAssertEqual(buffer.lineIndex(atUtf8Offset: 0), 0)
        XCTAssertEqual(buffer.lineIndex(atUtf8Offset: 5), 0) // the \n ends line 0
        XCTAssertEqual(buffer.lineIndex(atUtf8Offset: 6), 1)
        XCTAssertEqual(buffer.lineIndex(atUtf8Offset: 10), 1)
        XCTAssertEqual(buffer.lineIndex(atUtf8Offset: 11), 2)
        XCTAssertEqual(buffer.lineRange(0), 0..<6)
        XCTAssertEqual(buffer.lineRange(1), 6..<11)
        XCTAssertEqual(buffer.lineRange(2), 11..<16)

        let empty = Buffer()
        XCTAssertEqual(empty.lineCount, 1)
        XCTAssertEqual(empty.lineRange(0), 0..<0)
    }

    func testBufferRoundTripThroughPieces() {
        let text = String(repeating: "the quick brown fox jumps over the lazy dog. ", count: 200)
        let bytes = Array(text.utf8)
        var storage = PieceStorage()
        // Insert in reverse chunks to force piece splitting.
        var offset = 0
        for chunk in stride(from: 0, to: bytes.count, by: 97) {
            let end = min(chunk + 97, bytes.count)
            storage.insert(Array(bytes[chunk..<end]), at: offset)
            offset = end
        }
        XCTAssertEqual(String(decoding: storage.flattenedBytes, as: UTF8.self), text)
    }

    // MARK: - UTF-8

    func testUTF8Validation() {
        XCTAssertTrue(TextEncoding.isValidUTF8(Array("hello".utf8)))
        XCTAssertTrue(TextEncoding.isValidUTF8(Array("héllo — wörld 🌍".utf8)))

        // Truncated multi-byte sequence.
        XCTAssertFalse(TextEncoding.isValidUTF8([0xC3]))
        // Continuation byte without a lead.
        XCTAssertFalse(TextEncoding.isValidUTF8([0x80, 0x41]))
        // Overlong encoding of '/'.
        XCTAssertFalse(TextEncoding.isValidUTF8([0xC0, 0xAF]))
        // Surrogate U+D800 (ED A0 80).
        XCTAssertFalse(TextEncoding.isValidUTF8([0xED, 0xA0, 0x80]))
        // Beyond U+10FFFF (F5).
        XCTAssertFalse(TextEncoding.isValidUTF8([0xF5, 0x80, 0x80, 0x80]))
    }

    func testNFCNormalization() {
        // "é" as e + combining acute accent → NFC composes to a single code point.
        // Swift String == compares canonically, so compare scalar counts.
        let decomposed = "e\u{0301}"
        let composed = "é"
        XCTAssertEqual(decomposed.count, 1) // canonical-equivalent to "é"
        XCTAssertEqual(decomposed.unicodeScalars.count, 2)
        XCTAssertEqual(composed.unicodeScalars.count, 1)
        XCTAssertEqual(TextEncoding.normalizedNFC(decomposed), composed)
    }

    // MARK: - Undo stack

    func testUndoStack() {
        var stack = UndoStack<String>()
        XCTAssertFalse(stack.canUndo)
        XCTAssertFalse(stack.canRedo)

        stack.record("a")
        stack.record("b")
        XCTAssertTrue(stack.canUndo)
        XCTAssertEqual(stack.undoDepth, 2)

        XCTAssertEqual(stack.undo(), "b")
        XCTAssertEqual(stack.undo(), "a")
        XCTAssertNil(stack.undo())
        XCTAssertTrue(stack.canRedo)

        XCTAssertEqual(stack.redo(), "a")
        XCTAssertEqual(stack.redo(), "b")
        XCTAssertNil(stack.redo())

        // New record clears the redo branch.
        stack.record("c")
        stack.undo()
        stack.record("d")
        XCTAssertFalse(stack.canRedo)
        XCTAssertEqual(stack.undo(), "d")
    }
}
