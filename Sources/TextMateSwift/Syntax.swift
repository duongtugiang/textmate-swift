import AppKit
import TextCore

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
