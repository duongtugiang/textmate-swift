import AppKit
import TextCore
import UniformTypeIdentifiers

/// TextMateSwift — a bare editor whose document surface is the engine-backed
/// `EditorView` (roadmap 2.S1): the `TextCore.Buffer` is the single source of
/// truth, rendering and undo/redo both come from the piece tree, and files are
/// loaded/saved through the engine's bytes. No NSTextView in the pipeline.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var editorView: EditorView!
    private var currentURL: URL?
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

        editorView = EditorView(frame: rect)
        editorView.autoresizingMask = [.width]
        editorView.onChange = { [weak self] in self?.dirty = true }
        scrollView.documentView = editorView

        window.contentView = scrollView
        window.makeFirstResponder(editorView)
        window.makeKeyAndOrderFront(nil)
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

        // Edit menu (nil target → first responder, i.e. the EditorView)
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

    // MARK: - Title / dirty state

    private func updateTitle() {
        let name = currentURL?.lastPathComponent ?? "Untitled"
        window.title = dirty ? "\\(name) •" : name
    }

    // MARK: - File actions

    @objc func newDocument(_ sender: Any?) {
        currentURL = nil
        editorView.load(Buffer())
        dirty = false
        window.makeFirstResponder(editorView)
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
                presentError("“\\(url.lastPathComponent)” is not valid UTF-8 text.")
                return
            }
            editorView.load(Buffer(bytes))
            currentURL = url
            dirty = false
            window.makeFirstResponder(editorView)
        } catch {
            presentError("Could not open “\\(url.lastPathComponent)”: \\(error.localizedDescription)")
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
            // Write from the engine buffer — the piece tree is the document.
            try Data(editorView.buffer.bytes).write(to: url, options: .atomic)
            dirty = false
        } catch {
            presentError("Could not save “\\(url.lastPathComponent)”: \\(error.localizedDescription)")
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
