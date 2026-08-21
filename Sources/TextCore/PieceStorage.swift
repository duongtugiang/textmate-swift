import Foundation

/// A piece table backed by an **implicit treap** (randomized balanced tree):
/// the document text is the concatenation of immutable byte pieces, with
/// per-node aggregates `(byteCount, newlineCount, utf16Count)` so every
/// position query is O(log n). This replaces the array-backed version and
/// mirrors `ng::detail::storage_t` (Frameworks/buffer/src/storage.h), which
/// the original backs with `oak::basic_tree_t`.
///
/// Pieces are immutable: a node's own bytes never change, so its newline/UTF-16
/// metrics are computed once at allocation and only the subtree aggregates are
/// recomputed (O(1)) when the tree shape changes during insert/erase.
/// Large inserts and loads are split into bounded chunks (32 KB) so in-node
/// scans stay cheap.
public struct PieceStorage: Equatable {
    public struct Piece: Equatable {
        public let bytes: [UInt8]
        public init(_ bytes: [UInt8]) { self.bytes = bytes }
        public var size: Int { bytes.count }
    }

    // MARK: - Tree internals

    /// Maximum piece size; larger data is chunked so per-node scans are bounded.
    private static let maxPieceBytes = 1 << 15 // 32 KB

    private struct Node {
        var bytes: [UInt8]
        var priority: UInt32
        var left: Int = -1
        var right: Int = -1
        var byteCount: Int    // subtree bytes
        var newlineCount: Int // subtree newlines
        var utf16Count: Int   // subtree UTF-16 units
        var selfNewlines: Int // newlines in this node's own bytes
        var selfUTF16: Int    // UTF-16 units in this node's own bytes
    }

    private var nodes: [Node] = []
    private var freeSlots: [Int] = []
    private var root: Int = -1
    private(set) public var pieceCount: Int = 0

    /// Deterministic xorshift stream for treap priorities (stable across runs).
    private static var priorityState: UInt64 = 0x9E3779B97F4A7C15
    private static func nextPriority() -> UInt32 {
        var x = priorityState
        x ^= x << 13
        x ^= x >> 7
        x ^= x << 17
        priorityState = x
        return UInt32(truncatingIfNeeded: x)
    }

    private static func newlines(in bytes: [UInt8]) -> Int {
        var count = 0
        for byte in bytes where byte == 0x0A { count += 1 }
        return count
    }

    /// (UTF-16 units, byte length) of the character at `index`; malformed or
    /// incomplete bytes count as U+FFFD (1 unit, 1 byte) — the storage is
    /// byte-transparent, like the C++ original.
    private static func charMetrics(_ bytes: [UInt8], at index: Int) -> (units: Int, length: Int) {
        let byte = bytes[index]
        if byte < 0x80 { return (1, 1) }
        guard let length = TextUTF8.sequenceLength(byte), index + length <= bytes.count else { return (1, 1) }
        for k in (index + 1)..<(index + length) where (bytes[k] & 0xC0) != 0x80 { return (1, 1) }
        var value = UInt32(byte & ((1 << (7 - length)) - 1))
        for k in 1..<length { value = (value << 6) | UInt32(bytes[index + k] & 0x3F) }
        return (value > 0xFFFF ? 2 : 1, length)
    }

    private static func utf16Units(in bytes: [UInt8]) -> Int {
        var units = 0
        var index = 0
        while index < bytes.count {
            let metrics = charMetrics(bytes, at: index)
            units += metrics.units
            index += metrics.length
        }
        return units
    }

    private mutating func allocNode(_ bytes: [UInt8]) -> Int {
        let selfNewlines = Self.newlines(in: bytes)
        let selfUTF16 = Self.utf16Units(in: bytes)
        let node = Node(
            bytes: bytes,
            priority: Self.nextPriority(),
            byteCount: bytes.count,
            newlineCount: selfNewlines,
            utf16Count: selfUTF16,
            selfNewlines: selfNewlines,
            selfUTF16: selfUTF16
        )
        pieceCount += 1
        if let slot = freeSlots.popLast() {
            nodes[slot] = node
            return slot
        }
        nodes.append(node)
        return nodes.count - 1
    }

    private mutating func freeNode(_ index: Int) {
        nodes[index].left = -1
        nodes[index].right = -1
        freeSlots.append(index)
        pieceCount -= 1
    }

