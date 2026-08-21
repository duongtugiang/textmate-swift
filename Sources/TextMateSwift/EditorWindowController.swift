import AppKit
import TextCore

/// Window controller for a document: a scroll view hosting the engine-backed
/// `EditorView` (roadmap 2.S1). NSDocument manages the window's title and the
/// edited-state indicator.
final class EditorWindowController: NSWindowController {

    let editorView: EditorView

    init() {
        let rect = NSRect(x: 0, y: 0, width: 960, height: 640)

        let scrollView = NSScrollView(frame: rect)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let editorView = EditorView(frame: rect)
        editorView.autoresizingMask = [.width]
        scrollView.documentView = editorView

        let window = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.tabbingMode = .preferred
        window.center()
        window.setFrameAutosaveName("TextMateSwift.Document")
        window.contentView = scrollView

        self.editorView = editorView
        super.init(window: window)
        window.initialFirstResponder = editorView
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}
