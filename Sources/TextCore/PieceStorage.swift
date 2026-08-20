import Foundation

/// A piece table: the document text is the concatenation of an ordered list of
/// immutable byte pieces. Insert/erase split pieces at the boundary instead of
/// copying the whole text, mirroring `ng::detail::storage_t` from the original
/// TextMate (Frameworks/buffer/src/storage.h).
///
/// The C++ original backs this with a balanced `oak::basic_tree_t`; this port
/// uses an array of pieces for correctness first (O(n) worst-case operations).
/// A tree-backed upgrade is tracked in the roadmap (perf gate 2.T3).
public struct PieceStorage: Equatable {
    public struct Piece: Equatable {
        public let bytes: [UInt8]
        public init(_ bytes: [UInt8]) { self.bytes = bytes }
        public var size: Int { bytes.count }
    }

    private var _pieces: [Piece]

    public init() {
        _pieces = []
    }

    public init(_ bytes: [UInt8]) {
        _pieces = bytes.isEmpty ? [] : [Piece(bytes)]
    }

    /// Total number of bytes.
    public var size: Int { _pieces.reduce(0) { $0 + $1.size } }
    public var isEmpty: Bool { _pieces.isEmpty }
    public var pieceCount: Int { _pieces.count }

    /// All bytes as a single array (O(n); convenience for equality/queries).
    public var flattenedBytes: [UInt8] { _pieces.flatMap { $0.bytes } }

    /// (piece index, offset within that piece) for a byte offset.
    private func locate(_ offset: Int) -> (piece: Int, within: Int) {
        var remaining = offset
        for (index, piece) in _pieces.enumerated() {
            if remaining < piece.size { return (index, remaining) }
            remaining -= piece.size
        }
        return (_pieces.count, 0)
    }

    public mutating func insert(_ data: [UInt8], at position: Int) {
        precondition((0...size).contains(position), "insert position \(position) out of range [0, \(size)]")
        guard !data.isEmpty else { return }
        guard !_pieces.isEmpty else {
            _pieces = [Piece(data)]
            return
        }
        if position == size {
            _pieces.append(Piece(data))
            return
        }
        let (index, within) = locate(position)
        let piece = _pieces[index]
        if within == 0 {
            _pieces.insert(Piece(data), at: index)
        } else if within == piece.size {
            _pieces.insert(Piece(data), at: index + 1)
        } else {
            let left = Piece(Array(piece.bytes[..<within]))
            let right = Piece(Array(piece.bytes[within...]))
            _pieces.replaceSubrange(index...index, with: [left, Piece(data), right])
        }
    }

    /// Erases bytes in `range` (half-open, byte offsets).
    public mutating func erase(_ range: Range<Int>) {
        let first = range.lowerBound, last = range.upperBound
        precondition(first >= 0 && last <= size && first <= last, "erase \(range) out of range for size \(size)")
        guard first < last, !_pieces.isEmpty else { return }

        let (startIndex, startWithin) = locate(first)
        var (endIndex, endWithin) = locate(last)
        if last == size {
            endIndex = _pieces.count - 1
            endWithin = _pieces[endIndex].size
        }

        var result: [Piece] = []
        result.append(contentsOf: _pieces[..<startIndex])

        if startIndex == endIndex {
            let bytes = _pieces[startIndex].bytes
            let left = Array(bytes[..<startWithin])
            let right = Array(bytes[endWithin...])
            if !left.isEmpty { result.append(Piece(left)) }
            if !right.isEmpty { result.append(Piece(right)) }
        } else {
            let left = Array(_pieces[startIndex].bytes[..<startWithin])
            if !left.isEmpty { result.append(Piece(left)) }
            let right = Array(_pieces[endIndex].bytes[endWithin...])
            if !right.isEmpty { result.append(Piece(right)) }
            if endIndex + 1 < _pieces.count {
                result.append(contentsOf: _pieces[(endIndex + 1)...])
            }
        }
        _pieces = result
    }

    public subscript(index: Int) -> UInt8 {
        precondition((0..<size).contains(index), "index \(index) out of range")
        let (pieceIndex, within) = locate(index)
        return _pieces[pieceIndex].bytes[within]
    }

    /// Bytes in `range` (half-open, byte offsets).
    public func substr(_ range: Range<Int>) -> [UInt8] {
        let first = range.lowerBound, last = range.upperBound
        precondition(first >= 0 && last <= size && first <= last, "substr \(range) out of range for size \(size)")
        guard first < last else { return [] }

        let (startIndex, startWithin) = locate(first)
        var (endIndex, endWithin) = locate(last)
        if last == size {
            endIndex = _pieces.count - 1
            endWithin = _pieces[endIndex].size
        }

        if startIndex == endIndex {
            return Array(_pieces[startIndex].bytes[startWithin..<endWithin])
        }
        var out: [UInt8] = []
        out.append(contentsOf: _pieces[startIndex].bytes[startWithin...])
        if startIndex + 1 < endIndex {
            for piece in _pieces[(startIndex + 1)..<endIndex] {
                out.append(contentsOf: piece.bytes)
            }
        }
        out.append(contentsOf: _pieces[endIndex].bytes[..<endWithin])
        return out
    }

    /// Ordered pieces (for iteration-style access).
    public var pieces: [Piece] { _pieces }

    /// Structural equality (same content AND same piece splits).
    public static func == (lhs: PieceStorage, rhs: PieceStorage) -> Bool {
        guard lhs.size == rhs.size else { return false }
        return lhs.flattenedBytes == rhs.flattenedBytes
    }
}
