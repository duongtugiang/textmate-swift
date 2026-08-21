import Foundation

// MARK: - Grammar engine (Frameworks/parse)

/// Faithful Swift port of the TextMate grammar engine: rule/stack model
/// (grammar.h/private.h), pattern compilation (grammar.cc), and the per-line
/// parse loop with ranked matching, while/begin/end rules, captures, and the
/// scope-collection map (parse.cc). Regex matching is delegated to `TextRegex`
/// (the 4.T2 spike decision: ICU emulation instead of a full Onigmo port).
///
/// Offsets are UTF-16 units (NSRegularExpression's coordinate space); the
/// C++ operates on bytes. For ASCII — all of the ported suites — they agree.

// MARK: - Rule model

public final class GrammarRule {
    private static var ruleIDCounter = 0

    public let ruleID: Int

    public var includeString: String?
    public var scopeString: String?
    public var contentScopeString: String?
    public var matchString: String?
    public var whileString: String?
    public var endString: String?
    public var applyEndLast = false

    public var children: [GrammarRule] = []
    public var captures: [String: GrammarRule] = [:]
    public var beginCaptures: [String: GrammarRule] = [:]
    public var whileCaptures: [String: GrammarRule] = [:]
    public var endCaptures: [String: GrammarRule] = [:]
    public var repository: [String: GrammarRule] = [:]
    /// Compiled `injections` plist dict (selector string → rule).
    public var injections: [(selector: ScopeSelector, rule: GrammarRule)] = []

    // Pre-parsed versions (private.h)
    public var include: GrammarRule?
    public var matchPattern: TextRegex?
    public var whilePattern: TextRegex?
    public var endPattern: TextRegex?
    public var matchPatternIsAnchored = false

    // Mutable per-collect state
    public var included = false
    public var isRoot = false

    public init() {
        GrammarRule.ruleIDCounter += 1
        ruleID = GrammarRule.ruleIDCounter
    }
}

// MARK: - Stack model (private.h)

public final class GrammarStack {
    public let parent: GrammarStack?
    public let rule: GrammarRule
    public var scope: Scope
    /// Expanded `rule.scopeString` for this stack frame.
    public var scopeString: String?
    /// Expanded `rule.contentScopeString` for this stack frame.
    public var contentScopeString: String?
    public var whilePattern: TextRegex?
    public var endPattern: TextRegex?
    /// `anchor` — offset at which `\G` may match next.
    public var anchor: Int
    public var zwBeginMatch = false
    public var applyEndLast = false

    public init(rule: GrammarRule, scope: Scope, parent: GrammarStack?) {
        self.rule = rule
        self.scope = scope
        self.parent = parent
        self.anchor = 0
    }
}

// MARK: - Scope collection (scopes_t in parse.cc)

final class GrammarScopes {
    struct Record {
        let pos: Int
        let scope: String
        let add: Bool
        let order: Int
    }

    var records: [Record] = []
    var tracking = false
    var stack: [String] = []
    private var orderCounter = 0

    func add(_ pos: Int, _ scope: String) {
        if tracking {
            stack.append(scope)
        }
        records.append(Record(pos: pos, scope: scope, add: true, order: orderCounter))
        orderCounter += 1
    }

    func remove(_ pos: Int, _ scope: String, endRule: Bool = false) {
        // The C++ multimap keeps insertion order for equal keys, so ordering
        // is purely chronological; `endRule` only affects the tracking stack.
        records.append(Record(pos: pos, scope: scope, add: false, order: orderCounter))
        orderCounter += 1
        if tracking {
            if stack.last == scope {
                stack.removeLast()
            }
        }
    }

