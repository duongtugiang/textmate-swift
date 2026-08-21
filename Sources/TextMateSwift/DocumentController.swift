import AppKit

/// Programmatic document-type registration so the document layer works without
/// an Info.plist. Under `swift run` the executable has no bundle, so
/// `NSDocumentController` can't discover `CFBundleDocumentTypes`/`NSDocumentClass`
/// and every document creation fails with "No document could be created". The
/// Xcode `.app` keeps its Info.plist registration (which also requires the
/// module-qualified class name); this controller is equivalent and takes
/// precedence, so both build paths behave identically.
final class DocumentController: NSDocumentController {
    /// Mirrors the `LSItemContentTypes` in project.yml.
    static let supportedTypes = [
        "public.plain-text",
        "public.text",
        "public.utf8-plain-text",
        "public.utf16-plain-text",
        "com.apple.traditional-mac-plain-text",
    ]

    override func documentClass(forType type: String) -> AnyClass? {
        TextDocument.self
    }

    override func makeUntitledDocument(ofType typeName: String) throws -> NSDocument {
        try TextDocument(type: typeName)
    }

    override func makeDocument(withContentsOf url: URL, ofType typeName: String) throws -> NSDocument {
        try TextDocument(contentsOf: url, ofType: typeName)
    }
}
