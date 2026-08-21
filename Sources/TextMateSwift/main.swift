import AppKit
import TextCore
import UniformTypeIdentifiers

/// First buildable macOS app: a bare editor window with New / Open / Save /
/// Save As, full text editing (undo, redo, cut, copy, paste, select all via
/// NSTextView), and a dirty-state indicator.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var textView: NSTextView!
    private var currentURL: URL?
    /// The `TextCore` buffer is the document source of truth: files are loaded
    /// into it, edits are synced back from the view, and saves write from it.
    /// (Fine-grained edit streaming into the piece tree is Phase 2 work — for
    /// now the buffer is re-synced on each text change.)
    private var document = Buffer()
    private var dirty = false {
        didSet { updateTitle() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        buildWindow()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: - UI

    private func buildWindow() {
        let rect = NSRect(x: 0, y: 0, width: 960, height: 640)
        window = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Untitled"
        window.center()
        window.setFrameAutosaveName("TextMateSwift.MainWindow")

        let scrollView = NSScrollView(frame: rect)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        textView = NSTextView(frame: rect)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.allowsUndo = true
        textView.isRichText = false
        textView.usesFontPanel = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false

        scrollView.documentView = textView
        window.contentView = scrollView
        window.makeFirstResponder(textView)
        window.makeKeyAndOrderFront(nil)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidChange(_:)),
            name: NSText.didChangeNotification,
            object: textView
        )
    }

    private func buildMenu() {
        let mainMenu = NSMenu()

        // Application menu
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About TextMateSwift", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit TextMateSwift", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        appMenu.addItem(quit)
        appItem.submenu = appMenu

        // File menu
        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(menuItem("New", action: #selector(newDocument(_:)), key: "n"))
        fileMenu.addItem(menuItem("Open…", action: #selector(openDocument(_:)), key: "o"))
        fileMenu.addItem(.separator())
        fileMenu.addItem(menuItem("Save", action: #selector(saveDocument(_:)), key: "s"))
        fileMenu.addItem(menuItem("Save As…", action: #selector(saveDocumentAs(_:)), key: "S"))
        fileItem.submenu = fileMenu

        // Edit menu (nil target → first responder, i.e. the text view)
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    private func menuItem(_ title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: - Dirty state

    @objc private func textDidChange(_ notification: Notification) {
        // Sync the engine buffer from the editing surface so it stays the
        // source of truth for the document.
        document = Buffer(Array(textView.string.utf8))
        dirty = true
    }

    private func updateTitle() {
        let name = currentURL?.lastPathComponent ?? "Untitled"
        window.title = dirty ? "\(name) •" : name
    }

    // MARK: - File actions

    @objc func newDocument(_ sender: Any?) {
        currentURL = nil
        document = Buffer()
        textView.string = ""
        dirty = false
        window.makeFirstResponder(textView)
    }

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            self.load(url: url)
        }
    }

    private func load(url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let bytes = [UInt8](data)
            guard TextEncoding.isValidUTF8(bytes) else {
                presentError("“\(url.lastPathComponent)” is not valid UTF-8 text.")
                return
            }
            document = Buffer(bytes)
            textView.string = document.content
            currentURL = url
            dirty = false
            window.makeFirstResponder(textView)
        } catch {
            presentError("Could not open “\(url.lastPathComponent)”: \(error.localizedDescription)")
        }
    }

    @objc func saveDocument(_ sender: Any?) {
        if let url = currentURL {
            write(to: url)
        } else {
            saveDocumentAs(sender)
        }
    }

    @objc func saveDocumentAs(_ sender: Any?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = currentURL?.lastPathComponent ?? "Untitled.txt"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            self.currentURL = url
            self.write(to: url)
        }
    }

    private func write(to url: URL) {
        do {
            // Write from the engine buffer rather than the view.
            try Data(document.bytes).write(to: url, options: .atomic)
            dirty = false
        } catch {
            presentError("Could not save “\(url.lastPathComponent)”: \(error.localizedDescription)")
        }
    }

    // MARK: - Errors

    private func presentError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "TextMateSwift"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