    /// `scopes_t::update` — fold records into a per-position scope map.
    func update(_ scope: Scope) -> (Scope, [Int: Scope]) {
        var out: [Int: Scope] = [:]
        let sorted = records.sorted { a, b in
            a.pos != b.pos ? a.pos < b.pos : a.order < b.order
        }
        var pos = 0
        var sc = scope
        for rec in sorted {
            if pos != rec.pos {
                out[pos] = sc
                pos = rec.pos
            }
            if rec.add {
                sc.pushScope(rec.scope)
            } else {
                if sc.back == rec.scope {
                    sc.popScope()
                } else {
                    var popped: [String] = []
                    while sc.back != rec.scope {
                        popped.append(sc.back)
                        sc.popScope()
                    }
                    sc.popScope()
                    for element in popped.reversed() {
                        sc.pushScope(element)
                    }
                }
            }
        }
        out[pos] = sc
        return (sc, out)
    }
}

// MARK: - Grammar

public final class Grammar {

    public let root: GrammarRule

    static let sizeMax = Int.max

    /// Build a grammar from a plist dictionary (the `.tmLanguage` structure:
    /// `scopeName`/`name`/`match`/`begin`/`while`/`end`/`patterns`/`captures`/
    /// `repository`/`injections`/`include`/`disabled`, as loaded by
    /// `convert_plist` in grammar.cc).
    public init?(plist: [String: Any]) {
        guard let root = Grammar.convertRule(plist) else { return nil }
        Grammar.setupIncludes(root, base: root, selfRule: root, stack: [root])
        Grammar.compilePatterns(root)
        root.isRoot = true
        self.root = root
    }

    /// `grammar_t::seed()`.
    public func seed() -> GrammarStack {
        GrammarStack(rule: root, scope: Scope(root.scopeString ?? ""), parent: nil)
    }

    /// `buffer_t::parse` — parse one line (including its trailing newline)
    /// and return the resulting stack + the line's scope map.
    public func parseLine(_ line: String, stack: GrammarStack, firstLine: Bool) -> (stack: GrammarStack, scopes: [Int: Scope]) {
        let scopes = GrammarScopes()
        // The C++ folds the records over the *input* stack's scope
        // (`scopes.update(stack->scope, map)`), not the returned stack's.
        let inputScope = stack.scope
        let result = Grammar.parse(line, stack: stack, scopes: scopes, firstLine: firstLine, i: 0, limit: nil)
        let (finalScope, map) = scopes.update(inputScope)
        result.scope = finalScope
        return (result, map)
    }

    // MARK: Loading (grammar.cc)

    static func convertRule(_ plist: [String: Any]) -> GrammarRule? {
        if plist.isEmpty {
            return nil
        }
        if let disabled = plist["disabled"] as? Int, disabled != 0 {
            return nil
        }
        let rule = GrammarRule()
        // The C++ schema maps both "name" and "scopeName" to scope_string;
        // the plist dictionary is std::map-sorted, so "name" < "scopeName"
        // and scopeName wins for the root grammar rule.
        rule.scopeString = plist["scopeName"] as? String ?? plist["name"] as? String
        rule.contentScopeString = plist["contentName"] as? String
        rule.matchString = plist["match"] as? String ?? plist["begin"] as? String
        rule.whileString = plist["while"] as? String
        rule.endString = plist["end"] as? String
        rule.applyEndLast = (plist["applyEndPatternLast"] as? String) == "1"
        rule.includeString = plist["include"] as? String

        if let patterns = plist["patterns"] as? [[String: Any]] {
            for pattern in patterns {
                if let child = convertRule(pattern) {
                    rule.children.append(child)
                }
            }
        }
        rule.captures = convertRepository(plist["captures"])
        rule.beginCaptures = convertRepository(plist["beginCaptures"])
        rule.whileCaptures = convertRepository(plist["whileCaptures"])
        rule.endCaptures = convertRepository(plist["endCaptures"])
        rule.repository = convertRepository(plist["repository"])
        if let injections = plist["injections"] as? [String: [String: Any]] {
            for (selector, rulePlist) in injections {
                if let child = convertRule(rulePlist) {
                    rule.injections.append((ScopeSelector(selector), child))
                }
            }
        }
        return rule
    }