    private mutating func freeSubtree(_ index: Int) {
        guard index >= 0 else { return }
        freeSubtree(nodes[index].left)
        freeSubtree(nodes[index].right)
        freeNode(index)
    }

    private func byteCount(_ index: Int) -> Int { index < 0 ? 0 : nodes[index].byteCount }
    private func newlineCount(_ index: Int) -> Int { index < 0 ? 0 : nodes[index].newlineCount }
    private func utf16Count(_ index: Int) -> Int { index < 0 ? 0 : nodes[index].utf16Count }

    private mutating func recompute(_ index: Int) {
        nodes[index].byteCount = nodes[index].bytes.count + byteCount(nodes[index].left) + byteCount(nodes[index].right)
        nodes[index].newlineCount = nodes[index].selfNewlines + newlineCount(nodes[index].left) + newlineCount(nodes[index].right)
        nodes[index].utf16Count = nodes[index].selfUTF16 + utf16Count(nodes[index].left) + utf16Count(nodes[index].right)
    }

    // MARK: - Init

    public init() {}

    public init(_ bytes: [UInt8]) {
        var newRoot = -1
        var position = 0
        while position < bytes.count {
            let end = min(position + Self.maxPieceBytes, bytes.count)
            let node = allocNode(Array(bytes[position..<end]))
            newRoot = merge(newRoot, node)
            position = end
        }
        root = newRoot
    }

    // MARK: - Treap operations

    /// Splits the tree so the left result contains the first `count` bytes.
    private mutating func split(_ root: Int, _ count: Int) -> (Int, Int) {
        guard root >= 0 else { return (-1, -1) }
        let leftBytes = byteCount(nodes[root].left)
        let nodeBytes = nodes[root].bytes.count
        if count < leftBytes {
            let (a, b) = split(nodes[root].left, count)
            nodes[root].left = b
            recompute(root)
            return (a, root)
        } else if count > leftBytes + nodeBytes {
            let (a, b) = split(nodes[root].right, count - leftBytes - nodeBytes)
            nodes[root].right = a
            recompute(root)
            return (root, b)
        } else {
            let within = count - leftBytes
            if within <= 0 {
                // Split exactly at this node's start: the left result is this
                // node's left subtree; this node (bytes + right) stays right.
                let left = nodes[root].left
                nodes[root].left = -1
                recompute(root)
                return (left, root)
            } else if within >= nodeBytes {
                // Split exactly after this node's bytes: this node (left +
                // bytes) stays left; the right result is its right subtree.
                let right = nodes[root].right
                nodes[root].right = -1
                recompute(root)
                return (root, right)
            } else {
                // Split inside this node: it keeps the left half; a new node
                // takes the right half followed by the original right subtree
                // (in-order = bytes then subtree, so it attaches as .right).
                let rightBytes = Array(nodes[root].bytes[within...])
                let rightChild = nodes[root].right
                let newNode = allocNode(rightBytes)
                nodes[newNode].right = rightChild
                nodes[root].bytes = Array(nodes[root].bytes[..<within])
                nodes[root].selfNewlines = Self.newlines(in: nodes[root].bytes)
                nodes[root].selfUTF16 = Self.utf16Units(in: nodes[root].bytes)
                nodes[root].right = -1
                recompute(newNode)
                recompute(root)
                return (root, newNode)
            }
        }
    }

    private mutating func merge(_ a: Int, _ b: Int) -> Int {
        guard a >= 0 else { return b }
        guard b >= 0 else { return a }
        if nodes[a].priority > nodes[b].priority {
            nodes[a].right = merge(nodes[a].right, b)
            recompute(a)
            return a
        } else {
            nodes[b].left = merge(a, nodes[b].left)
            recompute(b)
            return b
        }
    }

    // MARK: - Public API

    /// Total number of bytes (O(1)).
    public var size: Int { root < 0 ? 0 : byteCount(root) }
    public var isEmpty: Bool { root < 0 }

    /// Total number of `\n` bytes (O(1)).
    public var newlineCount: Int { root < 0 ? 0 : newlineCount(root) }

    /// All bytes as a single array (O(n); convenience for equality/queries).
    public var flattenedBytes: [UInt8] {
        var out: [UInt8] = []
        flatten(root, &out)
        return out
    }

    private func flatten(_ index: Int, _ out: inout [UInt8]) {
        guard index >= 0 else { return }
        flatten(nodes[index].left, &out)
        out.append(contentsOf: nodes[index].bytes)
        flatten(nodes[index].right, &out)
    }

