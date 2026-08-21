import AppKit
import TextCore

/// Window controller for a document: a scroll view hosting the engine-backed
/// `EditorView` (roadmap 2.S1), with a hidden find & replace bar (4.S4) above
/// it. NSDocument manages the window's title and the edited-state indicator.
final class EditorWindowController: NSWindowController {

    let editorView: EditorView
    private let findBar = FindBar()

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

        // Find bar (hidden) above the scroll view.
        findBar.isHidden = true
        findBar.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: rect)
        container.addSubview(findBar)
        container.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            findBar.topAnchor.constraint(equalTo: container.topAnchor),
            findBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            findBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: findBar.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        let window = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.tabbingMode = .preferred
        window.center()
        window.setFrameAutosaveName("TextMateSwift.Document")
        window.contentView = container

        self.editorView = editorView
        super.init(window: window)
        window.initialFirstResponder = editorView

        // Wire find: bar ↔ editor ↔ responder chain.
        findBar.onSearch = { [weak self] query in
            self?.editorView.updateFind(query: query)
        }
        findBar.onNext = { [weak self] in
            _ = self?.editorView.findNext()
        }
        findBar.onPrevious = { [weak self] in
            _ = self?.editorView.findPrevious()
        }
        findBar.onReplace = { [weak self] text in
            _ = self?.editorView.replaceCurrentFindMatch(with: text)
        }
        findBar.onReplaceAll = { [weak self] text in
            _ = self?.editorView.replaceAllFindMatches(with: text)
        }
        findBar.onClose = { [weak self] in
            self?.setFindBarVisible(false)
        }
        editorView.onShowFindBar = { [weak self] in
            self?.setFindBarVisible(true)
        }
        editorView.onFindStateChange = { [weak self] in
            self?.findBar.updateCount(self?.editorView.findMatchCount ?? 0)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func setFindBarVisible(_ visible: Bool) {
        guard findBar.isHidden == visible else { return }
        findBar.isHidden = !visible
        if visible {
            findBar.focusSearchField()
        } else {
            window?.makeFirstResponder(editorView)
            editorView.needsDisplay = true
        }
    }
}
