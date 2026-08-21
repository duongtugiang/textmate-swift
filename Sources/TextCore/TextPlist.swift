import Foundation

/// Parser for the old-style (NeXTSTEP) ASCII plist format used by `.tmBundle`
/// and `.tmLanguage` files: `{ key = value; }`, `( item, item )`, `'string'`,
/// `"string"`, bare words, integers, and booleans (`1`/`0`). Modern plist
/// content (XML/binary) goes through `PropertyListSerialization` instead;
/// this parser exists because TextMate's own bundle index (and its test
/// fixtures) speak this format.
public enum TextPlist {

    /// Parses a complete plist document into a dictionary. Returns nil on
    /// syntax errors.
    public static func parse(_ text: String) -> [String: Any]? {
        var parser = Parser(text)
        guard let value = parser.parseValue() else { return nil }
        parser.skipWhitespace()
        guard parser.atEnd else { return nil }
        guard case .dict(let dict) = value else { return nil }
        return dict
    }

    enum Value {
        case dict([String: Any])
        case array([Any])
        case string(String)
        case int(Int)
        case bool(Bool)
    }

    private struct Parser {
        let characters: [Character]
        var index = 0

        init(_ text: String) {
            characters = Array(text)
        }

        var atEnd: Bool { index >= characters.count }

        mutating func peek() -> Character? {
            index < characters.count ? characters[index] : nil
        }

        mutating func advance() -> Character? {
            guard index < characters.count else { return nil }
            defer { index += 1 }
            return characters[index]
        }

        mutating func skipWhitespace() {
            while let c = peek(), c.isWhitespace {
                index += 1
            }
        }

        mutating func parseValue() -> Value? {
            skipWhitespace()
            guard let c = peek() else { return nil }
            switch c {
            case "{": return parseDict()
            case "(": return parseArray()
            case "'": return parseQuoted("\'")
            case "\"": return parseQuoted("\"")
            default:
                if c.isNumber || c == "-" {
                    return parseNumber()
                }
                return parseBare()
            }
        }

        mutating func parseDict() -> Value? {
            guard advance() == "{" else { return nil }
            var result: [String: Any] = [:]
            while true {
                skipWhitespace()
                guard let c = peek() else { return nil }
                if c == "}" {
                    _ = advance()
                    return .dict(result)
                }
                guard let key = parseKey() else { return nil }
                skipWhitespace()
                guard advance() == "=" else { return nil }
                guard let value = parseValue() else { return nil }
                result[key] = value.anyValue
                skipWhitespace()
                guard advance() == ";" else { return nil }
            }
        }

        mutating func parseArray() -> Value? {
            guard advance() == "(" else { return nil }
            var result: [Any] = []
            while true {
                skipWhitespace()
                guard let c = peek() else { return nil }
                if c == ")" {
                    _ = advance()
                    return .array(result)
                }
                guard let value = parseValue() else { return nil }
                result.append(value.anyValue)
                skipWhitespace()
                guard let c = peek() else { return nil }
                if c == ")" {
                    _ = advance()
                    return .array(result)
                }
                guard c == "," else { return nil }
                _ = advance()
            }
        }

        /// Keys are bare words (may contain `.`, `-`, `$`, digits…).
        mutating func parseKey() -> String? {
            var key = ""
            while let c = peek(), !c.isWhitespace, c != "=", c != ";" {
                key.append(c)
                index += 1
            }
            return key.isEmpty ? nil : key
        }

        mutating func parseQuoted(_ quote: Character) -> Value? {
            guard advance() == quote else { return nil }
            var result = ""
            while let c = advance() {
                if c == quote { return .string(result) }
                // Single-quoted strings are literal in old-style plists
                // (grammar patterns keep their backslashes); only double
                // quotes process escapes.
                if c == "\\", quote == "\"" {
                    guard let escaped = advance() else { return nil }
                    switch escaped {
                    case "n": result.append("\n")
                    case "t": result.append("\t")
                    case "\\": result.append("\\")
                    case "\"": result.append("\"")
                    default: result.append(escaped)
                    }
                } else {
                    result.append(c)
                }
            }
            return nil
        }

        mutating func parseNumber() -> Value? {
            var text = ""
            while let c = peek(), c.isNumber || c == "-" {
                text.append(c)
                index += 1
            }
            guard let value = Int(text) else { return nil }
            return .int(value)
        }

        /// Unquoted strings (booleans are the bare words `1`/`0`).
        mutating func parseBare() -> Value? {
            var text = ""
            while let c = peek(), !c.isWhitespace, c != ";", c != ",", c != ")", c != "}" {
                text.append(c)
                index += 1
            }
            if text == "1" { return .bool(true) }
            if text == "0" { return .bool(false) }
            guard !text.isEmpty else { return nil }
            return .string(text)
        }
    }
}

extension TextPlist.Value {
    var anyValue: Any {
        switch self {
        case .dict(let d): return d
        case .array(let a): return a
        case .string(let s): return s
        case .int(let i): return i
        case .bool(let b): return b
        }
    }
}