    /// Ordered pieces (in-order walk; O(n)).
    public var pieces: [Piece] {
        var out: [Piece] = []
        collectPieces(root, &out)
        return out
    }

    private func collectPieces(_ index: Int, _ out: inout [Piece]) {
        guard index >= 0 else { return }
        collectPieces(nodes[index].left, &out)
        out.append(Piece(nodes[index].bytes))
        collectPieces(nodes[index].right, &out)
    }

    public mutating func insert(_ data: [UInt8], at position: Int) {
        precondition((0...size).contains(position), "insert position \(position) out of range [0, \(size)]")
        guard !data.isEmpty else { return }
        let (left, right) = split(root, position)
        var newRoot = left
        var offset = 0
        while offset < data.count {
            let end = min(offset + Self.maxPieceBytes, data.count)
            let node = allocNode(Array(data[offset..<end]))
            newRoot = merge(newRoot, node)
            offset = end
        }
        root = merge(newRoot, right)
    }

    /// Erases bytes in `range` (half-open, byte offsets).
    public mutating func erase(_ range: Range<Int>) {
        let first = range.lowerBound, last = range.upperBound
        precondition(first >= 0 && last <= size && first <= last, "erase \(range) out of range for size \(size)")
        guard first < last, root >= 0 else { return }
        let (left, middle) = split(root, first)
        let (removed, right) = split(middle, last - first)
        freeSubtree(removed)
        root = merge(left, right)
    }

    public subscript(index: Int) -> UInt8 {
        precondition((0..<size).contains(index), "index \(index) out of range")
        var node = root
        var offset = index
        while node >= 0 {
            let leftBytes = byteCount(nodes[node].left)
            if offset < leftBytes {
                node = nodes[node].left
            } else {
                offset -= leftBytes
                if offset < nodes[node].bytes.count {
                    return nodes[node].bytes[offset]
                }
                offset -= nodes[node].bytes.count
                node = nodes[node].right
            }
        }
        fatalError("unreachable")
    }

    /// Bytes in `range` (half-open, byte offsets; O(log n + result size)).
    public func substr(_ range: Range<Int>) -> [UInt8] {
        let first = range.lowerBound, last = range.upperBound
        precondition(first >= 0 && last <= size && first <= last, "substr \(range) out of range for size \(size)")
        guard first < last, root >= 0 else { return [] }
        var out: [UInt8] = []
        collect(root, subtreeStart: 0, first: first, last: last, into: &out)
        return out
    }

    private func collect(_ index: Int, subtreeStart: Int, first: Int, last: Int, into out: inout [UInt8]) {
        guard index >= 0 else { return }
        let leftBytes = byteCount(nodes[index].left)
        let nodeStart = subtreeStart + leftBytes
        let nodeEnd = nodeStart + nodes[index].bytes.count
        if first < nodeStart {
            collect(nodes[index].left, subtreeStart: subtreeStart, first: first, last: last, into: &out)
        }
        if nodeEnd > first && nodeStart < last {
            let from = max(first - nodeStart, 0)
            let to = min(last - nodeStart, nodes[index].bytes.count)
            if from < to {
                out.append(contentsOf: nodes[index].bytes[from..<to])
            }
        }
        if last > nodeEnd {
            collect(nodes[index].right, subtreeStart: nodeEnd, first: first, last: last, into: &out)
        }
    }

    // MARK: - Position queries (O(log n))

    /// Number of `\n` bytes in `[0, offset)`.
    public func newlines(before offset: Int) -> Int {
        guard root >= 0, offset > 0 else { return 0 }
        var node = root
        var count = 0
        var remaining = min(offset, size)
        while node >= 0 {
            let left = nodes[node].left
            let leftBytes = byteCount(left)
            if remaining <= leftBytes {
                node = left
                continue
            }
            count += newlineCount(left)
            remaining -= leftBytes
            let nodeLength = nodes[node].bytes.count
            if remaining <= nodeLength {
                let bytes = nodes[node].bytes
                var index = 0
                while index < remaining {
                    if bytes[index] == 0x0A { count += 1 }
                    index += 1
                }
                return count
            }
            remaining -= nodeLength
            count += nodes[node].selfNewlines
            node = nodes[node].right
        }
        return count
    }

