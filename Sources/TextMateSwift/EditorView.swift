import AppKit
import TextCore

/// Engine-backed editor view (roadmap 2.S1 / issue #14). Renders a `TextCore`
/// `Buffer` directly from the piece tree — no `NSTextView` / `NSTextStorage` in
/// the pipeline. The view draws the visible lines, a caret and a selection, and
/// routes every edit back into the buffer, whose command stack backs undo/redo
/// (1.S2 / 2.S4).
///
/// Positions are UTF-8 byte offsets into the buffer, converted to line/column
/// for layout via `Buffer`'s UTF-16 mapping (1.T1). Layout is one visual row
/// per line (no wrapping yet — horizontal scrolling); large-document scrolling
/// is tracked separately (2.S3).
final class EditorView: NSView {

    // MARK: - Public state

    /// The document. All edits flow through this buffer (source of truth).
    private(set) var buffer: Buffer
    /// Current caret position as a UTF-8 byte offset.
    private(set) var caret: Int = 0
    /// Selection anchor (byte offset), or nil for no selection. The active end
    /// of the selection is always `caret`.
    private(set) var anchor: Int?

    /// Called after every user edit (content change) — used for dirty tracking.
    var onChange: (() -> Void)?

    /// Per-line grammar state driving syntax highlighting (4.S2).
    private let syntax: SyntaxParser

    // MARK: - Metrics & constants

    private let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    private let textInsetX: CGFloat = 8
    private let textInsetY: CGFloat = 4
    private let caretWidth: CGFloat = 2
    private let gutterWidth: CGFloat = 52

