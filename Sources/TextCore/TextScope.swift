import Foundation

/// Port of the `scope` framework (Frameworks/scope) — TextMate's scope chain
/// and scope-selector matching, including the exact rank formula used for
/// specificity ordering. This is the foundation the grammar engine (4.T2) and
/// syntax highlighting (4.S2) build on.

// MARK: - Scope

/// An ordered stack of scope elements, outermost first (`back` = innermost),
/// mirroring `scope::scope_t`. Each element is a dotted atom string such as
/// `comment.block`.
public struct Scope: Equatable, CustomStringConvertible {
    /// Outermost → innermost.
    public private(set) var elements: [String]

    public init() {
        elements = []
    }

    public init(_ string: String) {
        elements = []
        for element in string.split(separator: " ") where !element.isEmpty {
            elements.append(String(element))
        }
    }

    public init(_ elements: [String]) {
        self.elements = elements
    }

    public var isEmpty: Bool { elements.isEmpty }

    public var count: Int { elements.count }

    /// Innermost element (`scope.back()`).
    public var back: String {
        precondition(!elements.isEmpty)
        return elements[elements.count - 1]
    }

    public mutating func pushScope(_ element: String) {
        elements.append(element)
    }

    public mutating func popScope() {
        precondition(!elements.isEmpty)
        elements.removeLast()
    }

    /// True when this scope starts with `prefix` from the outermost side
    /// (`scope.has_prefix` pops innermost elements of the longer scope).
    public func hasPrefix(_ prefix: Scope) -> Bool {
        guard elements.count >= prefix.elements.count else { return false }
        return Array(elements.prefix(prefix.elements.count)) == prefix.elements
    }

    /// Port of `scope::shared_prefix`: the longest common prefix from the
    /// outermost side.
    public static func sharedPrefix(_ lhs: Scope, _ rhs: Scope) -> Scope {
        var l = lhs.elements
        var r = rhs.elements
        if l.count > r.count {
            l.removeLast(l.count - r.count)
        } else if r.count > l.count {
            r.removeLast(r.count - l.count)
        }
        while let a = l.last, let b = r.last, a != b {
            l.removeLast()
            r.removeLast()
        }
        return Scope(l)
    }

    /// Port of `scope::xml_difference`: `<open>scope<close>` markup for
    /// transitioning the scope stack from `from` to `to`.
    public static func xmlDifference(_ from: Scope, _ to: Scope, open: String = "<", close: String = ">") -> String {
        let fromScopes = from.elements
        let toScopes = to.elements
        var common = 0
        while common < min(fromScopes.count, toScopes.count), fromScopes[common] == toScopes[common] {
            common += 1
        }
        var res = ""
        for element in fromScopes[common...].reversed() {
            res += open + "/" + element + close
        }
        for element in toScopes[common...] {
            res += open + element + close
        }
        return res
    }

    /// `attr.*`/`dyn.*` scopes are auxiliary (not part of the "real" chain).
    internal func isAuxiliary(at index: Int) -> Bool {
        let element = elements[index]
        return element.hasPrefix("attr.") || element.hasPrefix("dyn.")
    }

    internal func numberOfAtoms(at index: Int) -> Int {
        elements[index].filter { $0 == "." }.count + 1
    }

    public var description: String { elements.joined(separator: " ") }
}

/// `scope::context_t`: a left/right scope pair (used for `L:`/`R:` filters and
/// the snippet/paired scopes model).
public struct ScopeContext: Equatable {
    public var left: Scope
    public var right: Scope

    public init(left: Scope, right: Scope) {
        self.left = left
        self.right = right
    }

    public init(_ scope: Scope) {
        self.init(left: scope, right: scope)
    }
}

// MARK: - Selector parsing

/// Parsed selector tree, mirroring scope/src/types.h.
indirect enum SelectorNode {
    case path(SelectorPath)
    case group(Selector)
    case filter(FilterSide, SelectorNode)
}

enum FilterSide: Character {
    case left = "L"
    case right = "R"
    case both = "B"
}

