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

    // MARK: - Find state (4.S4)

    /// Byte ranges of all current find matches (non-empty query only).
    private var findMatches: [Range<Int>] = []
    /// Index into `findMatches` of the active match (⌘G target).
    private var currentFindIndex = -1
    private var findQuery = ""
    private var findCaseSensitive = false
    /// Set by the window controller to reveal the find bar (⌘F).
    var onShowFindBar: (() -> Void)?
    /// Called after find state changes (the bar shows match counts).
    var onFindStateChange: (() -> Void)?

    var findMatchCount: Int { findMatches.count }

    private var currentFindRange: Range<Int>? {
        guard currentFindIndex >= 0, currentFindIndex < findMatches.count else { return nil }
        return findMatches[currentFindIndex]
    }

    /// Column (in UTF-16 units) preserved across vertical caret moves so moving
    /// up/down past shorter lines returns to the original column.
    private var stickyColumn: Int?

    // MARK: - Folding state (4.S3)

    /// Foldable ranges as `startLine..<lastHidden + 1` (start line visible).
    private var foldableRanges: [Range<Int>] = []
    /// Indices into `foldableRanges` that are currently folded.
    private var foldedSet: Set<Int> = []
    /// Folded ranges currently hiding lines.
    private var foldedRanges: [Range<Int>] = []
    /// Document lines currently visible, in document order (folded lines
    /// removed) — the row→line mapping for all drawing.
    private var visibleLines: [Int] = []

    private var visibleLineCount: Int { visibleLines.count }

    /// A line is hidden when it is inside a folded range past the marker line.
    private func isLineVisible(_ line: Int) -> Bool {
        for range in foldedRanges where line > range.lowerBound && line < range.upperBound {
            return false
        }
        return true
    }

    private func row(ofLine line: Int) -> Int? {
        visibleLines.firstIndex(of: line)
    }

    private func refreshVisibleLines() {
        visibleLines = (0..<buffer.lineCount).filter { isLineVisible($0) }
    }

    /// Recomputes foldable ranges from the grammar + indentation. Drops folds
    /// that no longer exist.
    private func refreshFolds() {
        let newRanges = TextFolds.foldableRanges(syntax.foldInfo())
        var kept: Set<Int> = []
        for index in foldedSet {
            if index < newRanges.count { kept.insert(index) }
        }
        foldableRanges = newRanges
        foldedSet = kept
        recomputeFoldedRanges()
    }

    private func recomputeFoldedRanges() {
        foldedRanges = foldedSet.sorted().map { foldableRanges[$0] }
        refreshVisibleLines()
        clampCaretToVisible()
        updateFrameSize()
        needsDisplay = true
    }

    /// Keeps the caret on a visible line after a fold (moves it to the end of
    /// the enclosing marker line).
    private func clampCaretToVisible() {
        let line = buffer.lineIndex(atUtf8Offset: caret)
        guard !isLineVisible(line) else { return }
        if let range = foldedRanges.first(where: { line > $0.lowerBound && line < $0.upperBound }) {
            var end = buffer.lineRange(range.lowerBound).upperBound
            if end > range.lowerBound, buffer[end - 1] == 0x0A { end -= 1 }
            caret = end
            anchor = nil
        }
    }

    private func toggleFold(atLine line: Int) {
        guard let index = foldableRanges.firstIndex(where: { $0.lowerBound == line }) else { return }
        if foldedSet.contains(index) {
            foldedSet.remove(index)
        } else {
            foldedSet.insert(index)
        }
        recomputeFoldedRanges()
    }

    /// Unfolds every range covering the given line (⌘⌥]).
    private func unfold(atLine line: Int) {
        var changed = false
        for index in foldedSet {
            let range = foldableRanges[index]
            if line > range.lowerBound && line < range.upperBound {
                foldedSet.remove(index)
                changed = true
            }
        }
        if changed { recomputeFoldedRanges() }
    }

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
        refreshFolds()
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
        let height = max(visibleRect.height, CGFloat(visibleLineCount) * lineHeight + textInsetY * 2)
        setFrameSize(NSSize(width: width, height: height))
    }

    /// Visible *rows* in the viewport (folded lines don't consume rows).
    private var visibleRowRange: Range<Int> {
        let first = max(0, Int(floor((visibleRect.minY - textInsetY) / lineHeight)))
        let last = min(max(0, visibleLineCount - 1), Int(ceil((visibleRect.maxY - textInsetY) / lineHeight)))
        return first..<max(first + 1, last + 1)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.textBackgroundColor.setFill()
        bounds.fill()

        drawGutter()
        drawSelection()
        drawFindHighlights()
        drawText()
        drawCaret()
    }

    /// Line-number gutter (4.S1 / issue #28) + fold markers (4.S3).
    private func drawGutter() {
        let rowRange = visibleRowRange
        NSColor(calibratedWhite: 0, alpha: 0.04).setFill()
        NSRect(x: 0, y: bounds.minY, width: gutterWidth, height: bounds.height).fill()

        for row in rowRange {
            let line = visibleLines[row]
            let number = "\(line + 1)" as NSString
            let size = number.size(withAttributes: gutterAttributes)
            let point = NSPoint(
                x: gutterWidth - textInsetX - size.width,
                y: textInsetY + CGFloat(row) * lineHeight + (lineHeight - size.height) / 2
            )
            number.draw(at: point, withAttributes: gutterAttributes)

            drawFoldMarkerIfNeeded(line: line, row: row)
        }

        NSColor.separatorColor.setFill()
        NSRect(x: gutterWidth - 1, y: bounds.minY, width: 1, height: bounds.height).fill()
    }

    /// ▸ (foldable, unfolded) / ▾ (folded) marker at the left of the gutter.
    private func drawFoldMarkerIfNeeded(line: Int, row: Int) {
        guard let index = foldableRanges.firstIndex(where: { $0.lowerBound == line }) else { return }
        let folded = foldedSet.contains(index)
        let marker = (folded ? "▾" : "▸") as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: folded ? NSColor.controlAccentColor : NSColor.secondaryLabelColor,
        ]
        marker.draw(at: NSPoint(x: 2, y: textInsetY + CGFloat(row) * lineHeight + (lineHeight - 12) / 2), withAttributes: attrs)
    }

    /// Draws only the visible lines: two O(log n) line lookups + a substring
    /// of the visible region — cost scales with what's on screen, not the
    /// document size (roadmap 2.S3).
    private func drawText() {
        let rowRange = visibleRowRange
        guard !visibleLines.isEmpty else { return }
        for row in rowRange {
            guard row < visibleLines.count else { break }
            let line = visibleLines[row]
            let range = buffer.lineRange(line)
            var end = range.upperBound
            if end > range.lowerBound && buffer[end - 1] == 0x0A { end -= 1 }
            let text = buffer.substring(range.lowerBound..<end)
            drawLine(text, row: row, line: line)
        }
    }

    private func drawLine(_ text: String, row: Int, line: Int) {
        guard !text.isEmpty else { return }
        let ns = text as NSString
        let baseY = textInsetY + CGFloat(row) * lineHeight
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
            guard let row = row(ofLine: line) else { continue }
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
                y: textInsetY + CGFloat(row) * lineHeight,
                width: max(x1 - x0, 1),
                height: lineHeight
            ).fill()
        }
    }

    private func drawCaret() {
        let (line, column) = buffer.lineColumn(atUtf8Offset: caret)
        guard let row = row(ofLine: line) else { return }
        let x = gutterWidth + textInsetX + CGFloat(column) * charWidth
        NSColor.textColor.setFill()
        NSRect(
            x: x,
            y: textInsetY + CGFloat(row) * lineHeight,
            width: caretWidth,
            height: lineHeight
        ).fill()
    }

    private func caretRect() -> NSRect {
        let (line, column) = buffer.lineColumn(atUtf8Offset: caret)
        guard let row = row(ofLine: line) else {
            return NSRect(x: gutterWidth + textInsetX, y: textInsetY, width: caretWidth, height: lineHeight)
        }
        return NSRect(
            x: gutterWidth + textInsetX + CGFloat(column) * charWidth,
            y: textInsetY + CGFloat(row) * lineHeight,
            width: caretWidth,
            height: lineHeight
        )
    }

    private func scrollCaretToVisible() {
        scrollToVisible(caretRect().insetBy(dx: -24, dy: -12))
    }

    // MARK: - Find & Replace (4.S4)

    /// Recomputes matches for the query. Preserves the active match when it
    /// still exists; otherwise the first match at/after the caret.
    func updateFind(query: String, caseSensitive: Bool = false) {
        findQuery = query
        findCaseSensitive = caseSensitive
        guard !query.isEmpty else {
            findMatches = []
            currentFindIndex = -1
            onFindStateChange?()
            needsDisplay = true
            return
        }
        let options: NSRegularExpression.Options = caseSensitive
            ? [.anchorsMatchLines]
            : [.caseInsensitive, .anchorsMatchLines]
        guard let regex = try? NSRegularExpression(pattern: query, options: options) else {
            findMatches = []
            currentFindIndex = -1
            onFindStateChange?()
            needsDisplay = true
            return
        }
        let content = buffer.content
        let ns = content as NSString
        var matches: [Range<Int>] = []
        regex.enumerateMatches(in: content, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match else { return }
            let start = buffer.byteOffset(fromUTF16Offset: match.range.location)
            let end = buffer.byteOffset(fromUTF16Offset: match.range.location + match.range.length)
            matches.append(start..<end)
        }
        findMatches = matches
        if let current = currentFindRange, let index = matches.firstIndex(where: { $0 == current }) {
            currentFindIndex = index
        } else {
            currentFindIndex = matches.firstIndex { $0.lowerBound >= caret } ?? (matches.isEmpty ? -1 : 0)
        }
        onFindStateChange?()
        needsDisplay = true
    }

    @discardableResult
    func findNext() -> Bool {
        guard !findMatches.isEmpty else { return false }
        var index: Int
        if let current = currentFindRange, let found = findMatches.firstIndex(of: current) {
            index = found + 1
        } else {
            index = findMatches.firstIndex { $0.lowerBound >= caret } ?? 0
        }
        if index >= findMatches.count { index = 0 }
        currentFindIndex = index
        selectCurrentFindMatch()
        return true
    }

    @discardableResult
    func findPrevious() -> Bool {
        guard !findMatches.isEmpty else { return false }
        var index: Int
        if let current = currentFindRange, let found = findMatches.firstIndex(of: current) {
            index = found - 1
        } else {
            index = findMatches.lastIndex { $0.lowerBound <= caret } ?? findMatches.count - 1
        }
        if index < 0 { index = findMatches.count - 1 }
        currentFindIndex = index
        selectCurrentFindMatch()
        return true
    }

    private func selectCurrentFindMatch() {
        guard let range = currentFindRange else { return }
        buffer.breakUndoCoalescing()
        anchor = range.lowerBound
        caret = range.upperBound
        stickyColumn = nil
        scrollCaretToVisible()
        needsDisplay = true
    }

    /// Replaces the active match; then jumps to the next one (replace-and-find).
    @discardableResult
    func replaceCurrentFindMatch(with replacement: String) -> Bool {
        guard let range = currentFindRange else { return false }
        trackEditRange(range)
        buffer.replace(range, with: replacement)
        caret = range.lowerBound + replacement.utf8.count
        anchor = nil
        stickyColumn = nil
        didEdit()
        findNext()
        return true
    }

    /// Replaces every match in one undo step (offsets are computed against the
    /// original content, so replacement order doesn't matter).
    @discardableResult
    func replaceAllFindMatches(with replacement: String) -> Int {
        guard !findMatches.isEmpty else { return 0 }
        let content = buffer.content
        let ns = content as NSString
        var result = ""
        var cursor = 0
        for range in findMatches {
            let utf16Start = buffer.utf16Offset(fromByteOffset: range.lowerBound)
            let utf16End = buffer.utf16Offset(fromByteOffset: range.upperBound)
            result += ns.substring(with: NSRange(location: cursor, length: utf16Start - cursor))
            result += replacement
            cursor = utf16End
        }
        result += ns.substring(from: cursor)
        trackEditRange(0..<buffer.utf8Length)
        buffer.replace(0..<buffer.utf8Length, with: result)
        caret = min(caret, buffer.utf8Length)
        anchor = nil
        stickyColumn = nil
        didEdit()
        return findMatches.count
    }

    // Responder-chain actions for the Edit ▸ Find menu (also reachable from
    // the find bar's own fields via the responder chain).
    @objc func showFindBar(_ sender: Any?) { onShowFindBar?() }
    @objc func findNext(_ sender: Any?) { _ = findNext() }
    @objc func findPrevious(_ sender: Any?) { _ = findPrevious() }

    /// Highlights every find match (active match more strongly), under the text.
    private func drawFindHighlights() {
        guard !findMatches.isEmpty else { return }
        for (index, range) in findMatches.enumerated() {
            drawMatchHighlight(range, current: index == currentFindIndex)
        }
    }

    private func drawMatchHighlight(_ range: Range<Int>, current: Bool) {
        let firstLine = buffer.lineIndex(atUtf8Offset: range.lowerBound)
        let lastLine = buffer.lineIndex(atUtf8Offset: max(range.upperBound - 1, range.lowerBound))
        for line in firstLine...lastLine {
            guard let row = row(ofLine: line) else { continue }
            let lineRange = buffer.lineRange(line)
            let start = max(range.lowerBound, lineRange.lowerBound)
            var end = min(range.upperBound, lineRange.upperBound)
            if end <= start { continue }
            if end == lineRange.upperBound && end > start && buffer[end - 1] == 0x0A { end -= 1 }
            if end <= start { continue }
            let col0 = buffer.lineColumn(atUtf8Offset: start).column
            let col1 = buffer.lineColumn(atUtf8Offset: end).column
            let fill = current
                ? (NSColor.systemYellow.blended(withFraction: 0.45, of: .orange) ?? .systemYellow)
                : NSColor.systemYellow.withAlphaComponent(0.32)
            fill.setFill()
            NSRect(
                x: gutterWidth + textInsetX + CGFloat(col0) * charWidth,
                y: textInsetY + CGFloat(row) * lineHeight,
                width: max(CGFloat(col1 - col0) * charWidth, 1),
                height: lineHeight
            ).fill()
        }
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
        guard !visibleLines.isEmpty else { return 0 }
        let row = max(0, min(visibleLineCount - 1, Int(floor((point.y - textInsetY) / lineHeight))))
        let line = visibleLines[row]
        let column = max(0, Int(floor((point.x - gutterWidth - textInsetX) / charWidth)))
        return buffer.byteOffset(atLine: line, utf16Column: column)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)

        // Gutter clicks toggle fold markers (4.S3).
        if point.x < gutterWidth, !foldableRanges.isEmpty {
            let row = max(0, Int(floor((point.y - textInsetY) / lineHeight)))
            if row < visibleLines.count {
                let line = visibleLines[row]
                if foldableRanges.contains(where: { $0.lowerBound == line }) {
                    toggleFold(atLine: line)
                    return
                }
            }
        }

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
        case 48:                        // Tab — next/previous snippet field
            if !snippetStack.isEmpty {
                if shift { _ = snippetStack.previous() } else { _ = snippetStack.next() }
                if !snippetStack.isEmpty {
                    let current = snippetStack.current()
                    caret = current.to.offset + snippetAnchor
                    anchor = nil
                    stickyColumn = nil
                    scrollCaretToVisible()
                    needsDisplay = true
                }
            } else {
                insertText("\t")
            }
        case 51:                        // Delete (backspace)
            deleteBackward()
        case 117:                       // fn + Delete
            deleteForward()
        case 33:                        // ⌘⌥[ — fold at the caret line
            if command && option { toggleFold(atLine: buffer.lineIndex(atUtf8Offset: caret)) }
        case 30:                        // ⌘⌥] — unfold
            if command && option { unfold(atLine: buffer.lineIndex(atUtf8Offset: caret)) }
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
        case 3:                         // ⌘F — show the find bar
            if command { onShowFindBar?() }
        case 5:                         // ⌘G / ⇧⌘G — next / previous match
            if command { shift ? findPrevious() : findNext() }
        case 53:                        // Escape — drop the snippet stack
            if !snippetStack.isEmpty {
                snippetStack.clear()
                needsDisplay = true
            }
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

    // MARK: - Snippets (4.S5)

    private var snippetStack = Snippet.Stack()
    /// Buffer offset where the active snippet text starts (the C++ `anchor`).
    private var snippetAnchor = 0

    /// Routes an edit through the snippet stack (mirror updates, field
    /// dropping) and returns the new caret position.
    private func snippetReplace(range: Range<Int>, with text: String) -> Int {
        let local = TextFormatString.Range(range.lowerBound - snippetAnchor, range.upperBound - snippetAnchor)
        let pairs = snippetStack.replace(range: local, replacement: text)
        var adjustment = 0
        var caret = range.lowerBound
        for (pairRange, pairStr) in pairs {
            let from = pairRange.from.offset + snippetAnchor + adjustment
            let to = pairRange.to.offset + snippetAnchor + adjustment
            let clampedFrom = max(0, min(buffer.utf8Length, from))
            let clampedTo = max(clampedFrom, min(buffer.utf8Length, to))
            buffer.replace(clampedFrom..<clampedTo, with: pairStr)
            caret = clampedFrom + pairStr.utf8.count
            adjustment += pairStr.utf8.count - (clampedTo - clampedFrom)
        }
        if !snippetStack.isEmpty {
            let current = snippetStack.current()
            caret = current.to.offset + snippetAnchor
        }
        return caret
    }

    /// Inserts a snippet at the caret/selection (Bundles ▸ Insert Snippet…).
    @objc func insertSnippet(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Insert Snippet"
        alert.informativeText = "$1/$2 tab stops, ${1:default}, ${1/pattern/format/} mirrors, ${1|a,b|}: "
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 340, height: 24))
        alert.accessoryView = input
        alert.addButton(withTitle: "Insert")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let snippetText = input.stringValue
        guard !snippetText.isEmpty else { return }
        let insertRange = selectedRange ?? (caret..<caret)
        trackEditRange(insertRange)
        let snippet = TextFormatString.parseSnippet(snippetText)
        if snippetStack.isEmpty { snippetAnchor = insertRange.lowerBound }
        buffer.replace(insertRange, with: snippet.string)
        let field = snippet.fields[snippet.currentField]
        let fieldRange = field?.range ?? TextFormatString.Range(snippet.string.utf8.count, snippet.string.utf8.count)
        snippetStack.push(snippet, range: fieldRange)
        caret = insertRange.lowerBound + fieldRange.to.offset
        anchor = nil
        stickyColumn = nil
        didEdit()
    }

    private func insertText(_ text: String) {
        guard !text.isEmpty else { return }
        let range = selectedRange ?? (caret..<caret)
        trackEditRange(range)
        if !snippetStack.isEmpty {
            caret = snippetReplace(range: range, with: text)
        } else if let range = selectedRange {
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
        if !snippetStack.isEmpty {
            let range = selectedRange ?? (caret > 0 ? (buffer.previousCharacterBoundary(before: caret)..<caret) : nil)
            guard let range else { NSSound.beep(); return }
            trackEditRange(range)
            caret = snippetReplace(range: range, with: "")
            stickyColumn = nil
            didEdit()
            return
        }
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
        if !snippetStack.isEmpty {
            let range = selectedRange ?? (caret < buffer.utf8Length ? (caret..<buffer.nextCharacterBoundary(after: caret)) : nil)
            guard let range else { NSSound.beep(); return }
            trackEditRange(range)
            caret = snippetReplace(range: range, with: "")
            stickyColumn = nil
            didEdit()
            return
        }
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
        if !findQuery.isEmpty { updateFind(query: findQuery, caseSensitive: findCaseSensitive) }
        refreshFolds()
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
        guard let currentRow = row(ofLine: currentLine) else {
            // Caret on a hidden line — move to the fold boundary first.
            clampCaretToVisible()
            return
        }
        let targetRow = max(0, min(visibleLineCount - 1, currentRow + delta))
        let targetLine = visibleLines[targetRow]
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