    static func convertRepository(_ value: Any?) -> [String: GrammarRule] {
        guard let dict = value as? [String: [String: Any]] else { return [:] }
        var res: [String: GrammarRule] = [:]
        for (key, plist) in dict {
            if let rule = convertRule(plist) {
                res[key] = rule
            }
        }
        return res
    }

    /// `setup_includes` — resolve `$base`/`$self`/`#name` includes.
    static func setupIncludes(_ rule: GrammarRule, base: GrammarRule, selfRule: GrammarRule, stack: [GrammarRule]) {
        precondition(rule.include == nil)
        if let include = rule.includeString {
            if include == "$base" {
                rule.include = base
            } else if include == "$self" {
                rule.include = selfRule
            } else if include.hasPrefix("#") {
                let name = String(include.dropFirst())
                for ancestor in stack.reversed() {
                    if rule.include == nil, let repoRule = ancestor.repository[name] {
                        rule.include = repoRule
                    }
                }
                // Cross-grammar includes ("source.python#x") need a bundles
                // index — not built yet (4.S6); leave unresolved.
            } else {
                // Cross-grammar include by scope — unresolved without bundles.
            }
        } else {
            for child in rule.children {
                setupIncludes(child, base: base, selfRule: selfRule, stack: stack + [rule])
            }
            for repo in [rule.repository, rule.captures, rule.beginCaptures, rule.whileCaptures, rule.endCaptures] {
                for (_, child) in repo {
                    setupIncludes(child, base: base, selfRule: selfRule, stack: stack + [rule])
                }
            }
        }
    }

    /// `compile_patterns` — pre-compile match/while/end patterns.
    static func compilePatterns(_ rule: GrammarRule) {
        if let match = rule.matchString {
            rule.matchPattern = TextRegex(match)
            rule.matchPatternIsAnchored = patternHasAnchor(match)
        }
        if let w = rule.whileString, !patternHasBackReference(w) {
            rule.whilePattern = TextRegex(w)
        }
        if let e = rule.endString, !patternHasBackReference(e) {
            rule.endPattern = TextRegex(e)
        }
        for child in rule.children {
            compilePatterns(child)
        }
        for repo in [rule.repository, rule.captures, rule.beginCaptures, rule.whileCaptures, rule.endCaptures] {
            for (_, child) in repo {
                compilePatterns(child)
            }
        }
    }

    /// `pattern_has_back_reference` — an unescaped `\digit`.
    static func patternHasBackReference(_ pattern: String) -> Bool {
        var escape = false
        for ch in pattern {
            if escape, ch.isNumber {
                return true
            }
            escape = !escape && ch == "\\"
        }
        return false
    }

    /// `pattern_has_anchor` — an unescaped `\G`.
    static func patternHasAnchor(_ pattern: String) -> Bool {
        var escape = false
        for ch in pattern {
            if escape, ch == "G" {
                return true
            }
            escape = !escape && ch == "\\"
        }
        return false
    }

    // MARK: - The per-line parse (parse.cc)

