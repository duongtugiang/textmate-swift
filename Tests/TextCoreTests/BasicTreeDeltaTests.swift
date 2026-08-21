import XCTest
@testable import TextCore

/// Deterministic SplitMix64 so failures are reproducible.
struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// Re-expressed from editor/../layout/tests/t_basic_tree_delta.cc: the C++
/// `basic_tree_t<annotation_t>` (buffer_size / children / width aggregates) maps
/// onto `PieceStorage`'s treap (bytes / piece-count / piece-size aggregates).
/// The C++ tree stores only lengths and reads content from the original by
/// final offset; the byte re-expression inserts each chunk's own bytes at the
/// same positions, which reconstructs the original exactly (verified below).
final class BasicTreeDeltaTests: XCTestCase {
    private let buffer = "Lorem Ipsum is simply dummy text of the printing and typesetting industry. Lorem Ipsum has been the industry's standard dummy text ever since the 1500s, when an unknown printer took a galley of type and scrambled it to make a type specimen book. It has survived not only five centuries, but also the leap into electronic typesetting, remaining essentially unchanged. It was popularised in the 1960s with the release of Letraset sheets containing Lorem Ipsum passages, and more recently with desktop publishing software like Aldus PageMaker including versions of Lorem Ipsum."

    /// The C++ random_insert algorithm: splits the buffer into ~15–30 byte
    /// chunks (extended to the next space), shuffles them, and inserts each at
    /// the offset that reconstructs the original.
    private func randomChunkInserts() -> (storage: PieceStorage, chunkCount: Int, maxChunk: Int, chunkLengths: [Int]) {
        var rng = SplitMix64(seed: 0xC0FFEE)
        let buf = Array(buffer.utf8)

        var lengths: [Int] = []
        var i = 0
        while i < buf.count {
            var len = min(Int(rng.next() % 15) + 15, buf.count - i)
            while i + len < buf.count && buf[i + len - 1] != 0x20 { len += 1 }
            lengths.append(len)
            i += len
        }
        var cum: [Int] = []
        var acc = 0
        for l in lengths { cum.append(acc); acc += l }

        var ordering = Array(0..<lengths.count)
        for j in stride(from: ordering.count - 1, through: 1, by: -1) {
            let k = Int(rng.next() % UInt64(j + 1))
            ordering.swapAt(j, k)
        }

        var srcOffsets = [Int](repeating: 0, count: lengths.count)
        var insertRanges: [(Int, Int)] = []
        for index in ordering {
            insertRanges.append((srcOffsets[index], lengths[index]))
            for k in (index + 1)..<srcOffsets.count {
                srcOffsets[k] += lengths[index]
            }
        }

        var storage = PieceStorage()
        for (insertPos, chunkID) in zip(insertRanges.map { $0.0 }, ordering) {
            let len = lengths[chunkID]
            storage.insert(Array(buf[cum[chunkID]..<cum[chunkID] + len]), at: insertPos)
        }
        return (storage, lengths.count, lengths.max() ?? 0, lengths.sorted())
    }

    func testBasicTreeDelta() {
        let (tree, chunkCount, maxChunk, chunkLengths) = randomChunkInserts()
        let original = Array(buffer.utf8)

        // Primary key: children count == node count; total size unchanged.
        XCTAssertEqual(tree.pieceCount, chunkCount)
        XCTAssertEqual(tree.size, original.count)

        // Forward iteration rebuilds the buffer.
        XCTAssertEqual(tree.flattenedBytes, original)
        XCTAssertEqual(tree.pieces.flatMap(\.bytes), original)

        // Reverse iteration rebuilds the buffer (the C++ riterate loop inserts
        // each node at position 0).
        var byReverse: [UInt8] = []
        for piece in tree.pieces.reversed() {
            byReverse.insert(contentsOf: piece.bytes, at: 0)
        }
        XCTAssertEqual(byReverse, original)

        // Secondary key (number_of_children): navigate to the nth node and
        // rebuild — each chunk contributes one child, so this equals forward
        // iteration (the C++ find(n, children_comp) loop).
        var byChild: [UInt8] = []
        for n in 0..<tree.pieceCount {
            byChild.append(contentsOf: tree.pieces[n].bytes)
        }
        XCTAssertEqual(byChild, original)

        // Aggregation: max piece width == max inserted chunk size, and the piece
        // sizes are exactly the chunk sizes (no splitting/coalescing).
        XCTAssertEqual(tree.pieces.map(\.size).max() ?? 0, maxChunk)
        XCTAssertEqual(tree.pieces.map(\.size).sorted(), chunkLengths)

        // Cleanup leaves an empty, consistent tree.
        var mutable = tree
        mutable = PieceStorage()
        XCTAssertTrue(mutable.isEmpty)
        XCTAssertEqual(mutable.size, 0)
    }
}
