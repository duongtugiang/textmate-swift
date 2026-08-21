import Foundation

/// Variable expansion for bundle settings — the subset of TextMate's
/// `format_string::expand` needed by the bundles framework:
///
///   $name, ${name}                       variable lookup
///   ${name:fallback}                     value if set & non-empty, else fallback
///   ${name:+value}                       value if set & non-empty, else ""
///   ${name:?if_set:if_not_set}           if_set if set, else if_not_set
///   ${name/pattern/format/options}       regex substitution (options: g)
///   ${N} / ${N/pattern/format/options}   capture-group backreference
///   \U \u \L \l \E                       case changes inside a replacement
///
/// Unknown variables expand to the empty string (TextMate semantics).
public enum TextFormatString {

    public static func expand(_ format: String, variables: [String: String]) -> String {
        var state = State(characters: Array(format), variables: variables)
        return state.expandUntil(terminator: nil)
    }

    private struct State {
        let characters: [Character]
        let variables: [String: String]
        var index = 0
        /// Resolves `$N` / `${N…}` backreferences during replacement expansion
        /// (the caller supplies capture-group text). Returns nil when the
        /// name is not a backreference.
        var backrefHook: (String, String?) -> String? = { _, _ in nil }

        var atEnd: Bool { index >= characters.count }

        mutating func peek() -> Character? {
            index < characters.count ? characters[index] : nil
        }

        /// Expands until the given terminator character (consumed if found)
        /// or end of input.
        mutating func expandUntil(terminator: Character?) -> String {
            var result = ""
            while let c = peek() {
                if let terminator, c == terminator {
                    index += 1
                    return result
                }
                if c == "\\" {
                    result.append(expandEscape())
                    continue
                }
                if c == "$" {
                    index += 1
                    result.append(expandVariableReference())
                    continue
                }
                result.append(c)
                index += 1
            }
            return result
        }

        /// `\U`/`\u`/`\L`/`\l`/`\E` — applied to the *expanded* text that
        /// follows within the same scope. We collect the tail first, then
        /// transform it.
        mutating func expandEscape() -> String {
            guard index + 1 < characters.count else { return "\\" }
            index += 1
            let modifier = characters[index]
            index += 1
            let rest = expandUntil(terminator: nil) // \E has no effect in our subset
            switch modifier {
            case "U": return rest.uppercased()
            case "L": return rest.lowercased()
            case "u":
                guard let first = rest.first else { return rest }
                return String(first).uppercased() + rest.dropFirst()
            case "l":
                guard let first = rest.first else { return rest }
                return String(first).lowercased() + rest.dropFirst()
            case "E":
                return rest
            default:
                return "\\" + String(modifier) + rest
            }
        }

        /// After a `$` — either `${...}` or `$name`.
        mutating func expandVariableReference() -> String {
            guard peek() == "{" else {
                return expandSimpleVariable()
            }
            index += 1 // consume {
            guard let name = readName() else { return "" }

            if peek() == "}" {
                index += 1
                if let resolved = backrefHook(name, nil) { return resolved }
                return variables[name] ?? ""
            }

            if peek() == ":" {
                index += 1
                if let c = peek() {
                    if c == "+" {
                        index += 1
                        let value = expandUntil(terminator: "}")
                        guard let v = variables[name], !v.isEmpty else { return "" }
                        return expand(value, variables: variables)
                    }
                    if c == "?" {
                        index += 1
                        let ifSet = expandUntil(terminator: ":")
                        let ifNotSet: String
                        if peek() == ":" {
                            index += 1
                            ifNotSet = expandUntil(terminator: "}")
                        } else {
                            // Malformed; treat the remainder as if_not_set.
                            ifNotSet = expandUntil(terminator: nil)
                        }
                        guard let v = variables[name], !v.isEmpty else {
                            return expand(ifNotSet, variables: variables)
                        }
                        return expand(ifSet, variables: variables)
                    }
                }
                let fallback = expandUntil(terminator: "}")
                guard let v = variables[name], !v.isEmpty else {
                    return expand(fallback, variables: variables)
                }
                return v
            }

            if peek() == "/" {
                index += 1
                if Int(name) != nil {
                    // Capture-group backreference: the hook (if any) owns the
                    // substitution text; outside a replacement it is empty.
                    guard let tail = readSubstitutionTail() else { return "" }
                    return backrefHook(name, tail) ?? variables[name] ?? ""
                }
                return expandSubstitution(name: name)
            }

            return variables[name] ?? ""
        }

        /// After `${N/` — reads `pattern/format/options}` and returns the raw
        /// substitution string for the backref hook.
        mutating func readSubstitutionTail() -> String? {
            var result = ""
            var depth = 1
            while let c = peek() {
                if c == "}" { depth -= 1; if depth == 0 { index += 1; return result } }
                if c == "{" { depth += 1 }
                result.append(c)
                index += 1
            }
            return nil
        }

