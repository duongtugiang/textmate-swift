import AppKit

/// Find & replace bar (roadmap 4.S4 / issue #31). Lives above the scroll view,
/// hidden by default; the window controller wires its callbacks to the
/// `EditorView` find state. It also forwards the Edit ▸ Find menu actions
/// (`findNext:`/`findPrevious:`/`showFindBar:`) so ⌘G keeps working while the
/// search field has focus.
final class FindBar: NSView, NSSearchFieldDelegate {

    var onSearch: ((String) -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onReplace: ((String) -> Void)?
    var onReplaceAll: ((String) -> Void)?
    var onClose: (() -> Void)?
    var onCountChange: ((Int) -> Void)?

    let searchField = NSSearchField()
    private let replaceField = NSTextField()
    private let countLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func build() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        searchField.delegate = self
        searchField.sendsSearchStringImmediately = true
        searchField.placeholderString = "Find"
        searchField.translatesAutoresizingMaskIntoConstraints = false

        let previousButton = NSButton(title: "↑", target: self, action: #selector(previous(_:)))
        previousButton.bezelStyle = .texturedRounded
        previousButton.toolTip = "Previous (⇧⌘G)"
        let nextButton = NSButton(title: "↓", target: self, action: #selector(next(_:)))
        nextButton.bezelStyle = .texturedRounded
        nextButton.toolTip = "Next (⌘G)"

        replaceField.placeholderString = "Replace"
        replaceField.translatesAutoresizingMaskIntoConstraints = false

        let replaceButton = NSButton(title: "Replace", target: self, action: #selector(replace(_:)))
        replaceButton.bezelStyle = .texturedRounded
        let replaceAllButton = NSButton(title: "All", target: self, action: #selector(replaceAll(_:)))
        replaceAllButton.bezelStyle = .texturedRounded
        replaceAllButton.toolTip = "Replace All"

        countLabel.textColor = .secondaryLabelColor
        countLabel.font = .systemFont(ofSize: 11)

        closeButton.title = "✕"
        closeButton.bezelStyle = .texturedRounded
        closeButton.target = self
        closeButton.action = #selector(close(_:))

        let stack = NSStackView(views: [searchField, previousButton, nextButton, countLabel, replaceField, replaceButton, replaceAllButton, closeButton])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            searchField.widthAnchor.constraint(equalToConstant: 180),
            replaceField.widthAnchor.constraint(equalToConstant: 180),
        ])
    }

    func focusSearchField() {
        window?.makeFirstResponder(searchField)
        searchField.selectText(nil)
    }

    func updateCount(_ count: Int) {
        countLabel.stringValue = count > 0 ? "\(count)" : ""
    }

    // MARK: - NSSearchFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        onSearch?(searchField.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if control === searchField, commandSelector == #selector(NSResponder.insertNewline(_:)) {
            onNext?()
            return true
        }
        if control === searchField, commandSelector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) {
            onPrevious?()
            return true
        }
        return false
    }

    // MARK: - Actions (also reachable from the Edit ▸ Find menu)

    @objc func next(_ sender: Any?) { onNext?() }
    @objc func previous(_ sender: Any?) { onPrevious?() }
    @objc func replace(_ sender: Any?) { onReplace?(replaceField.stringValue) }
    @objc func replaceAll(_ sender: Any?) { onReplaceAll?(replaceField.stringValue) }
    @objc func close(_ sender: Any?) { onClose?() }

    @objc func findNext(_ sender: Any?) { onNext?() }
    @objc func findPrevious(_ sender: Any?) { onPrevious?() }
    @objc func showFindBar(_ sender: Any?) { focusSearchField() }
}
