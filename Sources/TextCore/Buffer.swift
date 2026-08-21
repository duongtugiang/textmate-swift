import Foundation

/// One edit recorded for undo/redo. `Buffer` stores these in its undo stack
/// (roadmap 0.T4 → 1.S2); each command knows how to invert itself.
public enum EditCommand: Equatable {
    /// Text inserted at a UTF-8 byte offset.
    case insert(String, at: Int)
    /// Text erased from a UTF-8 byte range (the removed text is kept for redo).
    case erase(Range<Int>, removed: String)
    /// A selection replaced by new text — a single undo step for replace-typing.
    case replace(Range<Int>, removed: String, inserted: String)
}

/// Document buffer built on `PieceStorage`. Provides UTF-8 byte-level editing,
/// line/position mapping (roadmap 1.T1) and a command-based undo stack wired to
/// the editing surface (1.S2 / 2.S4). Offsets are UTF-8 byte offsets, matching
/// `ng::buffer_t`'s index space; UTF-16 conversion helpers bridge to AppKit.
public struct Buffer: Equatable {
    private var storage: PieceStorage
    private var undoStack: [EditCommand] = []
    private var redoStack: [EditCommand] = []
    /// Consecutive typing at the same spot coalesces into one undo step, like
    /// TextMate. `breakUndoCoalescing()` stops the *next* insert from merging.
    private var canCoalesceInsert = true

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

    // MARK: - Undo / redo state

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    public var undoDepth: Int { undoStack.count }

    /// Stops the next insert from coalescing with the previous one (call after
    /// the caret moves or the selection changes).
    public mutating func breakUndoCoalescing() {
        canCoalesceInsert = false
    }

    /// Undoes the most recent edit, returning the byte offset the caret should
    /// move to, or nil if there is nothing to undo.
    @discardableResult
    public mutating func undo() -> Int? {
        guard let command = undoStack.popLast() else { return nil }
        let caret: Int
        switch command {
        case .insert(let string, let at):
            storage.erase(at..<(at + string.utf8.count))
            caret = at
        case .erase(let range, let removed):
            storage.insert(Array(removed.utf8), at: range.lowerBound)
            caret = range.lowerBound + removed.utf8.count
        case .replace(let range, let removed, let inserted):
            storage.erase(range.lowerBound..<(range.lowerBound + inserted.utf8.count))
            storage.insert(Array(removed.utf8), at: range.lowerBound)
            caret = range.lowerBound + removed.utf8.count
        }
        redoStack.append(command)
        canCoalesceInsert = false
        return caret
    }

    /// Redoes the most recently undone edit, returning the caret position, or
    /// nil if there is nothing to redo.
    @discardableResult
    public mutating func redo() -> Int? {
        guard let command = redoStack.popLast() else { return nil }
        let caret: Int
        switch command {
        case .insert(let string, let at):
            storage.insert(Array(string.utf8), at: at)
            caret = at + string.utf8.count
        case .erase(let range, _):
            storage.erase(range)
            caret = range.lowerBound
        case .replace(let range, let removed, let inserted):
            storage.erase(range)
            storage.insert(Array(inserted.utf8), at: range.lowerBound)
            caret = range.lowerBound + inserted.utf8.count
        }
        undoStack.append(command)
        canCoalesceInsert = false
        return caret
    }

    // MARK: - Editing (UTF-8 byte offsets)

    /// Inserts text at a UTF-8 byte offset, recording an undo command. Consecutive
    /// typing at the same spot coalesces into a single undo step.
    public mutating func insert(_ string: String, at utf8Offset: Int) {
        storage.insert(Array(string.utf8), at: utf8Offset)
        if canCoalesceInsert, case .insert(let previous, let previousAt)? = undoStack.last,
           previousAt + previous.utf8.count == utf8Offset {
            undoStack[undoStack.count - 1] = .insert(previous + string, at: previousAt)
        } else {
            undoStack.append(.insert(string, at: utf8Offset))
        }
        redoStack.removeAll()
        canCoalesceInsert = true
    }

    /// Erases a UTF-8 byte range, recording an undo command (the removed text is
    /// kept so redo can restore it).
    public mutating func erase(_ range: Range<Int>) {
        let removed = substring(range)
        storage.erase(range)
        undoStack.append(.erase(range, removed: removed))
        redoStack.removeAll()
        canCoalesceInsert = false
    }

    /// Replaces a range with new text as a single undo step (used when typing
    /// over a selection).
    public mutating func replace(_ range: Range<Int>, with string: String) {
        let removed = substring(range)
        storage.erase(range)
        storage.insert(Array(string.utf8), at: range.lowerBound)
        undoStack.append(.replace(range, removed: removed, inserted: string))
        redoStack.removeAll()
        canCoalesceInsert = false
    }

