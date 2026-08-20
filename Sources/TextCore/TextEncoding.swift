import Foundation

/// Text encoding utilities (roadmap 1.T3), specified by the original TextMate
/// `text/utf8` and `text/transcode` frameworks.
public enum TextEncoding {

    /// Validates a byte sequence as strict UTF-8: rejects overlong encodings,
    /// surrogates (U+D800–U+DFFF), and out-of-range code points.
    public static func isValidUTF8(_ bytes: [UInt8]) -> Bool {
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte < 0x80 {
                index += 1
                continue
            }

            var continuationCount = 0
            var lowerBound: UInt8 = 0x80
            var upperBound: UInt8 = 0xBF
            switch byte {
            case 0xC2...0xDF: continuationCount = 1
            case 0xE0: continuationCount = 2; lowerBound = 0xA0 // no overlong
            case 0xE1...0xEC: continuationCount = 2
            case 0xED: continuationCount = 2; upperBound = 0x9F // no surrogates
            case 0xEE...0xEF: continuationCount = 2
            case 0xF0: continuationCount = 3; lowerBound = 0x90 // no overlong
            case 0xF1...0xF3: continuationCount = 3
            case 0xF4: continuationCount = 3; upperBound = 0x8F // max U+10FFFF
            default: return false
            }
            guard index + continuationCount < bytes.count else { return false }
            index += 1
            guard bytes[index] >= lowerBound && bytes[index] <= upperBound else { return false }
            for _ in 1..<continuationCount {
                index += 1
                guard bytes[index] >= 0x80 && bytes[index] <= 0xBF else { return false }
            }
            index += 1
        }
        return true
    }

    /// Normalizes a string to NFC (canonical composition).
    public static func normalizedNFC(_ string: String) -> String {
        string.precomposedStringWithCanonicalMapping
    }
}

/// A minimal undo/redo stack (roadmap 0.T4). Records whole states; callers
/// decide what a "state" is (e.g. buffer + caret). The AppKit UI additionally
/// gets full edit-level undo from `NSTextView`'s undo manager.
public struct UndoStack<State> {
    private var undoStack: [State] = []
    private var redoStack: [State] = []

    public init() {}

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    public var undoDepth: Int { undoStack.count }

    /// Records a new state; clears the redo branch.
    public mutating func record(_ state: State) {
        undoStack.append(state)
        redoStack.removeAll()
    }

    /// Pops the latest undo state and moves it to the redo branch.
    public mutating func undo() -> State? {
        guard let state = undoStack.popLast() else { return nil }
        redoStack.append(state)
        return state
    }

    /// Pops the latest redo state and moves it back to the undo branch.
    public mutating func redo() -> State? {
        guard let state = redoStack.popLast() else { return nil }
        undoStack.append(state)
        return state
    }
}
