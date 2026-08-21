import XCTest
@testable import TextCore

/// Re-expressed from layout/tests/t_basic_tree_numeric.cc: the generic C++
/// `basic_tree_t<ssize_t>` sorted-set tests map onto the Swift equivalent —
/// the offset-keyed treap `PieceStorage` (key = byte position). The pure
/// set-primitive cases (duplicate keys, lower/upper bound on a general key
/// domain) have no offset-keyed analogue and are dispositioned in the matrix.
final class BasicTreeNumericTests: XCTestCase {
    private let kTreeSize = 4000

    private func randomChunk(_ rng: inout SplitMix64) -> [UInt8] {
        let len = Int(rng.next() % 30) + 1
        return (0..<len).map { _ in UInt8(rng.next() & 0xFF) }
    }

    /// test_integrity + test_iteration: 4000 random inserts keep the tree
    /// consistent, and forward/reverse iteration rebuilds the content.
    func testIntegrityAndIteration() {
        var rng = SplitMix64(seed: 0x11)
        var tree = PieceStorage()
        var oracle: [UInt8] = []

        for _ in 0..<kTreeSize {
            let chunk = randomChunk(&rng)
            let pos = Int(rng.next() % UInt64(oracle.count + 1))
            tree.insert(chunk, at: pos)
            oracle.insert(contentsOf: chunk, at: pos)
        }

        XCTAssertEqual(tree.size, oracle.count)
        // Random mid-node positions split existing nodes, so the piece count
        // grows beyond the insert count — but never below it.
        XCTAssertGreaterThanOrEqual(tree.pieceCount, kTreeSize)
        XCTAssertEqual(tree.flattenedBytes, oracle)
        XCTAssertEqual(tree.pieces.flatMap(\.bytes), oracle)
        // Reverse iteration (C++ riterate: insert each node at position 0).
        var byReverse: [UInt8] = []
        for piece in tree.pieces.reversed() {
            byReverse.insert(contentsOf: piece.bytes, at: 0)
        }
        XCTAssertEqual(byReverse, oracle)
    }

    /// test_copy: value-type copy semantics — copy, clear, swap, assign.
    func testCopy() {
        var tree = PieceStorage()
        for i in 0..<100 {
            tree.insert([UInt8(i)], at: tree.size)
        }
        let original = tree.flattenedBytes

        var tmp = tree
        tree = PieceStorage()
        XCTAssertTrue(tree.isEmpty)
        XCTAssertEqual(tmp.flattenedBytes, original)

        swap(&tmp, &tree)
        XCTAssertTrue(tmp.isEmpty)
        XCTAssertEqual(tree.flattenedBytes, original)

        tmp = tree
        XCTAssertEqual(tmp.flattenedBytes, tree.flattenedBytes)
    }

    /// test_erase: random erasures keep content consistent with the model;
    /// erasing everything leaves an empty tree.
    func testErase() {
        var rng = SplitMix64(seed: 0x22)
        var tree = PieceStorage()
        var oracle: [UInt8] = []

        for _ in 0..<500 {
            let chunk = randomChunk(&rng)
            let pos = Int(rng.next() % UInt64(oracle.count + 1))
            tree.insert(chunk, at: pos)
            oracle.insert(contentsOf: chunk, at: pos)
        }

        while !oracle.isEmpty {
            let len = Int(rng.next() % UInt64(oracle.count)) + 1
            let pos = Int(rng.next() % UInt64(oracle.count - len + 1))
            tree.erase(pos..<(pos + len))
            oracle.removeSubrange(pos..<(pos + len))
            XCTAssertEqual(tree.size, oracle.count)
            XCTAssertEqual(tree.flattenedBytes, oracle)
        }
        XCTAssertTrue(tree.isEmpty)
    }

    /// test_search: existing keys (markers) resolve at their byte offset;
    /// non-existing keys resolve to the surrounding content; erasing a key
    /// makes its offset resolve to the shifted neighbor.
    func testSearch() {
        var rng = SplitMix64(seed: 0x33)
        var buffer = Buffer()
        var markers: [Int] = []

        // Strictly increasing marker positions → no shifting while inserting.
        // Pad with spaces up to each marker (a byte buffer can't hold a position
        // beyond its end, unlike the C++ virtual-key tree).
        var next = 1
        while markers.count < 200 {
            next += Int(rng.next() % 20) + 1
            markers.append(next)
        }
        for pos in markers {
            while buffer.utf8Length < pos {
                buffer.insert(" ", at: buffer.utf8Length)
            }
            buffer.insert("X", at: pos)
        }
        XCTAssertEqual(buffer.utf8Length, markers.last! + 1)

        // find(existing key): byte at the offset is the marker.
        for pos in markers {
            XCTAssertEqual(buffer.substring(pos..<(pos + 1)), "X")
        }

        // find(non-existing key): offset inside a gap resolves to its content.
        for gap in [markers[0] - 1, markers[10] + 1, markers.last! - 1] {
            let ch = buffer.substring(gap..<(gap + 1))
            XCTAssertEqual(ch, " ", "gap at \(gap) should be a space, got '\(ch)'")
        }

        // Erasing a key makes the offset resolve to the shifted neighbor.
        let victim = markers[50]
        buffer.erase(victim..<(victim + 1))
        XCTAssertEqual(buffer.substring(victim..<(victim + 1)), " ")

        // Boundary offsets resolve too (lower/upper bound of the key domain).
        XCTAssertEqual(buffer.substring(0..<1), " ")
        XCTAssertEqual(buffer.substring((buffer.utf8Length - 1)..<buffer.utf8Length), "X")
    }
}