    public func substring(_ range: Range<Int>) -> String {
        String(decoding: storage.substr(range), as: UTF8.self)
    }

    public subscript(index: Int) -> UInt8 {
        storage[index]
    }

    /// (code point, byte length) of the character starting at `offset`. Malformed
    /// or out-of-range bytes decode as U+FFFD of length 1.
    public func character(at offset: Int) -> (scalar: UInt32, length: Int) {
        guard offset >= 0, offset < utf8Length else { return (0xFFFD, 1) }
        let byte = storage[offset]
        if byte < 0x80 { return (UInt32(byte), 1) }
        guard let length = TextUTF8.sequenceLength(byte), offset + length <= utf8Length else {
            return (0xFFFD, 1)
        }
        for i in 1..<length where (storage[offset + i] & 0xC0) != 0x80 { return (0xFFFD, 1) }
        var bytes = [UInt8](repeating: 0, count: length)
        for i in 0..<length { bytes[i] = storage[offset + i] }
        return (TextUTF8.toScalar(bytes), length)
    }

    /// Byte offset of the character boundary strictly after `offset` (clamped to
    /// the document length).
    public func nextCharacterBoundary(after offset: Int) -> Int {
        guard offset >= 0 && offset < utf8Length else { return utf8Length }
        return min(offset + character(at: offset).length, utf8Length)
    }

    /// Byte offset of the character boundary at or before `offset`.
    public func previousCharacterBoundary(before offset: Int) -> Int {
        var index = min(max(offset, 0), utf8Length)
        while index > 0 && (storage[index - 1] & 0xC0) == 0x80 { index -= 1 }
        // The loop stops at the first continuation byte; step back onto the lead.
        if index > 0 { index -= 1 }
        return index
    }

    // MARK: - Lines & positions (O(log n) via the tree aggregates)

    /// Number of lines (1 for an empty buffer; `\n` terminates lines).
    public var lineCount: Int { storage.newlineCount + 1 }

    /// 0-based line index containing the given UTF-8 byte offset.
    public func lineIndex(atUtf8Offset offset: Int) -> Int {
        storage.newlines(before: min(max(offset, 0), utf8Length))
    }

    /// UTF-8 byte range of a 0-based line, including its trailing `\n`
    /// (or a single trailing byte if the line ends with `\r\n`).
    public func lineRange(_ line: Int) -> Range<Int> {
        storage.lineRange(line)
    }

    // MARK: - UTF-16 mapping (roadmap 1.T1)

    /// Converts a UTF-8 byte offset to a UTF-16 code-unit offset (what AppKit
    /// text APIs use), O(log n) via the tree aggregates. Out-of-range offsets
    /// clamp to the document ends.
    public func utf16Offset(fromByteOffset offset: Int) -> Int {
        storage.utf16Offset(fromByteOffset: offset)
    }

    /// Converts a UTF-16 code-unit offset to a UTF-8 byte offset, O(log n).
    /// Offsets that fall inside a surrogate pair snap to the character boundary
    /// before it.
    public func byteOffset(fromUTF16Offset offset: Int) -> Int {
        storage.byteOffset(fromUTF16Offset: offset)
    }

    /// (0-based line, UTF-16 column within that line) for a UTF-8 byte offset.
    public func lineColumn(atUtf8Offset offset: Int) -> (line: Int, column: Int) {
        let line = lineIndex(atUtf8Offset: offset)
        let lineStart = lineRange(line).lowerBound
        let column = utf16Offset(fromByteOffset: offset) - utf16Offset(fromByteOffset: lineStart)
        return (line, column)
    }

    /// UTF-8 byte offset for a (line, UTF-16 column) position; column snaps to
    /// the end of the line's content (before its trailing newline).
    public func byteOffset(atLine line: Int, utf16Column column: Int) -> Int {
        let range = lineRange(max(0, min(line, lineCount - 1)))
        let contentEnd = range.upperBound - (range.upperBound > range.lowerBound && storage[range.upperBound - 1] == 0x0A ? 1 : 0)
        let lineBytes = storage.substr(range.lowerBound..<contentEnd)
        return range.lowerBound + PieceStorage.byteOffsetForUTF16(lineBytes, upTo: column)
    }

    /// Equality by document content only (undo stacks are not part of the
    /// document's identity).
    public static func == (lhs: Buffer, rhs: Buffer) -> Bool {
        lhs.storage == rhs.storage
    }
}