        mutating func expandSimpleVariable() -> String {
            var name = ""
            while let c = peek(), c.isLetter || c.isNumber || c == "_" {
                name.append(c)
                index += 1
            }
            guard !name.isEmpty else { return "$" }
            return variables[name] ?? ""
        }

        mutating func readName() -> String? {
            var name = ""
            while let c = peek(), c.isLetter || c.isNumber || c == "_" {
                name.append(c)
                index += 1
            }
            return name.isEmpty ? nil : name
        }

        /// `${name/pattern/format/options}` — substitute on the variable's
        /// value (or a capture group when `name` is a number).
        mutating func expandSubstitution(name: String) -> String {
            guard let pattern = readUntilSlash() else { return "" }
            guard let format = readUntilSlash() else { return "" }
            let options = readUntilClosingBrace() ?? ""

            var source: String
            if let digit = Int(name) {
                // Backreference to a capture group of the enclosing match —
                // handled by the caller; with no context, use the variable.
                source = variables[name] ?? ""
                _ = digit
            } else {
                source = variables[name] ?? ""
            }

            guard !source.isEmpty else { return "" }
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return "" }
            let global = options.contains("g")

            var result = ""
            var searchRange = NSRange(location: 0, length: (source as NSString).length)
            var lastLocation = 0
            while let match = regex.firstMatch(in: source, range: searchRange) {
                let ns = source as NSString
                result += ns.substring(with: NSRange(location: lastLocation, length: match.range.location - lastLocation))
                result += expandReplacement(format, match: match, in: source)
                lastLocation = match.range.location + match.range.length
                guard global, match.range.length > 0 else { break }
                searchRange = NSRange(location: lastLocation, length: (source as NSString).length - lastLocation)
            }
            result += (source as NSString).substring(from: lastLocation)
            return result
        }

        func expandReplacement(_ format: String, match: NSTextCheckingResult, in source: String) -> String {
            // Replace ${N} / ${N/…/…/} backreferences, then apply \U/\u etc.
            let ns = source as NSString
            func groupText(_ n: Int) -> String {
                guard n < match.numberOfRanges else { return "" }
                let range = match.range(at: n)
                guard range.location != NSNotFound else { return "" }
                return ns.substring(with: range)
            }
            return TextFormatString.expand(format, variables: [:]) { name, substitution in
                if let n = Int(name) {
                    let text = groupText(n)
                    if let substitution {
                        return TextFormatString.applySubstitution(text, substitution: substitution)
                    }
                    return text
                }
                return nil
            }
        }

        /// Reads up to the next `/` at brace depth 0 — `/` inside a nested
        /// `${…}` (e.g. a capture substitution) does not terminate the field.
        mutating func readUntilSlash() -> String? {
            var result = ""
            var depth = 0
            while let c = peek() {
                if c == "{" { depth += 1 }
                if c == "}" { depth -= 1; if depth < 0 { return nil } }
                if c == "/" && depth == 0 { index += 1; return result }
                // Keep escapes (\U etc.) raw — they are applied during expansion.
                result.append(c)
                index += 1
            }
            return nil
        }

        mutating func readUntilClosingBrace() -> String? {
            var result = ""
            while let c = peek() {
                if c == "}" { index += 1; return result }
                result.append(c)
                index += 1
            }
            return nil
        }
    }

    /// Core expand with an optional backreference hook (for replacement
    /// formats that reference capture groups).
    static func expand(
        _ format: String,
        variables: [String: String],
        backref: @escaping (String, String?) -> String? = { _, _ in nil }
    ) -> String {
        var state = State(characters: Array(format), variables: variables)
        state.backrefHook = backref
        return state.expandUntil(terminator: nil)
    }

    /// Applies `${N/pattern/format/options}` to a captured group's text.
    static func applySubstitution(_ text: String, substitution: String) -> String {
        guard let slash = substitution.firstIndex(of: "/") else { return text }
        let pattern = String(substitution[..<slash])
        var rest = substitution[substitution.index(after: slash)...]
        guard let slash2 = rest.firstIndex(of: "/") else { return text }
        let format = String(rest[..<slash2])
        rest = rest[rest.index(after: slash2)...]
        let options = String(rest)
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let global = options.contains("g")
        let ns = text as NSString
        var result = ""
        var searchRange = NSRange(location: 0, length: ns.length)
        var last = 0
        while let match = regex.firstMatch(in: text, range: searchRange) {
            result += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            result += expand(format, variables: [:]) { name, _ in
                guard let n = Int(name), n < match.numberOfRanges else { return nil }
                let r = match.range(at: n)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
            last = match.range.location + match.range.length
            guard global, match.range.length > 0 else { break }
            searchRange = NSRange(location: last, length: ns.length - last)
        }
        result += ns.substring(from: last)
        return result
    }
}


