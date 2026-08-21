import XCTest
@testable import TextCore

/// Tests for Buffer position mapping (roadmap 1.T1 / issue #11): UTF-8 byte
/// offsets, UTF-16 code-unit offsets, and line/column conversion.
final class PositionMappingTests: XCTestCase {

    private let mixed = "aé中😀" // 1 + 2 + 3 + 4 bytes = 10; 1 + 1 + 1 + 2 = 5 UTF-16 units

    // MARK: - UTF-16 ↔ byte

    func testUTF16OffsetFromByte() {
        let buffer = Buffer(mixed)
        XCTAssertEqual(buffer.utf8Length, 10)
        XCTAssertEqual(buffer.utf16Offset(fromByteOffset: 0), 0)   // start
        XCTAssertEqual(buffer.utf16Offset(fromByteOffset: 1), 1)   // after 'a'
        XCTAssertEqual(buffer.utf16Offset(fromByteOffset: 3), 2)   // after 'é'
        XCTAssertEqual(buffer.utf16Offset(fromByteOffset: 6), 3)   // after '中'
        XCTAssertEqual(buffer.utf16Offset(fromByteOffset: 10), 5)  // end (😀 = 2 units)
    }

    func testByteOffsetFromUTF16() {
        let buffer = Buffer(mixed)
        XCTAssertEqual(buffer.byteOffset(fromUTF16Offset: 0), 0)
        XCTAssertEqual(buffer.byteOffset(fromUTF16Offset: 1), 1)
        XCTAssertEqual(buffer.byteOffset(fromUTF16Offset: 2), 3)
        XCTAssertEqual(buffer.byteOffset(fromUTF16Offset: 3), 6)
        XCTAssertEqual(buffer.byteOffset(fromUTF16Offset: 5), 10)
    }

    func testUTF16RoundTrip() {
        let texts = ["", "plain ascii", "héllo wörld", "日本語のテキスト", "mixed aé中😀 end"]
        for text in texts {
            let buffer = Buffer(text)
            // Every character boundary maps to the same position in both spaces.
            var byte = 0
            var unit = 0
            while byte <= buffer.utf8Length {
                XCTAssertEqual(buffer.utf16Offset(fromByteOffset: byte), unit, "byte \(byte) in \"\(text)\"")
                XCTAssertEqual(buffer.byteOffset(fromUTF16Offset: unit), byte, "unit \(unit) in \"\(text)\"")
                if byte < buffer.utf8Length {
                    let (scalar, length) = buffer.character(at: byte)
                    byte += length
                    unit += scalar > 0xFFFF ? 2 : 1
                } else {
                    break
                }
            }
        }
    }

    func testUTF16Clamping() {
        let buffer = Buffer("abc")
        XCTAssertEqual(buffer.utf16Offset(fromByteOffset: 99), 3)  // clamp to end
        XCTAssertEqual(buffer.utf16Offset(fromByteOffset: -5), 0)  // clamp to start
        XCTAssertEqual(buffer.byteOffset(fromUTF16Offset: 99), 3)
        XCTAssertEqual(buffer.byteOffset(fromUTF16Offset: 0), 0)
        // Inside a surrogate pair snaps to the boundary before it.
        let emoji = Buffer("😀")
        XCTAssertEqual(emoji.byteOffset(fromUTF16Offset: 1), 0) // low surrogate → start
        XCTAssertEqual(emoji.byteOffset(fromUTF16Offset: 2), 4) // past pair → end
    }

    // MARK: - Line / column

    func testLineColumn() {
        let buffer = Buffer("alpha\nbeta\ngamma")
        XCTAssertEqual(buffer.lineColumn(atUtf8Offset: 0).line, 0)
        XCTAssertEqual(buffer.lineColumn(atUtf8Offset: 5).line, 0) // the \n
        XCTAssertEqual(buffer.lineColumn(atUtf8Offset: 6).line, 1)
        XCTAssertEqual(buffer.lineColumn(atUtf8Offset: 7).column, 1) // 'e' of beta
        XCTAssertEqual(buffer.lineColumn(atUtf8Offset: 11).line, 2)
        XCTAssertEqual(buffer.lineColumn(atUtf8Offset: 11).column, 0)
        XCTAssertEqual(buffer.lineColumn(atUtf8Offset: 15).column, 4)
    }

    func testLineColumnMultibyte() {
        // "h é l l o" — é is 2 bytes, 1 column
        let buffer = Buffer("héllo")
        XCTAssertEqual(buffer.lineColumn(atUtf8Offset: 0).column, 0)
        XCTAssertEqual(buffer.lineColumn(atUtf8Offset: 3).column, 2) // after h+é
        XCTAssertEqual(buffer.lineColumn(atUtf8Offset: 6).column, 5)
    }

    func testByteOffsetFromLineColumn() {
        let buffer = Buffer("alpha\nbeta\ngamma")
        XCTAssertEqual(buffer.byteOffset(atLine: 0, utf16Column: 0), 0)
        XCTAssertEqual(buffer.byteOffset(atLine: 0, utf16Column: 5), 5)
        XCTAssertEqual(buffer.byteOffset(atLine: 1, utf16Column: 1), 7)
        XCTAssertEqual(buffer.byteOffset(atLine: 2, utf16Column: 4), 15)
        // Column past the line end snaps to the line's end.
        XCTAssertEqual(buffer.byteOffset(atLine: 1, utf16Column: 99), 10)
        // Line index out of range clamps.
        XCTAssertEqual(buffer.byteOffset(atLine: 99, utf16Column: 0), 11)
    }

    func testLineColumnRoundTrip() {
        let buffer = Buffer("first line\nsecond\nthird line with émoji 😀\nlast")
        var offset = 0
        while offset <= buffer.utf8Length {
            let (line, column) = buffer.lineColumn(atUtf8Offset: offset)
            let roundTripped = buffer.byteOffset(atLine: line, utf16Column: column)
            XCTAssertEqual(roundTripped, offset, "offset \(offset)")
            if offset < buffer.utf8Length {
                offset += buffer.character(at: offset).length
            } else {
                break
            }
        }
    }

    // MARK: - Character boundaries

    func testCharacterBoundaries() {
        let buffer = Buffer("aé中😀")
        XCTAssertEqual(buffer.nextCharacterBoundary(after: 0), 1)
        XCTAssertEqual(buffer.nextCharacterBoundary(after: 1), 3)
        XCTAssertEqual(buffer.nextCharacterBoundary(after: 3), 6)
        XCTAssertEqual(buffer.nextCharacterBoundary(after: 6), 10)
        XCTAssertEqual(buffer.nextCharacterBoundary(after: 10), 10) // clamped

        XCTAssertEqual(buffer.previousCharacterBoundary(before: 10), 6)
        XCTAssertEqual(buffer.previousCharacterBoundary(before: 6), 3)
        XCTAssertEqual(buffer.previousCharacterBoundary(before: 3), 1)
        XCTAssertEqual(buffer.previousCharacterBoundary(before: 1), 0)
        XCTAssertEqual(buffer.previousCharacterBoundary(before: 0), 0)
    }
}