    private static func parse(_ line: String, stack: GrammarStack, scopes: GrammarScopes, firstLine: Bool, i initialI: Int, limit: Int?) -> GrammarStack {
        var stack = stack
        var i = initialI
        let ns = line as NSString
        let lineLength = ns.length
        let searchLimit = limit ?? lineLength
        let lineEndsWithNewline = lineLength > 0 && ns.character(at: lineLength - 1) == 0x0A

        // ==============================
        // = apply the 'while' patterns =
        // ==============================

        var whileRules: [GrammarStack] = []
        var node: GrammarStack? = stack
        while let n = node, n.whilePattern != nil {
            whileRules.append(n)
            if n.scopeString != nil {
                scopes.remove(i, n.scopeString!, endRule: true)
            }
            if n.contentScopeString != nil {
                scopes.remove(i, n.contentScopeString!, endRule: true)
            }
            node = n.parent
        }

        var scope = whileRules.isEmpty ? stack.scope : whileRules.last!.parent!.scope

        for whileRule in whileRules.reversed() {
            if let m = whileRule.whilePattern!.search(line: line, from: i, options: TextRegex.SearchOptions(gposEnabled: true, firstLine: true, noteos: false)) {
                let rule = whileRule.rule
                if let scopeStringField = rule.scopeString {
                    let scopeString = Grammar.expand(scopeStringField, match: m)
                    scope.pushScope(scopeString)
                    scopes.add(m.begin, scopeString)
                }
                Grammar.applyCaptures(scope, match: m, captures: rule.whileCaptures.isEmpty ? rule.captures : rule.whileCaptures, scopes: scopes, firstLine: firstLine)
                if let contentScopeStringField = rule.contentScopeString {
                    let scopeString = Grammar.expand(contentScopeStringField, match: m)
                    scope.pushScope(scopeString)
                    scopes.add(m.end, scopeString)
                }
                stack.anchor = m.end
                i = m.end
                continue
            }
            stack = whileRule.parent!
            if stack.whilePattern != nil {
                stack.anchor = i
            }
            break
        }

        // ======================
        // = Parse rest of line =
        // ======================

        var rules = collectRules(line, i: i, firstLine: firstLine, stack: stack, limit: searchLimit)

        while !rules.isEmpty {
            var m = rules.removeFirst()

            if m.match.begin < i {
                // Stale match — re-search at the current position.
                let pattern = m.isEndPattern ? stack.endPattern! : m.rule.matchPattern!
                if let newMatch = Grammar.search(pattern, line: line, from: i, firstLine: firstLine, lineEndsWithNewline: lineEndsWithNewline, stack: stack) {
                    m.match = newMatch
                    insert(&rules, m)
                }
                continue
            }

            i = m.match.end

            let rule = m.rule
            if m.isEndPattern {
                if stack.contentScopeString != nil {
                    scopes.remove(m.match.begin, stack.contentScopeString!, endRule: true)
                }
                Grammar.applyCaptures(scope, match: m.match, captures: rule.endCaptures.isEmpty ? rule.captures : rule.endCaptures, scopes: scopes, firstLine: firstLine)
                if stack.scopeString != nil {
                    scopes.remove(m.match.end, stack.scopeString!, endRule: true)
                }

                let nothingMatched = stack.zwBeginMatch && stack.anchor == i

                stack = stack.parent!
                scope = stack.scope

                if nothingMatched {
                    // No bytes parsed by a begin/end rule — destined to repeat.
                    break
                }
            } else if rule.whileString != nil || rule.endString != nil {
                // Begin-part of a rule.
                if m.match.isEmpty && hasCycle(rule.ruleID, i: i, stack: stack) {
                    break
                }

                let newStack = GrammarStack(rule: rule, scope: Scope(), parent: stack)

                if rule.scopeString != nil {
                    newStack.scopeString = Grammar.expand(rule.scopeString!, match: m.match)
                    scope.pushScope(newStack.scopeString!)
                    scopes.add(m.match.begin, newStack.scopeString!)
                }

                Grammar.applyCaptures(scope, match: m.match, captures: rule.beginCaptures.isEmpty ? rule.captures : rule.beginCaptures, scopes: scopes, firstLine: firstLine)

                if rule.contentScopeString != nil {
                    newStack.contentScopeString = Grammar.expand(rule.contentScopeString!, match: m.match)
                    scope.pushScope(newStack.contentScopeString!)
                    scopes.add(m.match.end, newStack.contentScopeString!)
                }

                newStack.scope = scope
                newStack.whilePattern = rule.whilePattern
                newStack.endPattern = rule.endPattern
                newStack.applyEndLast = rule.applyEndLast
                newStack.anchor = i
                newStack.zwBeginMatch = m.match.isEmpty
                newStack.parent!.anchor = Grammar.sizeMax

                if rule.whilePattern == nil, rule.whileString != nil {
                    newStack.whilePattern = TextRegex(Grammar.expandBackReferences(rule.whileString!, match: m.match))
                }
                if rule.endPattern == nil, rule.endString != nil {
                    newStack.endPattern = TextRegex(Grammar.expandBackReferences(rule.endString!, match: m.match))
                }
                stack = newStack
            } else {
                // Regular match rule.
                if m.match.isEmpty {
                    continue // do not re-apply (matched zero characters)
                }

                if let scopeStringField = rule.scopeString {
                    let scopeString = Grammar.expand(scopeStringField, match: m.match)
                    scopes.add(m.match.begin, scopeString)
                    scopes.remove(m.match.end, scopeString)
                }

                Grammar.applyCaptures(scope, match: m.match, captures: rule.captures, scopes: scopes, firstLine: firstLine)

                if let newMatch = Grammar.search(rule.matchPattern!, line: line, from: i, firstLine: firstLine, lineEndsWithNewline: lineEndsWithNewline, stack: stack) {
                    let reinserted = RankedMatch(rule: rule, match: newMatch, rank: m.rank, isEndPattern: false)
                    insert(&rules, reinserted)
                }
                continue // no context change, so skip finding rules for this context
            }

            rules = collectRules(line, i: i, firstLine: firstLine, stack: stack, limit: searchLimit)
        }

        // `stack->anchor = first + stack->anchor == last ? 0 : SIZE_T_MAX`
        stack.anchor = stack.anchor == lineLength ? 0 : Grammar.sizeMax
        return stack
    }

