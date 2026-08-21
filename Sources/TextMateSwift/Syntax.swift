import AppKit
import TextCore

/// Loads `.tmLanguage` grammars and `.tmBundle` bundles from disk (4.S6).
/// Accepts both the old-style ASCII plist format (`.tmBundle` tradition) and
/// XML/binary plists — the same dict is fed to `Grammar(plist:)` that the
/// built-in grammar uses.
enum GrammarLoader {

    /// Grammar for a `.tmLanguage` file.
    static func grammar(from url: URL) -> Grammar? {
        guard let dict = plist(from: url) else { return nil }
        return Grammar(plist: dict)
    }

    /// First grammar found in a `.tmBundle` directory (`Syntaxes/*.tmLanguage`).
    static func grammar(fromBundle url: URL) -> Grammar? {
        let syntaxes = url.appendingPathComponent("Syntaxes")
        let files = (try? FileManager.default.contentsOfDirectory(
            at: syntaxes,
            includingPropertiesForKeys: nil
        )) ?? []
        for file in files where file.pathExtension == "tmLanguage" {
            if let grammar = grammar(from: file) {
                return grammar
            }
        }
        return nil
    }

    /// First grammar for a URL that may be a file or a bundle directory.
    static func grammar(fromAny url: URL) -> Grammar? {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return grammar(fromBundle: url)
        }
        return grammar(from: url)
    }

    private static func plist(from url: URL) -> [String: Any]? {
        // Old-style ASCII plist first (the classic .tmLanguage format)…
        if let text = try? String(contentsOf: url, encoding: .utf8),
           let dict = TextPlist.parse(text) {
            return dict
        }
        // …then XML/binary plist.
        if let data = try? Data(contentsOf: url),
           let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
           let dict = object as? [String: Any] {
            return dict
        }
        return nil
    }
}

/// Scope → color theme (4.S2). Mirrors the classic TextMate scope hierarchy:
/// innermost scope element wins, matched by prefix. `SyntaxParser` and the
/// built-in grammar live in TextCore (engine-side); this mapping is
/// presentation-only.
enum SyntaxTheme {

    private static let commentColor = NSColor(calibratedRed: 0.42, green: 0.48, blue: 0.52, alpha: 1)
    private static let stringColor = NSColor(calibratedRed: 0.80, green: 0.32, blue: 0.26, alpha: 1)
    private static let numberColor = NSColor(calibratedRed: 0.16, green: 0.44, blue: 0.72, alpha: 1)
    private static let keywordColor = NSColor(calibratedRed: 0.56, green: 0.27, blue: 0.68, alpha: 1)
    private static let supportColor = NSColor(calibratedRed: 0.18, green: 0.52, blue: 0.52, alpha: 1)
    private static let entityColor = NSColor(calibratedRed: 0.30, green: 0.44, blue: 0.72, alpha: 1)
    private static let variableColor = NSColor(calibratedRed: 0.20, green: 0.42, blue: 0.20, alpha: 1)

    /// Color for a scope chain, innermost-first.
    static func color(for scope: Scope) -> NSColor {
        for element in scope.elements.reversed() {
            if element.hasPrefix("comment") { return commentColor }
            if element.hasPrefix("string") { return stringColor }
            if element.hasPrefix("constant") { return numberColor }
            if element.hasPrefix("keyword") || element.hasPrefix("storage") { return keywordColor }
            if element.hasPrefix("support") { return supportColor }
            if element.hasPrefix("entity") || element.hasPrefix("meta.function") { return entityColor }
            if element.hasPrefix("variable") { return variableColor }
        }
        return NSColor.textColor
    }
}
