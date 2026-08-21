import AppKit
import TextCore

/// The document layer (roadmap Phase 3, 3.T1/3.S1/3.S2). An `NSDocument` whose
/// content is a `TextCore.Buffer`, with encoding detection on open and
/// re-encoding on save. NSDocument provides the multi-window/tab management
/// (3.S3), the unsaved-changes sheet on close/quit, and the File menu actions.
///
/// The engine buffer lives in the `EditorView` (the editing surface); the
/// document pushes bytes into it on read and pulls from it on save, so there is
/// a single source of truth.
final class TextDocument: NSDocument {

    /// Detected charset of the file (used to re-encode on save).
    private(set) var charset: TextTranscode.Charset = .utf8

    override func makeWindowControllers() {
        let controller = EditorWindowController()
        controller.editorView.onChange = { [weak self] in
            self?.updateChangeCount(.changeDone)
        }
        addWindowController(controller)
        controller.editorView.load(bufferForDisplay())
    }

    private var editorView: EditorView? {
        (windowControllers.first as? EditorWindowController)?.editorView
    }

    /// The buffer currently shown in the (first) window; empty if none yet.
    private func bufferForDisplay() -> Buffer {
        editorView?.buffer ?? Buffer()
    }

    override func read(from data: Data, ofType typeName: String) throws {
        let bytes = [UInt8](data)
        let detected = TextTranscode.detect(bytes)
        guard let text = TextTranscode.string(from: bytes, charset: detected) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        charset = detected
        for controller in windowControllers {
            (controller as? EditorWindowController)?.editorView.load(Buffer(text))
        }
    }

    override func data(ofType typeName: String) throws -> Data {
        guard let view = editorView else {
            throw CocoaError(.fileWriteUnknown)
        }
        guard let bytes = TextTranscode.data(from: view.buffer.content, charset: charset) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return Data(bytes)
    }
}