struct SelectorScope {
    var atoms: String = ""
    var anchorToPrevious = false
}

struct SelectorPath {
    var scopes: [SelectorScope] = []
    var anchorToBOL = false
    var anchorToEOL = false
}

struct SelectorExpression {
    enum Op: Character {
        case none = "\0"
        case or = "|"
        case and = "&"
        case minus = "-"
    }
    var op: Op
    var negate = false
    var node: SelectorNode = .path(SelectorPath())
}

struct SelectorComposite {
    var expressions: [SelectorExpression] = []
}

struct Selector {
    var composites: [SelectorComposite] = []
}

/// Recursive-descent parser, a faithful transliteration of scope/src/parse.cc.
enum SelectorParser {
    static func parse(_ string: String) -> Selector {
        var parser = Context(string)
        parser.ws()
        _ = parser.parseSelector()
        return parser.selector
    }

    struct Context {
        let chars: [Character]
        var index: Int
        var selector = Selector()

        init(_ string: String) {
            chars = Array(string)
            index = 0
        }

        var it: Character? { index < chars.count ? chars[index] : nil }

        @discardableResult
        mutating func ws() -> Bool {
            while let c = it, c == " " || c == "\t" {
                index += 1
            }
            return true
        }

        @discardableResult
        mutating func parseChar(_ chars: String, dst: inout Character?) -> Bool {
            guard let c = it, chars.contains(c) else { return false }
            dst = c
            index += 1
            return true
        }

        mutating func parseChar(_ chars: String) -> Bool {
            var dummy: Character?
            return parseChar(chars, dst: &dummy)
        }

        mutating func parseScope(_ res: inout SelectorScope) -> Bool {
            res.anchorToPrevious = parseChar(">") && ws()

            let from = index
            repeat {
                if it == nil {
                    break
                }
                guard let c = it, c.isLetter || c.isNumber || c == "*" || c.asciiValue.map({ $0 >= 0x80 }) == true else {
                    break
                }
                while let d = it, d.isLetter || d.isNumber || d == "_" || d == "-" || d == "+" || d == "*" || d.asciiValue.map({ $0 >= 0x7F }) == true {
                    index += 1
                }
            } while parseChar(".")
            res.atoms = String(chars[from..<index])
            return from != index
        }

        mutating func parsePath(_ res: inout SelectorPath) -> Bool {
            res.anchorToBOL = parseChar("^") && ws()

            repeat {
                var scope = SelectorScope()
                if !parseScope(&scope) {
                    break
                }
                res.scopes.append(scope)
            } while ws()

            res.anchorToEOL = parseChar("$")
            return true
        }

        mutating func parseGroup(_ res: inout SelectorNode) -> Bool {
            let bt = index
            var group = Selector()
            if parseChar("("), parseSelector(&group), ws(), parseChar(")") {
                res = .group(group)
                return true
            }
            index = bt
            return false
        }

        mutating func parseFilter(_ res: inout SelectorNode) -> Bool {
            let bt = index
            var side: Character?
            if parseChar("LRB", dst: &side), parseChar(":"), ws() {
                var inner: SelectorNode = .path(SelectorPath())
                if parseGroup(&inner) {
                    // parsed as a group
                } else {
                    var path = SelectorPath()
                    guard parsePath(&path) else {
                        index = bt
                        return false
                    }
                    inner = .path(path)
                }
                guard let s = side, let filterSide = FilterSide(rawValue: s) else { return false }
                res = .filter(filterSide, inner)
                return true
            }
            index = bt
            return false
        }

        mutating func parseExpression(_ res: inout SelectorExpression) -> Bool {
            if parseChar("-"), ws() {
                res.negate = true
            }
            var node: SelectorNode = .path(SelectorPath())
            if parseFilter(&node) || parseGroup(&node) {
                res.node = node
                return true
            }
            var path = SelectorPath()
            guard parsePath(&path) else { return false }
            res.node = .path(path)
            return true
        }