    private lazy var lineHeight: CGFloat = NSLayoutManager().defaultLineHeight(for: font)
    /// Exact per-character advance (not ceil'd): the caret and text must
    /// share the same grid, and ceil introduces ~1pt/char of drift that
    /// visibly detaches the caret from the last typed character.
    private lazy var charWidth: CGFloat = "M".size(withAttributes: [.font: font]).width
    private lazy var textAttributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.textColor,
    ]
    private lazy var gutterAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
        .foregroundColor: NSColor.secondaryLabelColor,
    ]

    /// Line range of the most recent edit — the incremental repair point for
    /// syntax highlighting.
    private var lastEditLine = 0
    private var lastEditEndLine = 0

    /// Column (in UTF-16 units) preserved across vertical caret moves so moving
    /// up/down past shorter lines returns to the original column.
    private var stickyColumn: Int?

    // MARK: - Init

    init(frame frameRect: NSRect, buffer: Buffer = Buffer()) {
        self.buffer = buffer
        self.syntax = SyntaxParser(grammar: Grammar(plist: BuiltInGrammar.plist)!)
        super.init(frame: frameRect)
        updateFrameSize()
        syntax.reload(buffer.content)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Replaces the document (open / new). Clears the caret and undo history.
    func load(_ newBuffer: Buffer) {
        buffer = newBuffer
        caret = 0
        anchor = nil
        stickyColumn = nil
        syntax.reload(buffer.content)
        updateFrameSize()
        scroll(NSPoint(x: 0, y: 0))
        needsDisplay = true
    }

    // MARK: - NSView basics

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
    override func resignFirstResponder() -> Bool { needsDisplay = true; return true }

    // MARK: - Layout

    /// Longest line in UTF-16 units × char width (drives the horizontal
    /// scroller). One byte-level pass over the document (runs per edit, not
    /// per frame).
    private var contentWidth: CGFloat {
        let bytes = buffer.bytes
        var maxUnits = 0
        var lineUnits = 0
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 0x0A {
                maxUnits = max(maxUnits, lineUnits)
                lineUnits = 0
                index += 1
            } else if byte < 0x80 {
                lineUnits += 1
                index += 1
            } else if let length = TextUTF8.sequenceLength(byte), index + length <= bytes.count {
                let scalar = TextUTF8.toScalar(Array(bytes[index..<(index + length)]))
                lineUnits += scalar > 0xFFFF ? 2 : 1
                index += length
            } else {
                lineUnits += 1
                index += 1
            }
        }
        maxUnits = max(maxUnits, lineUnits)
        return CGFloat(maxUnits) * charWidth
    }

    private func updateFrameSize() {
        let width = max(visibleRect.width, gutterWidth + contentWidth + textInsetX * 2)
        let height = max(visibleRect.height, CGFloat(buffer.lineCount) * lineHeight + textInsetY * 2)
        setFrameSize(NSSize(width: width, height: height))
    }

    private var visibleLineRange: Range<Int> {
        let first = max(0, Int(floor((visibleRect.minY - textInsetY) / lineHeight)))
        let last = min(max(0, buffer.lineCount - 1), Int(ceil((visibleRect.maxY - textInsetY) / lineHeight)))
        return first..<max(first + 1, last + 1)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.textBackgroundColor.setFill()
        bounds.fill()

        drawGutter()
        drawSelection()
        drawText()
        drawCaret()
    }

    /// Line-number gutter (4.S1 / issue #28).
    private func drawGutter() {
        let lineRange = visibleLineRange
        NSColor(calibratedWhite: 0, alpha: 0.04).setFill()
        NSRect(x: 0, y: bounds.minY, width: gutterWidth, height: bounds.height).fill()

        for line in lineRange {
            let number = "\(line + 1)" as NSString
            let size = number.size(withAttributes: gutterAttributes)
            let point = NSPoint(
                x: gutterWidth - textInsetX - size.width,
                y: textInsetY + CGFloat(line) * lineHeight + (lineHeight - size.height) / 2
            )
            number.draw(at: point, withAttributes: gutterAttributes)
        }

        NSColor.separatorColor.setFill()
        NSRect(x: gutterWidth - 1, y: bounds.minY, width: 1, height: bounds.height).fill()
    }

    /// Draws only the visible lines: two O(log n) line lookups + a substring
    /// of the visible region — cost scales with what's on screen, not the
    /// document size (roadmap 2.S3).
    private func drawText() {
        let lineRange = visibleLineRange
        let firstLine = lineRange.lowerBound
        let lastLine = lineRange.upperBound - 1
        guard buffer.lineCount > 0, firstLine <= lastLine else { return }

        let byteStart = buffer.lineRange(firstLine).lowerBound
        let byteEnd = buffer.lineRange(lastLine).upperBound
        let text = buffer.substring(byteStart..<byteEnd)

        var line = firstLine
        var lineStart = text.startIndex
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "\n" {
                drawLine(String(text[lineStart..<index]), line: line)
                line += 1
                lineStart = text.index(after: index)
                if line > lastLine { break }
            }
            index = text.index(after: index)
        }
        if line <= lastLine && lineStart < text.endIndex {
            drawLine(String(text[lineStart...]), line: line)
        }
    }

    private func drawLine(_ text: String, line: Int) {
        guard !text.isEmpty else { return }
        let ns = text as NSString
        let baseY = textInsetY + CGFloat(line) * lineHeight
        let baseX = gutterWidth + textInsetX

        // Split the line into scope runs (UTF-16 offsets from the scope map)
        // and draw each run in its theme color.
        let scopeMap = syntax.scopes(forLine: line)
        if scopeMap.isEmpty {
            ns.draw(at: NSPoint(x: baseX, y: baseY), withAttributes: textAttributes)
            return
        }
        let entries = scopeMap.sorted { $0.key < $1.key }
        var cursor = 0
        for (index, entry) in entries.enumerated() {
            let from = max(entry.key, cursor)
            let to = index + 1 < entries.count ? entries[index + 1].key : ns.length
            if to <= from { continue }
            var attributes = textAttributes
            attributes[.foregroundColor] = SyntaxTheme.color(for: entry.value)
            let run = ns.substring(with: NSRange(location: from, length: to - from))
            (run as NSString).draw(at: NSPoint(x: baseX + CGFloat(from) * charWidth, y: baseY), withAttributes: attributes)
            cursor = to
        }
    }

    private func drawSelection() {
        guard let range = selectedRange else { return }
        NSColor.selectedTextBackgroundColor.setFill()

        let firstLine = buffer.lineIndex(atUtf8Offset: range.lowerBound)
        let lastLine = buffer.lineIndex(atUtf8Offset: max(range.upperBound - 1, 0))
        for line in firstLine...lastLine {
            let lineRange = buffer.lineRange(line)
            let start = max(range.lowerBound, lineRange.lowerBound)
            var end = min(range.upperBound, lineRange.upperBound)
            if end <= start { continue }
            // Don't highlight the trailing newline itself.
            if end == lineRange.upperBound && end > start && buffer[end - 1] == 0x0A {
                end -= 1
            }
            if end <= start { continue }
            let col0 = buffer.lineColumn(atUtf8Offset: start).column
            let col1 = buffer.lineColumn(atUtf8Offset: end).column
            let x0 = gutterWidth + textInsetX + CGFloat(col0) * charWidth
            let x1 = gutterWidth + textInsetX + CGFloat(col1) * charWidth
            NSRect(
                x: x0,
                y: textInsetY + CGFloat(line) * lineHeight,
                width: max(x1 - x0, 1),
                height: lineHeight
            ).fill()
        }
    }

    private func drawCaret() {
        let (line, column) = buffer.lineColumn(atUtf8Offset: caret)
        let x = gutterWidth + textInsetX + CGFloat(column) * charWidth
        NSColor.textColor.setFill()
        NSRect(
            x: x,
            y: textInsetY + CGFloat(line) * lineHeight,
            width: caretWidth,
            height: lineHeight
        ).fill()
    }

    private func caretRect() -> NSRect {
        let (line, column) = buffer.lineColumn(atUtf8Offset: caret)
        return NSRect(
            x: gutterWidth + textInsetX + CGFloat(column) * charWidth,
            y: textInsetY + CGFloat(line) * lineHeight,
            width: caretWidth,
            height: lineHeight
        )
    }

    private func scrollCaretToVisible() {
        scrollToVisible(caretRect().insetBy(dx: -24, dy: -12))
    }

    // MARK: - Selection helpers

    private var selectedRange: Range<Int>? {
        guard let anchor else { return nil }
        let low = min(anchor, caret)
        let high = max(anchor, caret)
        return low < high ? low..<high : nil
    }

    private static let wordCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))

    private func isWord(_ scalar: UInt32) -> Bool {
        guard let scalar = Unicode.Scalar(scalar) else { return false }
        return Self.wordCharacters.contains(scalar)
    }

    private func selectWord(around offset: Int) {
        var start = offset
        var end = offset
        while start > 0 {
            let previous = buffer.previousCharacterBoundary(before: start)
            if isWord(buffer.character(at: previous).scalar) { start = previous } else { break }
        }
        while end < buffer.utf8Length {
            let (scalar, length) = buffer.character(at: end)
            if isWord(scalar) { end += length } else { break }
        }
        if start < end {
            anchor = start
            caret = end
        } else {
            anchor = offset
            caret = offset
        }
    }

    // MARK: - Mouse

    private func byteOffset(at point: NSPoint) -> Int {
        guard buffer.lineCount > 0 else { return 0 }
        let line = max(0, min(buffer.lineCount - 1, Int(floor((point.y - textInsetY) / lineHeight))))
        let column = max(0, Int(floor((point.x - gutterWidth - textInsetX) / charWidth)))
        return buffer.byteOffset(atLine: line, utf16Column: column)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        let offset = byteOffset(at: point)
        if event.clickCount == 2 {
            selectWord(around: offset)
        } else {
            caret = offset
            anchor = offset
        }
        stickyColumn = nil
        buffer.breakUndoCoalescing()
        scrollCaretToVisible()
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        caret = byteOffset(at: point)
        _ = autoscroll(with: event)
        needsDisplay = true
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags
        let shift = modifiers.contains(.shift)
        let option = modifiers.contains(.option)
        let command = modifiers.contains(.command)

        if modifiers.contains(.control) {
            super.keyDown(with: event)
            return
        }

        switch event.keyCode {
        case 36, 76:                    // Return / keypad Enter
            insertText("\n")
        case 48:                        // Tab
            insertText("\t")
        case 51:                        // Delete (backspace)
            deleteBackward()
        case 117:                       // fn + Delete
            deleteForward()
        case 123:                       // Left arrow
            if command { moveLineStart(shift: shift) } else { moveHorizontal(-1, shift: shift, word: option) }
        case 124:                       // Right arrow
            if command { moveLineEnd(shift: shift) } else { moveHorizontal(1, shift: shift, word: option) }
        case 125:                       // Down arrow
            if command { applyCaretMove(to: buffer.utf8Length, shift: shift) } else { moveVertical(1, shift: shift) }
        case 126:                       // Up arrow
            if command { applyCaretMove(to: 0, shift: shift) } else { moveVertical(-1, shift: shift) }
        case 115:                       // Home
            moveLineStart(shift: shift)
        case 119:                       // End
            moveLineEnd(shift: shift)
        case 53:                        // Escape
            break
        default:
            if command {
                super.keyDown(with: event)
            } else if let characters = event.characters,
                      !characters.isEmpty,
                      !characters.unicodeScalars.contains(where: { $0.value >= 0xF700 }) {
                insertText(characters)
            } else {
                super.keyDown(with: event)
            }
        }
    }

    // MARK: - Editing (all edits go through the buffer's undo stack)

    /// Records the affected line range for a byte range that is about to be
    /// replaced/erased (the end line is computed pre-mutation).
    private func trackEditRange(_ range: Range<Int>) {
        lastEditLine = buffer.lineIndex(atUtf8Offset: range.lowerBound)
        let endByte = max(range.upperBound - 1, range.lowerBound)
        lastEditEndLine = buffer.lineIndex(atUtf8Offset: endByte)
    }

    private func insertText(_ text: String) {
        guard !text.isEmpty else { return }
        let range = selectedRange ?? (caret..<caret)
        trackEditRange(range)
        if let range = selectedRange {
            buffer.replace(range, with: text)
            caret = range.lowerBound + text.utf8.count
            anchor = nil
        } else {
            buffer.insert(text, at: caret)
            caret += text.utf8.count
        }
        stickyColumn = nil
        didEdit()
    }

    private func deleteBackward() {
        if let range = selectedRange {
            trackEditRange(range)
            buffer.erase(range)
            caret = range.lowerBound
            anchor = nil
        } else if caret > 0 {
            let start = buffer.previousCharacterBoundary(before: caret)
            trackEditRange(start..<caret)
            buffer.erase(start..<caret)
            caret = start
        } else {
            NSSound.beep()
            return
        }
        stickyColumn = nil
        didEdit()
    }

    private func deleteForward() {
        if let range = selectedRange {
            trackEditRange(range)
            buffer.erase(range)
            caret = range.lowerBound
            anchor = nil
        } else if caret < buffer.utf8Length {
            let end = buffer.nextCharacterBoundary(after: caret)
            trackEditRange(caret..<end)
            buffer.erase(caret..<end)
        } else {
            NSSound.beep()
            return
        }
        stickyColumn = nil
        didEdit()
    }

    private func didEdit() {
        syntax.updateText(buffer.content, fromLine: lastEditLine, endLine: lastEditEndLine)
        onChange?()
        updateFrameSize()
        needsDisplay = true
        scrollCaretToVisible()
    }

    // MARK: - Caret movement

    private func applyCaretMove(to newOffset: Int, shift: Bool) {
        if shift {
            if anchor == nil { anchor = caret }
            caret = newOffset
        } else {
            anchor = nil
            caret = newOffset
        }
        buffer.breakUndoCoalescing()
        scrollCaretToVisible()
        needsDisplay = true
    }

    private func moveHorizontal(_ delta: Int, shift: Bool, word: Bool) {
        // Without shift, a selection collapses to its active end first.
        if !shift, anchor != nil {
            caret = delta < 0 ? min(anchor!, caret) : max(anchor!, caret)
            anchor = nil
        }
        let target = word ? wordBoundary(forward: delta > 0) : (
            delta < 0 ? buffer.previousCharacterBoundary(before: caret) : buffer.nextCharacterBoundary(after: caret)
        )
        stickyColumn = nil
        applyCaretMove(to: target, shift: shift)
    }

    private func moveVertical(_ delta: Int, shift: Bool) {
        let column = stickyColumn ?? buffer.lineColumn(atUtf8Offset: caret).column
        stickyColumn = column
        let currentLine = buffer.lineIndex(atUtf8Offset: caret)
        let targetLine = max(0, min(buffer.lineCount - 1, currentLine + delta))
        let target = buffer.byteOffset(atLine: targetLine, utf16Column: column)
        applyCaretMove(to: target, shift: shift)
    }

    private func moveLineStart(shift: Bool) {
        let line = buffer.lineIndex(atUtf8Offset: caret)
        stickyColumn = nil
        applyCaretMove(to: buffer.lineRange(line).lowerBound, shift: shift)
    }

    private func moveLineEnd(shift: Bool) {
        let line = buffer.lineIndex(atUtf8Offset: caret)
        let range = buffer.lineRange(line)
        let end = range.upperBound - (range.upperBound > range.lowerBound && buffer[range.upperBound - 1] == 0x0A ? 1 : 0)
        stickyColumn = nil
        applyCaretMove(to: end, shift: shift)
    }

    private func wordBoundary(forward: Bool) -> Int {
        var offset = caret
        if forward {
            // Skip leading whitespace, then the word run.
            while offset < buffer.utf8Length {
                let (scalar, length) = buffer.character(at: offset)
                if isWord(scalar) { break }
                offset += length
            }
            while offset < buffer.utf8Length {
                let (scalar, length) = buffer.character(at: offset)
                if !isWord(scalar) { break }
                offset += length
            }
        } else {
            while offset > 0 {
                let previous = buffer.previousCharacterBoundary(before: offset)
                if isWord(buffer.character(at: previous).scalar) { break }
                offset = previous
            }
            while offset > 0 {
                let previous = buffer.previousCharacterBoundary(before: offset)
                if !isWord(buffer.character(at: previous).scalar) { break }
                offset = previous
            }
        }
        return offset
    }

    // MARK: - Responder-chain actions (Edit menu → first responder)

    @objc func undo(_ sender: Any?) {
        guard let newCaret = buffer.undo() else { NSSound.beep(); return }
        caret = newCaret
        anchor = nil
        stickyColumn = nil
        lastEditLine = 0
        lastEditEndLine = buffer.lineCount - 1
        didEdit()
    }

    @objc func redo(_ sender: Any?) {
        guard let newCaret = buffer.redo() else { NSSound.beep(); return }
        caret = newCaret
        anchor = nil
        stickyColumn = nil
        lastEditLine = 0
        lastEditEndLine = buffer.lineCount - 1
        didEdit()
    }

    @objc func copy(_ sender: Any?) {
        guard let range = selectedRange else { NSSound.beep(); return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(buffer.substring(range), forType: .string)
    }

    @objc func cut(_ sender: Any?) {
        guard let range = selectedRange else { NSSound.beep(); return }
        copy(sender)
        trackEditRange(range)
        buffer.erase(range)
        caret = range.lowerBound
        anchor = nil
        stickyColumn = nil
        didEdit()
    }

    @objc func paste(_ sender: Any?) {
        guard let text = NSPasteboard.general.string(forType: .string) else { NSSound.beep(); return }
        insertText(text)
    }

    /// Loads a `.tmLanguage` grammar (or a `.tmBundle` directory) from disk
    /// and applies it to this document (4.S6).
    @objc func loadGrammar(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.title = "Load Grammar"
        panel.prompt = "Load"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.allowedFileTypes = ["tmLanguage", "tmBundle", "plist"]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let grammar = GrammarLoader.grammar(fromAny: url) else {
            NSSound.beep()
            return
        }
        syntax.setGrammar(grammar)
        needsDisplay = true
    }

    // `selectAll:` is declared on NSResponder, so it must use `override`.
    override func selectAll(_ sender: Any?) {
        anchor = 0
        caret = buffer.utf8Length
        buffer.breakUndoCoalescing()
        needsDisplay = true
    }

    // Correct enabled state for the Edit menu (2.S4 AC).
    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(undo(_:)): return buffer.canUndo
        case #selector(redo(_:)): return buffer.canRedo
        case #selector(cut(_:)), #selector(copy(_:)): return selectedRange != nil
        case #selector(paste(_:)): return NSPasteboard.general.string(forType: .string) != nil
        default: return true
        }
    }
}
