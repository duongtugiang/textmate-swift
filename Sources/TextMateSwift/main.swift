import AppKit
import TextCore

/// TextMateSwift — a document-based AppKit editor (roadmap Phase 3). The app
/// delegate only builds the menu bar and app lifecycle; documents, windows,
/// tabs, encoding-aware open/save, and the unsaved-changes sheets come from
/// `TextDocument` (NSDocument) + the engine-backed `EditorView`.
final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = true
        buildMenu()
        // Start with an untitled document, like a bare editor should.
        NSDocumentController.shared.newDocument(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    // MARK: - Menus

    private func buildMenu() {
        let mainMenu = NSMenu()

        // Application menu
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About TextMateSwift", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        servicesItem.submenu = NSMenu()
        appMenu.addItem(servicesItem)
        appMenu.addItem(.separator())
        let hide = NSMenuItem(title: "Hide TextMateSwift", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        hide.target = NSApp
        appMenu.addItem(hide)
        let hideOthers = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        hideOthers.target = NSApp
        appMenu.addItem(hideOthers)
        appMenu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit TextMateSwift", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        appMenu.addItem(quit)
        appItem.submenu = appMenu

        // File menu — nil targets resolve through the responder chain to the
        // document controller / document / window.
        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(NSMenuItem(title: "New", action: #selector(NSDocumentController.newDocument(_:)), keyEquivalent: "n"))
        fileMenu.addItem(NSMenuItem(title: "Open…", action: #selector(NSDocumentController.openDocument(_:)), keyEquivalent: "o"))
        fileMenu.addItem(.separator())
        fileMenu.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        fileMenu.addItem(.separator())
        fileMenu.addItem(NSMenuItem(title: "Save", action: #selector(NSDocument.save(_:)), keyEquivalent: "s"))
        fileMenu.addItem(NSMenuItem(title: "Save As…", action: #selector(NSDocument.saveAs(_:)), keyEquivalent: "S"))
        fileItem.submenu = fileMenu

        // Edit menu — nil targets → first responder (the EditorView)
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
        editMenu.addItem(.separator())
        // Find & replace (4.S4) — actions resolve through the responder chain
        // to the first responder (EditorView or the FindBar's fields).
        editMenu.addItem(NSMenuItem(title: "Find…", action: Selector(("showFindBar:")), keyEquivalent: "f"))
        editMenu.addItem(NSMenuItem(title: "Find Next", action: Selector(("findNext:")), keyEquivalent: "g"))
        editMenu.addItem(NSMenuItem(title: "Find Previous", action: Selector(("findPrevious:")), keyEquivalent: "G"))
        editItem.submenu = editMenu

        // Bundles menu — load .tmLanguage grammars / .tmBundle directories
        // (4.S6); the action resolves to the first responder (EditorView).
        let bundlesItem = NSMenuItem()
        mainMenu.addItem(bundlesItem)
        let bundlesMenu = NSMenu(title: "Bundles")
        bundlesMenu.addItem(NSMenuItem(title: "Load Grammar…", action: Selector(("loadGrammar:")), keyEquivalent: ""))
        bundlesMenu.addItem(NSMenuItem(title: "Insert Snippet…", action: Selector(("insertSnippet:")), keyEquivalent: ""))
        bundlesItem.submenu = bundlesMenu

        // Window menu — the window list (with ⌘` cycling) is added automatically
        // when the menu is registered as NSApp.windowsMenu.
        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        let minimize = NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(minimize)
        let zoom = NSMenuItem(title: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(zoom)
        let mergeAll = NSMenuItem(title: "Merge All Windows", action: #selector(NSWindow.mergeAllWindows(_:)), keyEquivalent: "")
        windowMenu.addItem(mergeAll)
        windowMenu.addItem(.separator())
        let bringAll = NSMenuItem(title: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        windowMenu.addItem(bringAll)
        windowItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
// A document controller created before the app runs becomes the shared one.
// This registers TextDocument without an Info.plist (the `swift run` path);
// the Xcode app's plist registration is equivalent.
_ = DocumentController()
app.run()
