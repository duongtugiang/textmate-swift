import Foundation

/// TextMate's `format_string` engine, ported node-for-node from the C++:
///
///   $name, ${name}                       variable lookup
///   ${name:fallback}                     value if set, else fallback
///   ${name:+value}                       value if set & non-empty, else ""
///   ${name:?if_set:if_not_set}           conditionals
///   ${name/pattern/format/options}       regex substitution (options: g i e m s)
///   ${name:/upcase|downcase|capitalize|asciify|urlencode|shellescape|dirname|basename|...}
///   $N / ${N/…/…/}                       capture-group backreference (in replace)
///   (?N:if_set:if_not_set)               legacy conditions
///   \U \u \L \l \E                       deferred case changes (affect following text)
///   \t \r \n \x{HHHH} \xHH               control codes / raw bytes / unicode
///   \$ \( \\                              escapes
///
/// Expansion is byte-based (UTF-8) exactly like the C++ `std::string`, so
/// snippet field offsets match the C++ semantics. Regex matching uses
/// NSRegularExpression (ICU) but iterates the *full* range so that `^` stays
/// anchored to the buffer start — mirroring Oniguruma's search(ptrn, first,
/// last, it) rather than ICU's region-anchored `^`.
public enum TextFormatString {

    // MARK: - Options & node model