        mutating func parseComposite(_ res: inout SelectorComposite) -> Bool {
            var rc = false
            var op: Character?
            repeat {
                var tmp = SelectorExpression(op: SelectorExpression.Op(rawValue: op ?? "\0") ?? .none)
                if !parseExpression(&tmp) {
                    break
                }
                res.expressions.append(tmp)
                rc = true
            } while ws() && parseChar("&|-", dst: &op) && ws()
            return rc
        }

        mutating func parseSelector(_ res: inout Selector) -> Bool {
            var rc = false
            ws()
            repeat {
                var composite = SelectorComposite()
                if !parseComposite(&composite) {
                    break
                }
                res.composites.append(composite)
                rc = true
            } while ws() && parseChar(",") && ws()
            return rc
        }

        mutating func parseSelector() -> Bool {
            var sel = selector
            let ok = parseSelector(&sel)
            selector = sel
            return ok
        }
    }
}

// MARK: - Matching (scope/src/match.cc)

/// Port of `types::prefix_match`: pattern vs scope element, where `*` in the
/// pattern matches a run of non-`.` characters.
func scopePrefixMatch(_ pattern: String, _ element: String) -> Bool {
    let p = Array(pattern)
    let e = Array(element)
    var pi = 0
    var ei = 0
    while pi < p.count, ei < e.count {
        if p[pi] == e[ei] {
            pi += 1
            ei += 1
        } else if p[pi] == "*" {
            pi += 1
            while ei < e.count, e[ei] != "." {
                ei += 1
            }
        } else {
            return false
        }
    }
    return pi == p.count && (ei == e.count || e[ei] == ".")
}

enum ScopeMatcher {
    /// `path_t::does_match` — walk the scope chain innermost → outermost,
    /// matching selector scopes in reverse, with `>` backtracking.
    static func pathMatches(_ path: SelectorPath, lhs: Scope, rhs: Scope, rank: inout Double?) -> Bool {
        var nodeIndex = rhs.elements.count - 1
        var selIndex = path.scopes.count - 1
        var score = 0.0
        var power = 0.0

        var btNodeIndex: Int?
        var btSelIndex: Int?
        var btScore = 0.0

        if path.anchorToEOL {
            while nodeIndex >= 0, rhs.isAuxiliary(at: nodeIndex) {
                if rank != nil {
                    power += Double(rhs.numberOfAtoms(at: nodeIndex))
                }
                nodeIndex -= 1
            }
            btSelIndex = selIndex
        }

        while nodeIndex >= 0, selIndex >= 0 {
            if rank != nil {
                power += Double(rhs.numberOfAtoms(at: nodeIndex))
            }

            // The outermost selector scope is redundant for ^-anchored paths
            // when it isn't the outermost scope node (avoids matching "bar"
            // in "^ foo > bar" against a non-initial position).
            let isRedundantNonBOLMatch = path.anchorToBOL && nodeIndex > 0 && selIndex == 0
            if !isRedundantNonBOLMatch, scopePrefixMatch(path.scopes[selIndex].atoms, rhs.elements[nodeIndex]) {
                if path.scopes[selIndex].anchorToPrevious {
                    if btSelIndex == nil {
                        btNodeIndex = nodeIndex
                        btSelIndex = selIndex
                        btScore = score
                    }
                } else if btSelIndex != nil {
                    btSelIndex = nil
                    btNodeIndex = nil
                }

                if rank != nil {
                    let len = path.scopes[selIndex].atoms.filter { $0 == "." }.count + 1
                    var l = len
                    while l != 0 {
                        score += 1 / pow(2, power - Double(l))
                        l -= 1
                    }
                }
                selIndex -= 1
            } else if btSelIndex != nil {
                guard let btNode = btNodeIndex else { break }
                nodeIndex = btNode
                selIndex = btSelIndex!
                score = btScore
                btSelIndex = nil
                btNodeIndex = nil
            }

            nodeIndex -= 1
        }

        if rank != nil {
            rank = selIndex < 0 ? score : 0
        }
        return selIndex < 0
    }

