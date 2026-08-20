import Foundation

/// Document buffer built on `PieceStorage`. Provides UTF-8 byte-level editing
/// plus line/position mapping (roadmap 1.T1). Offsets are UTF-8 byte offsets,
/// matching `ng::buffer_t`'s index space.
public struct Buffer: Equatable {
    private var storage: PieceStorage

    public init() {
        storage = PieceStorage()
    }

    public init(_ string: String) {
        storage = PieceStorage(Array(string.utf8))
    }

    public init(_ bytes: [UInt8]) {
        storage = PieceStorage(bytes)
    }

    /// UTF-8 byte length.
    public var utf8Length: Int { storage.size }
    public var isEmpty: Bool { storage.isEmpty }

    /// Number of Unicode characters (O(n)).
    public var characterCount: Int { content.count }

    /// Whole document as a String (O(n)).
    public var content: String {
        String(decoding: storage.flattenedBytes, as: UTF8.self)
    }

    /// Raw UTF-8 bytes.
    public var bytes: [UInt8] { storage.flattenedBytes }

    // MARK: - Editing (UTF-8 byte offsets)

    public mutating func insert(_ string: String, at utf8Offset: Int) {
        storage.insert(Array(string.utf8), at: utf8Offset)
    }

    public mutating func erase(_ range: Range<Int>) {
        storage.erase(range)
    }

    public func substring(_ range: Range<Int>) -> String {
        String(decoding: storage.substr(range), as: UTF8.self)
    }

    public subscript(index: Int) -> UInt8 {
        storage[index]
    }

    // MARK: - Lines & positions

    /// Number of lines (1 for an empty buffer; `\n` terminates lines).
    public var lineCount: Int {
        var lines = 1
        for byte in storage.flattenedBytes where byte == 0x0A { lines += 1 }
        return lines
    }

    /// 0-based line index containing the given UTF-8 byte offset.
    public func lineIndex(atUtf8Offset offset: Int) -> Int {
        let bytes = storage.flattenedBytes
        let end = min(offset, bytes.count)
        var line = 0
        for i in 0..<end where bytes[i] == 0x0A { line += 1 }
        return line
    }

    /// UTF-8 byte range of a 0-based line, including its trailing `\n`
    /// (or a single trailing byte if the line ends with `\r\n`).
    public func lineRange(_ line: Int) -> Range<Int> {
        let bytes = storage.flattenedBytes
        var start = 0
        var currentLine = 0
        var index = 0
        while index < bytes.count && currentLine < line {
            if bytes[index] == 0x0A { currentLine += 1; start = index + 1 }
            index += 1
        }
        var end = start
        while end < bytes.count && bytes[end] != 0x0A { end += 1 }
        if end < bytes.count { end += 1 } // include the newline
        return start..<end
    }
}