    // MARK: - Rule collection (collect_rules/apply_rules)

    private struct RankedMatch {
        let rule: GrammarRule
        var match: TextRegex.Match
        let rank: Int
        let isEndPattern: Bool
    }

    private static func insert(_ rules: inout [RankedMatch], _ m: RankedMatch) {
        var lo = 0
        var hi = rules.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if rules[mid].match.begin < m.match.begin || (rules[mid].match.begin == m.match.begin && rules[mid].rank < m.rank) {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        rules.insert(m, at: lo)
    }

    private static func collectRules(_ line: String, i: Int, firstLine: Bool, stack: GrammarStack, limit: Int) -> [RankedMatch] {
        var rules: [GrammarRule] = []
        var groups: [GrammarRule]? = []
        var injectedPre: [GrammarRule] = []
        var injectedPost: [GrammarRule] = []

        collectChildren(stack.rule.children, res: &rules, groups: &groups)
        collectInjections(stack, scope: ScopeContext(left: stack.scope, right: Scope()), groups: groups ?? [], res: &injectedPre)
        collectInjections(stack, scope: ScopeContext(left: Scope(), right: stack.scope), groups: groups ?? [], res: &injectedPost)

        for group in groups ?? [] {
            group.included = false
        }

        let ns = line as NSString
        let lineEndsWithNewline = ns.length > 0 && ns.character(at: ns.length - 1) == 0x0A

        var res: [RankedMatch] = []
        var rank = applyRules(rank: 0, rules: injectedPre, line: line, i: i, firstLine: firstLine, lineEndsWithNewline: lineEndsWithNewline, stack: stack, res: &res)
        let endPatternRank = rank + 1
        rank += 1
        rank = applyRules(rank: rank, rules: rules, line: line, i: i, firstLine: firstLine, lineEndsWithNewline: lineEndsWithNewline, stack: stack, res: &res)

        if let endPattern = stack.endPattern {
            if let m = Grammar.search(endPattern, line: line, from: i, firstLine: firstLine, lineEndsWithNewline: lineEndsWithNewline, stack: stack) {
                let endRank = stack.applyEndLast ? rank + 1 : endPatternRank
                if stack.applyEndLast {
                    rank += 1
                }
                res.append(RankedMatch(rule: stack.rule, match: m, rank: endRank, isEndPattern: true))
            }
        }

        _ = applyRules(rank: rank, rules: injectedPost, line: line, i: i, firstLine: firstLine, lineEndsWithNewline: lineEndsWithNewline, stack: stack, res: &res)

        return res.sorted { a, b in
            a.match.begin != b.match.begin ? a.match.begin < b.match.begin : a.rank < b.rank
        }
    }

    @discardableResult
    private static func applyRules(rank: Int, rules: [GrammarRule], line: String, i: Int, firstLine: Bool, lineEndsWithNewline: Bool, stack: GrammarStack, res: inout [RankedMatch]) -> Int {
        var rank = rank
        for rule in rules {
            rule.included = false
            if let match = Grammar.search(rule.matchPattern!, line: line, from: i, firstLine: firstLine, lineEndsWithNewline: lineEndsWithNewline, stack: stack) {
                rank += 1
                res.append(RankedMatch(rule: rule, match: match, rank: rank, isEndPattern: false))
            }
        }
        return rank
    }

    static func search(_ pattern: TextRegex, line: String, from: Int, firstLine: Bool, lineEndsWithNewline: Bool, stack: GrammarStack) -> TextRegex.Match? {
        let options = TextRegex.SearchOptions.anchors(firstLine: firstLine, isGPos: stack.anchor == from, lineEndsWithNewline: lineEndsWithNewline)
        return pattern.search(line: line, from: from, options: options)
    }

    // MARK: - collect_rule / collect_children / collect_injections

    private static func collectRule(_ rule: GrammarRule, res: inout [GrammarRule], groups: inout [GrammarRule]?) {
        var rule: GrammarRule? = rule
        while let r = rule, let include = r.include, !r.included {
            if groups != nil {
                r.included = true
                groups!.append(r)
            }
            rule = include
        }

        guard let final = rule, !final.included else { return }

        if final.matchPattern != nil {
            final.included = true
            res.append(final)
        } else if !final.children.isEmpty {
            if groups != nil {
                final.included = true
                groups!.append(final)
            }
            collectChildren(final.children, res: &res, groups: &groups)
        }
    }

    private static func collectChildren(_ children: [GrammarRule], res: inout [GrammarRule], groups: inout [GrammarRule]?) {
        for child in children {
            collectRule(child, res: &res, groups: &groups)
        }
    }

    private static func collectInjections(_ stack: GrammarStack, scope: ScopeContext, groups: [GrammarRule], res: inout [GrammarRule]) {
        var node: GrammarStack? = stack
        while let n = node {
            for (selector, rule) in n.rule.injections where selector.doesMatch(scope) != nil {
                var none: [GrammarRule]? = nil
                collectRule(rule, res: &res, groups: &none)
            }
            node = n.parent
        }
        for group in groups where !group.isRoot {
            for (selector, rule) in group.injections where selector.doesMatch(scope) != nil {
                var none: [GrammarRule]? = nil
                collectRule(rule, res: &res, groups: &none)
            }
        }
    }

    // MARK: - has_cycle

    private static func hasCycle(_ ruleID: Int, i: Int, stack: GrammarStack) -> Bool {
        if !stack.zwBeginMatch || stack.anchor != i {
            return false
        } else if ruleID == stack.rule.ruleID {
            return true
        }
        return stack.parent != nil ? hasCycle(ruleID, i: i, stack: stack.parent!) : false
    }

    // MARK: - apply_captures

    static func applyCaptures(_ scope: Scope, match: TextRegex.Match, captures: [String: GrammarRule], scopes: GrammarScopes, firstLine: Bool) {
        if captures.isEmpty {
            return
        }

        // Merge the captures repository with the match's capture indices
        // (C++: two string-sorted maps walked in lockstep).
        var matched: [(key: String, from: Int, to: Int)] = []
        for (key, _) in captures {
            guard let idx = Int(key), idx < match.captureRanges.count, match.didMatch(idx) else { continue }
            let from = match.begin(idx)
            let to = match.end(idx)
            if from != to {
                matched.append((key, from, to))
            }
        }
        // Sorted by (begin, -length, key) — leftmost first, longest first;
        // ties break by capture-index string order, matching the C++ lockstep
        // merge over the string-sorted repository and capture indices.
        matched.sort { a, b in
            if a.from != b.from { return a.from < b.from }
            if (a.to - a.from) != (b.to - b.from) { return (a.to - a.from) > (b.to - b.from) }
            return a.key < b.key
        }

        for entry in matched {
            let rule = captures[entry.key]!
            let from = entry.from
            let to = entry.to

            if rule.scopeString != nil {
                let scopeString = expand(rule.scopeString!, match: match)
                scopes.add(from, scopeString)
                scopes.remove(to, scopeString)
            }

            if !rule.children.isEmpty {
                let stack = GrammarStack(rule: rule, scope: scope, parent: nil)
                stack.anchor = from

                let savedStack = scopes.stack
                scopes.stack = []
                scopes.tracking = true
                let truncated = (match.line as NSString).substring(with: NSRange(location: 0, length: to))
                _ = Grammar.parse(truncated, stack: stack, scopes: scopes, firstLine: firstLine, i: from, limit: nil)
                while !scopes.stack.isEmpty {
                    scopes.remove(to, scopes.stack.last!, endRule: true)
                }
                scopes.tracking = false
                scopes.stack = savedStack
            }
        }
    }

    // MARK: - expand / expand_back_references / escape_regexp

    /// `pattern_is_format_string` + `format_string::expand` (minimal `$n`).
    static func expand(_ format: String, match: TextRegex.Match) -> String {
        guard format.contains("$") else { return format }
        let chars = Array(format)
        var res = ""
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\\", i + 1 < chars.count, chars[i + 1] == "$" {
                res += "$"
                i += 2
                continue
            }
            if c == "$", i + 1 < chars.count {
                if chars[i + 1] == "{" {
                    var j = i + 2
                    var digits = ""
                    while j < chars.count, chars[j].isNumber {
                        digits.append(chars[j])
                        j += 1
                    }
                    if j < chars.count, chars[j] == "}", !digits.isEmpty, let n = Int(digits), n < match.captureRanges.count {
                        if let text = match.captureText(n) {
                            res += text
                        }
                        i = j + 1
                        continue
                    }
                } else if chars[i + 1].isNumber {
                    var j = i + 1
                    var digits = ""
                    while j < chars.count, chars[j].isNumber {
                        digits.append(chars[j])
                        j += 1
                    }
                    if let n = Int(digits), n < match.captureRanges.count, let text = match.captureText(n) {
                        res += text
                        i = j
                        continue
                    }
                }
            }
            res.append(c)
            i += 1
        }
        return res
    }

    /// `expand_back_references` — `\1`-`\9` → regex-escaped capture text.
    static func expandBackReferences(_ pattern: String, match: TextRegex.Match) -> String {
        var escape = false
        var res = ""
        for ch in pattern {
            if escape {
                if let d = ch.wholeNumberValue {
                    if d < match.captureRanges.count, let text = match.captureText(d) {
                        res += escapeRegexp(text)
                    }
                    escape = false
                    continue
                }
                res += "\\"
                escape = false
            }
            if ch == "\\" {
                escape = true
            } else {
                res.append(ch)
            }
        }
        return res
    }

    /// `escape_regexp` (parse.cc) — `\ | ( [ { } ) ] . ? * + ^ $`.
    static func escapeRegexp(_ s: String) -> String {
        var out = ""
        for ch in s {
            if "\\|([{}]).?*+^$".contains(ch) {
                out += "\\"
            }
            out.append(ch)
        }
        return out
    }
}
