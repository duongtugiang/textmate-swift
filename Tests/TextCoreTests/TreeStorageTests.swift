import XCTest
@testable import TextCore

/// Stress + aggregate tests for the treap-backed `PieceStorage` (roadmap 2.T3).
/// A deterministic pseudo-random sequence of inserts/erases is checked against
/// an array model after every operation; the byte/newline/UTF-16 aggregates are
/// then verified against the flattened content.
final class TreeStorageTests: XCTestCase {

    private var seed: UInt64 = 0x5EED_2026

    private func nextRandom(_ bound: Int) -> Int {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Int((seed >> 33) % UInt64(bound))
    }

    private let letters = Array("abcdefghijklmnopqrstuvwxyz ABCD\n\u{00E9}\u{4E2D}\u{1F600}".utf8)

    func testRandomInsertEraseMatchesModel() {
        var model: [UInt8] = []
        var storage = PieceStorage()
        let operations = 800
        for _ in 0..<operations {
            switch nextRandom(3) {
            case 0:
                let length = 1 + nextRandom(40)
                var data: [UInt8] = []
                for _ in 0..<length { data.append(letters[nextRandom(letters.count)]) }
                let position = nextRandom(model.count + 1)
                model.insert(contentsOf: data, at: position)
                storage.insert(data, at: position)
            case 1:
                guard model.count > 0 else { continue }
                let from = nextRandom(model.count)
                let to = min(model.count, from + 1 + nextRandom(30))
                model.removeSubrange(from..<to)
                storage.erase(from..<to)
            default:
                continue
            }
            XCTAssertEqual(storage.flattenedBytes, model, "mismatch after op")
            XCTAssertEqual(storage.size, model.count)
            XCTAssertEqual(storage.pieces.flatMap { $0.bytes }, model)
        }
        XCTAssertEqual(storage.flattenedBytes, model)
        XCTAssertGreaterThan(storage.pieceCount, 1) // multi-piece layout exercised
    }

    func testAggregatesMatchFlattenedContent() {
        var storage = PieceStorage(Array("alpha\nbeta\ngamma\ndelta\n".utf8))
        storage.insert(Array("X\nY".utf8), at: 3)
        storage.erase(20..<25)

        let bytes = storage.flattenedBytes
        var expectedNewlines = 0
        for byte in bytes where byte == 0x0A { expectedNewlines += 1 }
        XCTAssertEqual(storage.newlineCount, expectedNewlines)

        // utf16Offset at every character boundary matches a String-based count.
        var byteOffset = 0
        while byteOffset <= bytes.count {
            let prefix = bytes[0..<byteOffset]
            let expectedUTF16 = String(decoding: prefix, as: UTF8.self).utf16.count
            XCTAssertEqual(storage.utf16Offset(fromByteOffset: byteOffset), expectedUTF16, "byte \(byteOffset)")
            if byteOffset < bytes.count {
                let b = storage[byteOffset]
                byteOffset += b < 0x80 ? 1 : (TextUTF8.sequenceLength(b) ?? 1)
            } else {
                break
            }
        }

        // newlines(before:) consistency with the flattened bytes.
        var expectedBefore = 0
        for i in 0...bytes.count {
            XCTAssertEqual(storage.newlines(before: i), expectedBefore, "offset \(i)")
            if i < bytes.count && bytes[i] == 0x0A { expectedBefore += 1 }
        }
    }

    func testLargeDocumentPerformance() {
        // 5 MB document: position lookups must be fast (tree-backed).
        let line = "the quick brown fox jumps over the lazy dog 0123456789\n"
        let count = 70_000
        let text = String(repeating: line, count: count)
        let buffer = Buffer(text)
        XCTAssertEqual(buffer.utf8Length, text.utf8.count)

        let start = Date()
        _ = buffer.lineIndex(atUtf8Offset: buffer.utf8Length / 2)
        _ = buffer.lineRange(35_000)
        _ = buffer.utf16Offset(fromByteOffset: buffer.utf8Length / 2)
        _ = buffer.byteOffset(fromUTF16Offset: 1_000_000)
        _ = buffer.lineColumn(atUtf8Offset: buffer.utf8Length / 3)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 0.5, "position lookups on a 5 MB doc took \(elapsed)s")
    }
}