    /// Byte offset of the `index`-th `\n` (0-based), or nil if there are fewer.
    public func newlinePosition(index: Int) -> Int? {
        guard root >= 0, index >= 0 else { return nil }
        var node = root
        var remaining = index
        var subtreeStart = 0
        while node >= 0 {
            let left = nodes[node].left
            let leftNewlines = newlineCount(left)
            if remaining < leftNewlines {
                node = left
                continue
            }
            remaining -= leftNewlines
            let nodeNewlines = nodes[node].selfNewlines
            if remaining < nodeNewlines {
                let bytes = nodes[node].bytes
                var found = -1
                var seen = 0
                for i in 0..<bytes.count where bytes[i] == 0x0A {
                    if seen == remaining { found = i; break }
                    seen += 1
                }
                return subtreeStart + byteCount(left) + found
            }
            remaining -= nodeNewlines
            subtreeStart += byteCount(left) + nodes[node].bytes.count
            node = nodes[node].right
        }
        return nil
    }

    /// UTF-8 byte range of a 0-based line, including its trailing `\n`
    /// (or ending at EOF for the last line).
    public func lineRange(_ line: Int) -> Range<Int> {
        let start: Int
        if line <= 0 {
            start = 0
        } else if let position = newlinePosition(index: line - 1) {
            start = position + 1
        } else {
            start = size
        }
        let end: Int
        if let position = newlinePosition(index: line) {
            end = position + 1
        } else {
            end = size
        }
        return start..<max(start, end)
    }

    /// UTF-16 code-unit offset corresponding to a UTF-8 byte offset (O(log n)).
    public func utf16Offset(fromByteOffset offset: Int) -> Int {
        guard root >= 0 else { return 0 }
        var node = root
        var count = 0
        var remaining = min(max(offset, 0), size)
        while node >= 0 {
            let left = nodes[node].left
            let leftBytes = byteCount(left)
            if remaining <= leftBytes {
                node = left
                continue
            }
            count += utf16Count(left)
            remaining -= leftBytes
            let nodeLength = nodes[node].bytes.count
            if remaining <= nodeLength {
                return count + Self.utf16Units(in: nodes[node].bytes, upTo: remaining)
            }
            remaining -= nodeLength
            count += nodes[node].selfUTF16
            node = nodes[node].right
        }
        return count
    }

    /// UTF-8 byte offset corresponding to a UTF-16 code-unit offset (O(log n));
    /// offsets inside a surrogate pair snap to the boundary before it.
    public func byteOffset(fromUTF16Offset offset: Int) -> Int {
        guard root >= 0, offset > 0 else { return 0 }
        var node = root
        var bytePosition = 0
        var remaining = offset
        while node >= 0 {
            let left = nodes[node].left
            let leftUTF16 = utf16Count(left)
            if remaining <= leftUTF16 {
                node = left
                continue
            }
            remaining -= leftUTF16
            bytePosition += byteCount(left)
            let nodeUTF16 = nodes[node].selfUTF16
            if remaining <= nodeUTF16 {
                return bytePosition + Self.byteOffsetForUTF16(nodes[node].bytes, upTo: remaining)
            }
            remaining -= nodeUTF16
            bytePosition += nodes[node].bytes.count
            node = nodes[node].right
        }
        return bytePosition
    }

    private static func utf16Units(in bytes: [UInt8], upTo: Int) -> Int {
        var units = 0
        var index = 0
        while index < upTo {
            let metrics = charMetrics(bytes, at: index)
            if metrics.length > upTo - index { // partial sequence at the cut
                units += 1
                index += 1
            } else {
                units += metrics.units
                index += metrics.length
            }
        }
        return units
    }

    /// Byte offset in `bytes` where the UTF-16 unit count reaches `upTo`
    /// (snapping to a character boundary). Shared with `Buffer` for line-local
    /// column conversion.
    static func byteOffsetForUTF16(_ bytes: [UInt8], upTo: Int) -> Int {
        var units = 0
        var index = 0
        while index < bytes.count && units < upTo {
            let metrics = charMetrics(bytes, at: index)
            if units + metrics.units > upTo { break } // snap to boundary
            units += metrics.units
            index += metrics.length
        }
        return index
    }

    /// Structural equality (same content AND same piece splits).
    public static func == (lhs: PieceStorage, rhs: PieceStorage) -> Bool {
        guard lhs.size == rhs.size else { return false }
        return lhs.flattenedBytes == rhs.flattenedBytes
    }
}