    static func compositeMatches(_ composite: SelectorComposite, lhs: Scope, rhs: Scope, rank: inout Double?) -> Bool {
        var res = false
        if rank != nil {
            var sum = 0.0
            for expr in composite.expressions {
                var r: Double? = 0
                var local = nodeMatches(expr.node, lhs: lhs, rhs: rhs, rank: &r)
                if local {
                    sum = max(r ?? 0, sum)
                }
                if expr.negate {
                    local = !local
                }
                switch expr.op {
                case .none: res = local
                case .or: res = res || local
                case .and: res = res && local
                case .minus: res = res && !local
                }
            }
            if res {
                rank = sum
            }
            return res
        }

        for expr in composite.expressions {
            let op = expr.op
            if res && op == .or {
                continue
            } else if !res && op == .and {
                continue
            } else if !res && op == .minus {
                continue
            }
            var local = nodeMatches(expr.node, lhs: lhs, rhs: rhs, rank: &rank)
            if expr.negate {
                local = !local
            }
            switch op {
            case .none: res = local
            case .or: res = res || local
            case .and: res = res && local
            case .minus: res = res && !local
            }
        }
        return res
    }

    static func nodeMatches(_ node: SelectorNode, lhs: Scope, rhs: Scope, rank: inout Double?) -> Bool {
        switch node {
        case .path(let path):
            return pathMatches(path, lhs: lhs, rhs: rhs, rank: &rank)
        case .group(let selector):
            return selectorMatches(selector, lhs: lhs, rhs: rhs, rank: &rank)
        case .filter(let side, let inner):
            switch side {
            case .both:
                if rank != nil {
                    var r1: Double? = 0
                    var r2: Double? = 0
                    if nodeMatches(inner, lhs: lhs, rhs: lhs, rank: &r1),
                       nodeMatches(inner, lhs: rhs, rhs: rhs, rank: &r2) {
                        rank = max(r1 ?? 0, r2 ?? 0)
                        return true
                    }
                    return false
                }
                return nodeMatches(inner, lhs: lhs, rhs: lhs, rank: &rank)
                    && nodeMatches(inner, lhs: rhs, rhs: rhs, rank: &rank)
            case .left:
                return nodeMatches(inner, lhs: lhs, rhs: lhs, rank: &rank)
            case .right:
                return nodeMatches(inner, lhs: rhs, rhs: rhs, rank: &rank)
            }
        }
    }

    static func selectorMatches(_ selector: Selector, lhs: Scope, rhs: Scope, rank: inout Double?) -> Bool {
        if rank != nil {
            var res = false
            var sum = 0.0
            for composite in selector.composites {
                var r: Double? = 0
                if compositeMatches(composite, lhs: lhs, rhs: rhs, rank: &r) {
                    sum = max(r ?? 0, sum)
                    res = true
                }
            }
            if res {
                rank = sum
            }
            return res
        }
        for composite in selector.composites where compositeMatches(composite, lhs: lhs, rhs: rhs, rank: &rank) {
            return true
        }
        return false
    }
}

// MARK: - Public selector

/// Port of `scope::selector_t`: a parsed scope selector with ranked matching.
public struct ScopeSelector {
    public static let wildcard = Scope("x-any")

    private let selector: Selector

    public init(_ string: String) {
        selector = SelectorParser.parse(string)
    }

    /// `selector_t::does_match(context_t)`: returns the rank when the selector
    /// matches (or one side is the wildcard scope), nil otherwise.
    public func doesMatch(_ context: ScopeContext) -> Double? {
        var rank: Double? = 1.0
        if context.left == ScopeSelector.wildcard || context.right == ScopeSelector.wildcard {
            return rank
        }
        guard ScopeMatcher.selectorMatches(selector, lhs: context.left, rhs: context.right, rank: &rank) else {
            return nil
        }
        return rank
    }

    public func doesMatch(_ scope: Scope) -> Double? {
        doesMatch(ScopeContext(scope))
    }
}