    public struct RegexpOptions: OptionSet, Sendable {
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }
        public static let g: Self = Self(rawValue: 1 << 0)   // repeat over all matches
        public static let i: Self = Self(rawValue: 1 << 1)   // ignore case
        public static let e: Self = Self(rawValue: 1 << 2)   // extended (free-spacing)
        public static let m: Self = Self(rawValue: 1 << 3)   // ^/$ match at line boundaries
        public static let s: Self = Self(rawValue: 1 << 4)   // . matches line separators
    }

    public enum CaseChange: Int, Sendable { case none = 0, upperNext, lowerNext, upper, lower }

    public struct TransformChange: OptionSet, Sendable {
        public let rawValue: UInt16
        public init(rawValue: UInt16) { self.rawValue = rawValue }
        public static let upcase: Self = Self(rawValue: 1 << 0)
        public static let downcase: Self = Self(rawValue: 1 << 1)
        public static let capitalize: Self = Self(rawValue: 1 << 2)
        public static let asciify: Self = Self(rawValue: 1 << 3)
        public static let urlEncode: Self = Self(rawValue: 1 << 4)
        public static let shellEscape: Self = Self(rawValue: 1 << 5)
        public static let relative: Self = Self(rawValue: 1 << 6)
        public static let number: Self = Self(rawValue: 1 << 7)
        public static let duration: Self = Self(rawValue: 1 << 8)
        public static let dirname: Self = Self(rawValue: 1 << 9)
        public static let basename: Self = Self(rawValue: 1 << 10)
    }

    indirect enum Node {
        case text(String)
        case rawByte(UInt8)          // \xHH — emits one raw UTF-8 byte
        case variable(String)
        case variableTransform(name: String, pattern: [Node], format: [Node], options: RegexpOptions)
        case variableFallback(name: String, fallback: [Node])
        case variableCondition(name: String, ifSet: [Node], ifNotSet: [Node])
        case variableChange(name: String, change: TransformChange)
        case caseChange(CaseChange)
        // Snippet nodes
        case placeholder(index: Int, content: [Node])
        case placeholderTransform(index: Int, pattern: String, format: [Node], options: RegexpOptions)
        case placeholderChoice(index: Int, choices: [[Node]])
        case code(String)
    }

    // MARK: - Snippet field model (byte offsets, like C++)

    public struct Pos: Comparable, Sendable {
        public var offset: Int   // byte offset
        public var rank: Int
        public init(offset: Int = 0, rank: Int = 0) { self.offset = offset; self.rank = rank }
        public static func < (l: Pos, r: Pos) -> Bool { l.offset < r.offset || (l.offset == r.offset && l.rank < r.rank) }
        public static func == (l: Pos, r: Pos) -> Bool { l.offset == r.offset && l.rank == r.rank }
        public static func + (p: Pos, d: Int) -> Pos { Pos(offset: p.offset + d, rank: p.rank) }
        public static func - (p: Pos, d: Int) -> Pos { Pos(offset: p.offset - d, rank: p.rank) }
    }

    public struct Range: Comparable, Sendable {
        public var from: Pos
        public var to: Pos
        public init(_ from: Pos, _ to: Pos) { self.from = from; self.to = to }
        public init(_ from: Int, _ to: Int) { self.from = Pos(offset: from); self.to = Pos(offset: to) }
        public func contains(_ pos: Pos) -> Bool { from < pos && pos < to }
        public func contains(_ other: Range) -> Bool { from < other.from && other.to < to }
        public var size: Int { to.offset - from.offset }
        public func toS(_ bytes: [UInt8]) -> String { String(decoding: bytes[from.offset..<to.offset], as: UTF8.self) }
        public static func < (l: Range, r: Range) -> Bool { l.from < r.from || (l.from == r.from && l.to < r.to) }
        public static func == (l: Range, r: Range) -> Bool { l.from == r.from && l.to == r.to }
        public static func + (r: Range, d: Int) -> Range { Range(r.from + d, r.to + d) }
        public static func - (r: Range, d: Int) -> Range { Range(r.from - d, r.to - d) }
    }

    public final class SnippetField {
        public var index: Int
        public var range: Range
        public var pattern: String?          // transform mirror
        var format: [Node]?
        public var options: RegexpOptions?
        public var choices: [String]?
        public init(index: Int, range: Range) { self.index = index; self.range = range }
        public var isTransform: Bool { pattern != nil }
        public func transform(_ src: String, variables: [String: String]) -> String {
            guard let pattern, let format else { return src }
            let expander = Expander(getVariable: { variables[$0] }, codeCallback: nil)
            expander.replace(src: src, pattern: pattern, options: options ?? [], format: format, repeatFlag: options?.contains(.g) ?? false)
            return expander.string
        }
        public func choiceList() -> [String] { choices ?? [] }
    }

    // MARK: - Parser

    final class Parser {
        let chars: [Character]
        var i = 0
        init(_ str: String) { chars = Array(str) }
        var atEnd: Bool { i >= chars.count }
        func peek() -> Character? { i < chars.count ? chars[i] : nil }

        @discardableResult
        func parseChar(_ set: String) -> Bool {
            guard let c = peek(), set.contains(c) else { return false }
            i += 1
            return true
        }

        func parseChars(_ allowed: String) -> String? {
            var res = ""
            while let c = peek(), allowed.contains(c) { res.append(c); i += 1 }
            return res.isEmpty ? nil : res
        }

        func parseInt() -> Int? {
            guard let c = peek(), c.isNumber else { return nil }
            var n = 0
            while let c = peek(), c.isNumber { n = n * 10 + Int(c.wholeNumberValue ?? 0); i += 1 }
            return n
        }

        /// `parse_until` from parser_base.cc: reads to a stop char, honoring
        /// `\`-escapes of `\` and stop chars, and consumes the stop char.
        /// Returns nil (and backtracks) when the stop char is never reached.
        func parseUntil(_ stop: String) -> String? {
            let backtrack = i
            var res = ""
            while let c = peek(), !stop.contains(c) {
                if c == "\\", i + 1 < chars.count, chars[i + 1] == "\\" || stop.contains(chars[i + 1]) {
                    i += 1
                }
                res.append(chars[i])
                i += 1
            }
            guard let c = peek(), stop.contains(c) else { i = backtrack; return nil }
            i += 1
            return res
        }

        func parseRegexpOptions() -> RegexpOptions {
            var opts: RegexpOptions = []
            while let c = peek(), "giems".contains(c) {
                switch c {
                case "g": opts.insert(.g)
                case "i": opts.insert(.i)
                case "e": opts.insert(.e)
                case "m": opts.insert(.m)
                case "s": opts.insert(.s)
                default: break
                }
                i += 1
            }
            return opts
        }

        /// format-string content parser (the `parse_content` member function pointer)
        func parseFormatString(stop: String) -> [Node]? {
            let backtrack = i
            var nodes: [Node] = []
            let esc = "\\$(" + stop
            while let c = peek(), !stop.contains(c) {
                if parseVariable(parseContent: { $0.parseFormatString(stop: $1) }, into: &nodes) { continue }
                if parseCondition(into: &nodes) { continue }
                if parseControlCode(into: &nodes) { continue }
                if parseCaseChange(into: &nodes) { continue }
                if parseEscape(esc, into: &nodes) { continue }
                _ = parseText(into: &nodes)
                continue
            }
            if atEnd && stop.isEmpty { return nodes }
            if parseChar(stop) { return nodes }
            i = backtrack
            return nil
        }

        /// snippet content parser (placeholder + variable + code + escape + text)
        func parseSnippet(stop: String) -> [Node]? {
            let backtrack = i
            var nodes: [Node] = []
            let esc = "\\$`" + stop
            while let c = peek(), !stop.contains(c) {
                if parsePlaceholder(into: &nodes) { continue }
                if parseVariable(parseContent: { $0.parseSnippet(stop: $1) }, into: &nodes) { continue }
                if parseCode(into: &nodes) { continue }
                if parseEscape(esc, into: &nodes) { continue }
                _ = parseText(into: &nodes)
                continue
            }
            if atEnd && stop.isEmpty { return nodes }
            if parseChar(stop) { return nodes }
            i = backtrack
            return nil
        }

        // $name | $N
        func parseVariableSimple(into nodes: inout [Node]) -> Bool {
            let backtrack = i
            guard parseChar("$") else { return false }
            if let n = parseInt() { nodes.append(.variable(String(n))); return true }
            if let name = parseChars("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_abcdefghijklmnopqrstuvwxyz") {
                nodes.append(.variable(name))
                return true
            }
            i = backtrack
            return false
        }

        func parseVariable(parseContent: (Parser, String) -> [Node]?, into nodes: inout [Node]) -> Bool {
            return parseVariableSimple(into: &nodes) || parseVariableComplex(parseContent: parseContent, into: &nodes)
        }

        func parseVariableComplex(parseContent: (Parser, String) -> [Node]?, into nodes: inout [Node]) -> Bool {
            let backtrack = i
            guard parseChar("$"), parseChar("{") else { return false }
            guard let name = parseUntil("/:}") else { i = backtrack; return false }
            // parseUntil consumed the stop char — C++ checks it[-1].
            let last = i > 0 ? chars[i - 1] : "}"

            if last == "}" {
                nodes.append(.variable(name))
                return true
            }
            if last == "/" {
                // ${name/pattern/format/options} — pattern is escaped text + nested
                // complex variables; the format is a format string.
                var pattern: [Node] = []
                while let c = peek(), c != "/" {
                    if parseEscape("\\/", into: &pattern) { continue }
                    if parseVariableComplex(parseContent: { $0.parseFormatString(stop: $1) }, into: &pattern) { continue }
                    _ = parseText(into: &pattern)
                    continue
                }
                if parseChar("/"), let format = parseFormatString(stop: "/") {
                    let opts = parseRegexpOptions()
                    if parseChar("}") {
                        nodes.append(.variableTransform(name: name, pattern: pattern, format: format, options: opts))
                        return true
                    }
                }
                i = backtrack
                return false
            }
            // last == ":"
            if parseChar("+") {
                if let ifSet = parseContent(self, "}") {
                    nodes.append(.variableCondition(name: name, ifSet: ifSet, ifNotSet: []))
                    return true
                }
                i = backtrack
                return false
            }
            if parseChar("?") {
                if let ifSet = parseContent(self, ":"), let ifNotSet = parseContent(self, "}") {
                    nodes.append(.variableCondition(name: name, ifSet: ifSet, ifNotSet: ifNotSet))
                    return true
                }
                i = backtrack
                return false
            }
            if parseChar("/") {
                // ${name:/upcase/downcase/...} — the just-consumed char is "/"
                // (C++ loops on it[-1] == '/').
                var change: TransformChange = []
                var lastStop: Character = "/"
                while lastStop == "/" {
                    guard let option = parseUntil("/}") else { i = backtrack; return false }
                    lastStop = i > 0 ? chars[i - 1] : "}"
                    switch option {
                    case "upcase": change.insert(.upcase)
                    case "downcase": change.insert(.downcase)
                    case "titlecase", "capitalize": change.insert(.capitalize)
                    case "asciify": change.insert(.asciify)
                    case "urlencode": change.insert(.urlEncode)
                    case "shellescape": change.insert(.shellEscape)
                    case "relative": change.insert(.relative)
                    case "number": change.insert(.number)
                    case "duration": change.insert(.duration)
                    case "dirname": change.insert(.dirname)
                    case "basename": change.insert(.basename)
                    default: break
                    }
                }
                nodes.append(.variableChange(name: name, change: change))
                return true
            }
            // ${name:fallback}
            if let fallback = parseContent(self, "}") {
                nodes.append(.variableFallback(name: name, fallback: fallback))
                return true
            }
            i = backtrack
            return false
        }

        // (?N:if_set:if_not_set)
        func parseCondition(into nodes: inout [Node]) -> Bool {
            let backtrack = i
            guard parseChar("("), parseChar("?"), let n = parseInt(), parseChar(":") else { i = backtrack; return false }
            guard let ifSet = parseFormatString(stop: ":)") else { i = backtrack; return false }
            // parseFormatString consumed the stop char — check it[-1].
            let last = i > 0 ? chars[i - 1] : ")"
            if last == ")" {
                nodes.append(.variableCondition(name: String(n), ifSet: ifSet, ifNotSet: []))
                return true
            }
            if last == ":" {
                guard let ifNotSet = parseFormatString(stop: ")") else { i = backtrack; return false }
                nodes.append(.variableCondition(name: String(n), ifSet: ifSet, ifNotSet: ifNotSet))
                return true
            }
            i = backtrack
            return false
        }

        func parseCaseChange(into nodes: inout [Node]) -> Bool {
            let backtrack = i
            guard parseChar("\\"), parseChar("ULEul") else { i = backtrack; return false }
            switch chars[i - 1] {
            case "U": nodes.append(.caseChange(.upper))
            case "L": nodes.append(.caseChange(.lower))
            case "E": nodes.append(.caseChange(.none))
            case "u": nodes.append(.caseChange(.upperNext))
            case "l": nodes.append(.caseChange(.lowerNext))
            default: break
            }
            return true
        }

        func parseControlCode(into nodes: inout [Node]) -> Bool {
            let backtrack = i
            guard parseChar("\\"), parseChar("trnx") else { i = backtrack; return false }
            switch chars[i - 1] {
            case "t": nodes.append(.text("\t")); return true
            case "r": nodes.append(.text("\r")); return true
            case "n": nodes.append(.text("\n")); return true
            case "x":
                if parseChar("{") {
                    var value = ""
                    while let c = peek(), c != "}" { value.append(c); i += 1 }
                    if peek() == "}", value.count <= 8, !value.isEmpty, value.allSatisfy({ $0.isHexDigit }), let scalar = UInt32(value, radix: 16), let unicode = UnicodeScalar(scalar) {
                        i += 1
                        nodes.append(.text(String(unicode)))
                        return true
                    }
                    i = backtrack
                    return false
                }
                if i + 1 < chars.count, chars[i].isHexDigit, chars[i + 1].isHexDigit {
                    let byte = UInt8(String(chars[i]), radix: 16)! << 4 | UInt8(String(chars[i + 1]), radix: 16)!
                    nodes.append(.rawByte(byte))
                    i += 2
                    return true
                }
                i = backtrack
                return false
            default:
                i = backtrack
                return false
            }
        }

        func parseEscape(_ escapeChars: String, into nodes: inout [Node]) -> Bool {
            let backtrack = i
            guard parseChar("\\"), parseChar(escapeChars) else { i = backtrack; return false }
            nodes.append(.text(String(chars[i - 1])))
            return true
        }

        func parseText(into nodes: inout [Node]) -> Bool {
            guard let c = peek() else { return false }
            if let last = nodes.last, case .text(let s) = last {
                nodes[nodes.count - 1] = .text(s + String(c))
            } else {
                nodes.append(.text(String(c)))
            }
            i += 1
            return true
        }

        // $N, ${N}, ${N:content}, ${N/pattern/format/options}, ${N|a,b,c|}
        func parsePlaceholder(into nodes: inout [Node]) -> Bool {
            let backtrack = i
            guard parseChar("$") else { return false }
            if parseChar("{") {
                guard let n = parseInt() else { i = backtrack; return false }
                if parseChar(":") {
                    if let content = parseSnippet(stop: "}") {
                        nodes.append(.placeholder(index: n, content: content))
                        return true
                    }
                    i = backtrack
                    return false
                }
                if parseChar("/") {
                    guard let pattern = parseUntil("/"), let format = parseFormatString(stop: "/") else { i = backtrack; return false }
                    let opts = parseRegexpOptions()
                    guard parseChar("}") else { i = backtrack; return false }
                    nodes.append(.placeholderTransform(index: n, pattern: pattern, format: format, options: opts))
                    return true
                }
                if parseChar("|") {
                    var choices: [[Node]] = []
                    while true {
                        guard let choice = parseFormatString(stop: ",|") else { i = backtrack; return false }
                        choices.append(choice)
                        let last = i > 0 ? chars[i - 1] : "|"
                        if last == "," { continue }
                        if last == "|" { break }
                        i = backtrack
                        return false
                    }
                    guard parseChar("}") else { i = backtrack; return false }
                    nodes.append(.placeholderChoice(index: n, choices: choices))
                    return true
                }
                if parseChar("}") {
                    nodes.append(.placeholder(index: n, content: []))
                    return true
                }
                i = backtrack
                return false
            }
            if let n = parseInt() {
                nodes.append(.placeholder(index: n, content: []))
                return true
            }
            i = backtrack
            return false
        }

        func parseCode(into nodes: inout [Node]) -> Bool {
            let backtrack = i
            guard parseChar("`") else { return false }
            var code = ""
            while let c = peek(), c != "`" { code.append(c); i += 1 }
            guard parseChar("`") else { i = backtrack; return false }
            nodes.append(.code(code))
            return true
        }
    }

    // MARK: - Expander

    final class Expander {
        var out: [UInt8] = []
        var caseChanges: [(Int, CaseChange)] = []
        var rankCount = 0
        var fields: [Int: SnippetField] = [:]
        var mirrors: [(Int, SnippetField)] = []
        var ambiguous: [(Int, SnippetField)] = []
        let getVariable: (String) -> String?
        let codeCallback: ((String) -> String)?

        init(getVariable: @escaping (String) -> String?, codeCallback: ((String) -> String)?) {
            self.getVariable = getVariable
            self.codeCallback = codeCallback
        }

        func visit(_ node: Node) {
            switch node {
            case .text(let s): out.append(contentsOf: Array(s.utf8))
            case .rawByte(let b): out.append(b)
            case .variable(let name):
                if let value = getVariable(name) { out.append(contentsOf: Array(value.utf8)) }
            case .variableTransform(let name, let pattern, let format, let options):
                let tmp = Expander(getVariable: getVariable, codeCallback: codeCallback)
                tmp.visitAll(pattern)
                tmp.handleCaseChanges()
                let patternString = tmp.string
                replace(src: getVariable(name) ?? "", pattern: patternString, options: options, format: format, repeatFlag: options.contains(.g))
            case .variableFallback(let name, let fallback):
                if let value = getVariable(name) { out.append(contentsOf: Array(value.utf8)) }
                else { visitAll(fallback) }
            case .variableCondition(let name, let ifSet, let ifNotSet):
                visitAll(getVariable(name) != nil ? ifSet : ifNotSet)
            case .variableChange(let name, let change):
                if let value = getVariable(name) { out.append(contentsOf: Array(TextFormatString.applyTransform(value, change: change).utf8)) }
            case .caseChange(let type):
                caseChanges.append((out.count, type))
            case .placeholder(let index, let content):
                let from = Pos(offset: out.count, rank: rankCount + 1)
                if fields[index] == nil { visitAll(content) }
                let to = Pos(offset: out.count, rank: rankCount + 3)
                rankCount += 3
                let field = SnippetField(index: index, range: Range(from, to))
                if fields[index] != nil { mirrors.append((index, field)) }
                else if content.isEmpty { ambiguous.append((index, field)) }
                else { fields[index] = field }
            case .placeholderTransform(let index, let pattern, let format, let options):
                let pos = Pos(offset: out.count, rank: rankCount + 1)
                rankCount += 3
                let field = SnippetField(index: index, range: Range(pos, Pos(offset: out.count, rank: rankCount)))
                field.pattern = pattern
                field.format = format
                field.options = options
                mirrors.append((index, field))
            case .placeholderChoice(let index, let choices):
                if fields[index] != nil { return }
                var all: [String] = []
                for choice in choices {
                    let tmp = Expander(getVariable: getVariable, codeCallback: codeCallback)
                    tmp.visitAll(choice)
                    tmp.handleCaseChanges()
                    all.append(tmp.string)
                }
                let pos = Pos(offset: out.count, rank: rankCount + 1)
                out.append(contentsOf: Array((all.first ?? "").utf8))
                rankCount += 3
                let field = SnippetField(index: index, range: Range(pos, Pos(offset: out.count, rank: rankCount)))
                field.choices = all
                fields[index] = field
            case .code(let code):
                if let callback = codeCallback {
                    var str = callback(code)
                    if !str.isEmpty, str.hasSuffix("\n") { str.removeLast() }
                    out.append(contentsOf: Array(str.utf8))
                }
            }
        }

        func visitAll(_ nodes: [Node]) { for n in nodes { visit(n) } }

        var string: String { String(decoding: out, as: UTF8.self) }

        /// Applies the deferred \U/\u/\L/\l case changes to `out`, in place.
        func handleCaseChanges() {
            caseChanges.append((out.count, .none))
            var result: [UInt8] = []
            var prev = 0
            var style: CaseChange = .none
            for (pos, type) in caseChanges {
                if prev < pos {
                    let segment = Array(out[prev..<pos])
                    let onlyNext = style == .upperNext || style == .lowerNext
                    if onlyNext {
                        // uppercase/lowercase only the first grapheme cluster
                        let str = String(decoding: segment, as: UTF8.self)
                        let first = String(str.prefix(1))
                        let rest = str.dropFirst()
                        let transformed: String
                        switch style {
                        case .upperNext: transformed = first.uppercased() + rest
                        case .lowerNext: transformed = first.lowercased() + rest
                        default: transformed = str
                        }
                        result.append(contentsOf: Array(transformed.utf8))
                    } else {
                        let str = String(decoding: segment, as: UTF8.self)
                        let transformed: String
                        switch style {
                        case .upper: transformed = str.uppercased()
                        case .lower: transformed = str.lowercased()
                        default: transformed = str
                        }
                        result.append(contentsOf: Array(transformed.utf8))
                    }
                }
                prev = pos
                style = type
            }
            out = result
            caseChanges = []
        }

        /// The C++ `expand_visitor::replace` — regex substitution with eclipsed
        /// captures and deferred per-match case changes.
        func replace(src: String, pattern: String, options: RegexpOptions, format: [Node], repeatFlag: Bool) {
            let ns = src as NSString
            let length = ns.length
            guard length > 0, let regex = try? NSRegularExpression(pattern: TextFormatString.normalize(pattern), options: TextFormatString.regexOptions(options)) else {
                out.append(contentsOf: Array(src.utf8))
                return
            }
            var it = 0
            for match in regex.matches(in: src, range: NSRange(location: 0, length: length)) {
                // C++ searches from `it` with ^ anchored to the buffer start —
                // matches(in:) already yields matches in order over the full range.
                if match.range.location < it { continue }
                if match.range.location > it {
                    out.append(contentsOf: Array((ns.substring(with: NSRange(location: it, length: match.range.location - it))).utf8))
                }
                var eclipsed = Set<String>()
                for i in 0..<match.numberOfRanges where match.range(at: i).location == NSNotFound {
                    eclipsed.insert(String(i))
                }
                let tmp = Expander(getVariable: { [eclipsed] name in
                    if eclipsed.contains(name) { return nil }
                    if let n = Int(name), n < match.numberOfRanges {
                        let r = match.range(at: n)
                        if r.location == NSNotFound { return nil }
                        return ns.substring(with: r)
                    }
                    return self.getVariable(name)
                }, codeCallback: codeCallback)
                tmp.visitAll(format)
                tmp.handleCaseChanges()
                out.append(contentsOf: tmp.out)
                it = match.range.location + match.range.length
                if !repeatFlag { break }
                if match.range.length == 0 {
                    if it >= length { break }
                    out.append(contentsOf: Array((ns.substring(with: NSRange(location: it, length: 1))).utf8))
                    it += 1
                }
            }
            if it < length {
                out.append(contentsOf: Array((ns.substring(from: it)).utf8))
            }
        }
    }

    // MARK: - Regex helpers

    /// Oniguruma `\p{^X}` negation → ICU `\P{X}` (the closing brace is shared).
    static func normalize(_ pattern: String) -> String {
        pattern.replacingOccurrences(of: "\\p{^", with: "\\P{")
    }

    static func regexOptions(_ opts: RegexpOptions) -> NSRegularExpression.Options {
        var o: NSRegularExpression.Options = []
        if opts.contains(.i) { o.insert(.caseInsensitive) }
        if opts.contains(.m) { o.insert(.anchorsMatchLines) }
        if opts.contains(.s) { o.insert(.dotMatchesLineSeparators) }
        if opts.contains(.e) { o.insert(.allowCommentsAndWhitespace) }
        return o
    }

    // MARK: - Transforms

    static func applyTransform(_ value: String, change: TransformChange) -> String {
        var value = value
        if change.contains(.upcase) { value = value.uppercased() }
        if change.contains(.downcase) { value = value.lowercased() }
        if change.contains(.capitalize) { value = capitalize(value) }
        if change.contains(.asciify) { value = asciify(value) }
        if change.contains(.urlEncode) { value = value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value }
        if change.contains(.shellEscape) { value = shellEscape(value) }
        if change.contains(.relative) { value = relativeTime(value) }
        if change.contains(.number) { value = formatNumber(value) }
        if change.contains(.duration) { value = formatDuration(value) }
        if change.contains(.dirname) { value = (value as NSString).deletingLastPathComponent }
        if change.contains(.basename) { value = (value as NSString).lastPathComponent }
        return value
    }

    /// C++ `capitalize`: downcase all-uppercase runs, then uppercase the first
    /// word and long words (skipping the stopword list).
    static func capitalize(_ src: String) -> String {
        let words = normalize("\\A\\p{^Lower}+\\z|\\b\\p{Upper}\\p{^Upper}+?\\b")
        let upcase = normalize("^([\\W\\d]*)(\\w[-\\w]*)|\\b((?!(?:else|from|over|then|when)\\b)\\w[-\\w]{3,}|\\w[-\\w]*[\\W\\d]*$)")
        let step1 = replace(src, pattern: words, format: "${0:/downcase}", options: [], repeatFlag: true, variables: [:])
        return replace(step1, pattern: upcase, format: "${1:?$1\\u$2:\\u$0}", options: [], repeatFlag: true, variables: [:])
    }

    /// C++ `asciify`: CFStringTransform strip diacritics + transliterate to ASCII.
    static func asciify(_ src: String) -> String {
        let cf = NSMutableString(string: src)
        CFStringTransform(cf, nil, "Any-Latin; Latin-ASCII" as CFString, false)
        return cf as String
    }

    static func shellEscape(_ src: String) -> String {
        let special = "|&;<>()$`\\\" \t\n*?[#˜=%"
        var res = ""
        var bow = src.startIndex
        while true {
            guard let range = src[bow...].range(of: "'") else {
                let word = String(src[bow...])
                let needQuotes = word.contains { special.contains($0) }
                if needQuotes { res += "'" }
                res += word
                if needQuotes { res += "'" }
                break
            }
            let word = String(src[bow..<range.lowerBound])
            let needQuotes = word.contains { special.contains($0) }
            if needQuotes { res += "'" }
            res += word
            if needQuotes { res += "'" }
            res += "\\'"
            bow = src.index(after: range.lowerBound)
        }
        return res
    }

    static func relativeTime(_ src: String) -> String { src }

    static func formatNumber(_ src: String) -> String {
        replace(src, pattern: "(\\d+)(\\.\\d+)?", format: "${1/\\d{1,3}(?=\\d{3}+(?!\\d))/$0,/g}${2}", options: [], repeatFlag: true, variables: [:])
    }

    static func formatDuration(_ src: String) -> String {
        guard let seconds = Double(src).map({ Int($0.rounded()) }) else { return src }
        var parts: [String] = []
        let units: [(name: String, amount: Int, include: Bool)] = [
            ("day", seconds / 60 / 60 / 24, true),
            ("hour", (seconds / 60 / 60) % 24, true),
            ("minute", (seconds / 60) % 60, true),
            ("second", seconds % 60, seconds < 10 * 60),
        ]
        for unit in units where unit.amount > 0 && unit.include {
            parts.append("\(unit.amount) \(unit.amount == 1 ? unit.name : unit.name + "s")")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Public API

    /// `format_string::expand` — variable expansion with no capture context.
    public static func expand(_ format: String, variables: [String: String]) -> String {
        expand(format) { variables[$0] }
    }

    public static func expand(_ format: String, getVariable: @escaping (String) -> String?) -> String {
        if !format.contains(where: { $0 == "$" || $0 == "\\" || $0 == "(" }) { return format }
        guard let nodes = Parser(format).parseFormatString(stop: "") else { return format }
        let expander = Expander(getVariable: getVariable, codeCallback: nil)
        expander.visitAll(nodes)
        expander.handleCaseChanges()
        return expander.string
    }

    /// `format_string::replace(src, pattern, format, repeat, variables)`.
    public static func replace(
        _ src: String,
        pattern: String,
        format: String,
        options: RegexpOptions = [],
        repeatFlag: Bool = false,
        variables: [String: String] = [:]
    ) -> String {
        guard let formatNodes = Parser(format).parseFormatString(stop: "") else { return src }
        let expander = Expander(getVariable: { variables[$0] }, codeCallback: nil)
        expander.replace(src: src, pattern: pattern, options: options, format: formatNodes, repeatFlag: repeatFlag)
        return expander.string
    }

    /// `format_string::escape` — escape a format string so expanding it yields
    /// the original text.
    public static func escape(_ format: String) -> String {
        var res = ""
        let chars = Array(format)
        for (i, c) in chars.enumerated() {
            switch c {
            case "\t": res += "\\t"
            case "\r": res += "\\r"
            case "\n": res += "\\n"
            case "$", "(", "\\":
                if c != "\\" || (i + 1 < chars.count && "\\$(trn".contains(chars[i + 1])) {
                    res += "\\"
                }
                res.append(c)
            default:
                res.append(c)
            }
        }
        return res
    }

    /// `snippet::parse` — expand a snippet string into fields/mirrors.
    public static func parseSnippet(_ str: String) -> Snippet {
        guard let nodes = Parser(str).parseSnippet(stop: "") else { return Snippet(text: Array(str.utf8), fields: [:], mirrors: [], variables: [:], indentString: "") }
        let expander = Expander(getVariable: { _ in nil }, codeCallback: nil)
        expander.visitAll(nodes)
        expander.handleCaseChanges()

        // Ambiguous placeholders (empty content, first occurrence) become
        // fields; later occurrences become mirrors.
        for (index, field) in expander.ambiguous {
            if expander.fields[index] == nil { expander.fields[index] = field }
            else { expander.mirrors.append((index, field)) }
        }
        return Snippet(text: expander.out, fields: expander.fields, mirrors: expander.mirrors, variables: [:], indentString: "")
    }
}

