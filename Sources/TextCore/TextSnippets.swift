import Foundation

public typealias FRange = TextFormatString.Range
public typealias FPos = TextFormatString.Pos

/// TextMate's snippet engine, ported from `snippet.cc` / `snippet.h`.
///
/// `Snippet` is the expanded snippet: plain text plus placeholder fields and
/// mirrors (transforms of field content). `Stack` is the snippet stack that
/// keeps nested snippets alive while the user types; every buffer edit flows
/// through `Stack.replace`, which returns the concrete (range, text) pairs the
/// caller applies to its buffer (with a running adjustment, like
/// `editor.cc::replace_helper`).
public struct Snippet {

    public var text: [UInt8]
    public var fields: [Int: TextFormatString.SnippetField]
    public var mirrors: [(Int, TextFormatString.SnippetField)]
    public var variables: [String: String]
    public var indentString: String
    public private(set) var currentField: Int

    public var string: String { String(decoding: text, as: UTF8.self) }

    public init(
        text: [UInt8],
        fields: [Int: TextFormatString.SnippetField],
        mirrors: [(Int, TextFormatString.SnippetField)],
        variables: [String: String],
        indentString: String
    ) {
        self.text = text
        self.fields = fields
        self.mirrors = mirrors
        self.variables = variables
        self.indentString = indentString
        self.currentField = 0
        setup()
    }

    // MARK: - setup

    private mutating func setup() {
        // Mirrors whose index has no field become fields (set_difference).
        let known = Set(fields.keys)
        let toMove = mirrors.filter { !known.contains($0.0) }.map { $0.0 }
        for index in toMove {
            if let idx = mirrors.firstIndex(where: { $0.0 == index }) {
                fields[index] = mirrors[idx].1
                mirrors.remove(at: idx)
            }
        }

        // Field 0 is the final caret (end of text).
        if fields[0] == nil {
            let n = text.count
            fields[0] = TextFormatString.SnippetField(index: 0, range: TextFormatString.Range(
                TextFormatString.Pos(offset: n, rank: Int.max - 2),
                TextFormatString.Pos(offset: n, rank: Int.max)
            ))
        }

        tabsToSpaces()
        indent()
        updateMirrors()
        currentField = fields.count > 1 ? fields.keys.filter { $0 > 0 }.min() ?? 0 : 0
    }

    // MARK: - tabs & indent

    /// Replaces `\t` with the configured tab string, adjusting all positions.
    private mutating func tabsToSpaces() {
        let tabString = "\t"  // indent_info.create() — default single tab
        guard tabString != "\t" else { return }
        var positions = allPositions()
        let data = text
        var tabStops: [Int] = []
        for (i, byte) in data.enumerated() where byte == 0x09 { tabStops.append(i) }
        guard !tabStops.isEmpty else { return }
        var newBuffer: [UInt8] = []
        var lastIndex = 0
        for index in tabStops {
            newBuffer.append(contentsOf: data[lastIndex..<index])
            newBuffer.append(contentsOf: Array(tabString.utf8))
            lastIndex = index + 1
        }
        newBuffer.append(contentsOf: data[lastIndex...])
        let delta = tabString.utf8.count - 1
        for i in positions.indices {
            let count = tabStops.filter { $0 <= positions[i].offset }.count
            positions[i].offset += delta * count
        }
        text = newBuffer
        applyPositions(positions)
    }

    /// Adds `indentString` to the start of every line after the first.
    private mutating func indent() {
        guard !indentString.isEmpty else { return }
        var positions = allPositions()
        var lines: [Int] = []
        var i = 0
        let bytes = text
        while i < bytes.count {
            if bytes[i] == 0x0A { lines.append(i + 1) }
            i += 1
        }
        let indentBytes = Array(indentString.utf8)
        var inserted = 0
        for line in lines {
            let offset = line + inserted
            for p in positions.indices where positions[p].offset >= offset {
                positions[p].offset += indentBytes.count
            }
            text.insert(contentsOf: indentBytes, at: offset)
            inserted += indentBytes.count
        }
        applyPositions(positions)
    }

    // MARK: - position bookkeeping

    private func allPositions() -> [TextFormatString.Pos] {
        var result: [TextFormatString.Pos] = []
        for field in fields.values { result.append(field.range.from); result.append(field.range.to) }
        for mirror in mirrors { result.append(mirror.1.range.from); result.append(mirror.1.range.to) }
        return result
    }

    private mutating func applyPositions(_ positions: [TextFormatString.Pos]) {
        var idx = 0
        for field in fields.values { field.range.from = positions[idx]; field.range.to = positions[idx + 1]; idx += 2 }
        for mirror in mirrors { mirror.1.range.from = positions[idx]; mirror.1.range.to = positions[idx + 1]; idx += 2 }
    }

    // MARK: - mirror updates

    private struct DependencyGraph {
        var dependencies: [Int: Set<Int>] = [:]
        mutating func addNode(_ node: Int) { dependencies[node] = dependencies[node] ?? [] }
        mutating func addEdge(_ node: Int, dependsOn: Int) { dependencies[node]?.insert(dependsOn) }
        func touch(_ node: Int) -> Set<Int> {
            var res: Set<Int> = []
            var active = [node]
            while let n = active.popLast() {
                if res.contains(n) { continue }
                res.insert(n)
                for (key, deps) in dependencies where deps.contains(n) {
                    active.append(key)
                }
            }
            return res
        }
        func topologicalOrder() -> [Int] {
            var res: [Int] = []
            var active = dependencies.filter { $0.value.isEmpty }.map { $0.key }
            var tmp = dependencies
            while let n = active.popLast() {
                res.append(n)
                for (key, var deps) in tmp {
                    if deps.contains(n) {
                        deps.remove(n)
                        tmp[key] = deps
                        if deps.isEmpty { active.append(key) }
                    }
                }
            }
            return res
        }
    }

    private func buildGraph() -> DependencyGraph {
        var graph = DependencyGraph()
        for field in fields { graph.addNode(field.key) }
        for field in fields {
            for other in fields where field.value.range.contains(other.value.range) {
                graph.addEdge(field.key, dependsOn: other.key)
            }
            for mirror in mirrors where field.value.range.contains(mirror.1.range) {
                graph.addEdge(field.key, dependsOn: mirror.0)
            }
        }
        return graph
    }

    /// Recomputes the content of all mirrors of the given fields.
    public mutating func updateMirrors(forFields requested: Set<Int> = []) {
        let graph = buildGraph()
        for node in graph.topologicalOrder() {
            if !requested.isEmpty && !requested.contains(node) { continue }
            guard let field = fields[node] else { continue }
            let src = field.range.toS(text)
            for mirror in mirrors where mirror.0 == node {
                var str = mirror.1.transform(src, variables: variables)
                // Insert indentation after every newline not at the end.
                str = TextFormatString.replace(str, pattern: "(?<=\\n)(?!$)", format: indentString, repeatFlag: true, variables: [:])
                applyReplace(range: mirror.1.range, str: str)
            }
        }
    }

    // MARK: - replace

    /// The static `snippet::replace` — mutates `text` and all positions.
    private mutating func applyReplace(range: FRange, str: String) {
        text.replaceSubrange(range.from.offset..<(range.from.offset + range.size), with: Array(str.utf8))
        var positions: [TextFormatString.Pos] = []
        for field in fields.values { positions.append(field.range.from); positions.append(field.range.to) }
        for mirror in mirrors { positions.append(mirror.1.range.from); positions.append(mirror.1.range.to) }
        let delta = str.utf8.count - range.size
        for i in positions.indices {
            if range.contains(positions[i]) {
                positions[i].offset = range.from.offset
            } else if range.from < positions[i] {
                positions[i].offset += delta
            }
        }
        var idx = 0
        for field in fields.values { field.range.from = positions[idx]; field.range.to = positions[idx + 1]; idx += 2 }
        for mirror in mirrors { mirror.1.range.from = positions[idx]; mirror.1.range.to = positions[idx + 1]; idx += 2 }
    }

    private mutating func replaceHelper(_ n: Int, range: FRange, replacement: String) -> [(FRange, String)] {
        let graph = buildGraph()
        let dirty = graph.touch(n)
        var updated: [(FRange, String)] = []
        for node in graph.topologicalOrder() where dirty.contains(node) {
            for mirror in mirrors where mirror.0 == node {
                updated.append((mirror.1.range, ""))
            }
        }
        applyReplace(range: range, str: replacement)
        updateMirrors(forFields: dirty)
        var i = 0
        for node in graph.topologicalOrder() where dirty.contains(node) {
            for mirror in mirrors where mirror.0 == node {
                updated[i].1 = mirror.1.range.toS(text)
                i += 1
            }
        }
        updated.sort { $0.0 < $1.0 }
        return updated
    }

    /// `snippet_t::replace` — an edit inside the current field. Returns the
    /// (range, text) pairs the caller applies to its buffer.
    public mutating func replace(range: FRange, str: String) -> [(FRange, String)] {
        guard let current = fields[currentField] else { return [(range, str)] }
        let currentFieldRange = current.range
        var local = range
        local.from.rank = currentFieldRange.from.rank + 1
        local.to.rank = currentFieldRange.from.rank + 1
        guard currentFieldRange.contains(local) else { return [(range, str)] }

        // Drop mirrors inside the active field.
        let mirrorsToRemove = mirrors.filter { currentFieldRange.contains($0.1.range) }
        for mirror in mirrorsToRemove {
            mirrors.removeAll { $0.1 === mirror.1 }
        }

        let res = replaceHelper(currentField, range: local, replacement: str)

        // Drop fields inside the active field, and their mirrors.
        let fieldsToRemove = fields.keys.filter { currentFieldRange.contains(fields[$0]!.range) }
        for key in fieldsToRemove {
            fields.removeValue(forKey: key)
            mirrors.removeAll { $0.0 == key }
        }
        return res
    }

    // MARK: - navigation

    public mutating func nextField() -> Bool {
        guard currentField != 0 else { return false }
        let currentFieldRange = fields[currentField]!.range
        var n = currentField
        while true {
            let keys = fields.keys.sorted()
            guard let i = keys.firstIndex(of: n) else { return false }
            n = keys[(i + 1) % keys.count]
            if fields[n]!.range != currentFieldRange {
                currentField = n
                return true
            }
            if n == 0 { break }
        }
        return false
    }

    public mutating func previousField() -> Bool {
        let keys = fields.keys.sorted()
        if currentField == 0 {
            guard keys.count > 1 else { return false }
            currentField = keys.last!
            return true
        }
        guard let i = keys.firstIndex(of: currentField), i > 0 else { return false }
        currentField = keys[i - 1]
        return true
    }

    // MARK: - stack

    public struct Stack {
        public struct Record {
            public var snippet: Snippet
            public var caret: Int
        }
        public private(set) var records: [Record] = []

        public init() {}

        public var isEmpty: Bool { records.isEmpty }

        public mutating func push(_ snippet: Snippet, range: FRange) {
            if !records.isEmpty {
                records[records.count - 1].caret = range.from.offset - current().from.offset
            }
            records.append(Record(snippet: snippet, caret: 0))
        }

        public mutating func clear() { records.removeAll() }

        public func current() -> FRange {
            guard !records.isEmpty else { return FRange(0, 0) }
            var offset = 0
            for i in 0..<(records.count - 1) {
                let field = records[i].snippet.fields[records[i].snippet.currentField]
                offset += (field?.range.from.offset ?? 0) + records[i].caret
            }
            let field = records[records.count - 1].snippet.fields[records[records.count - 1].snippet.currentField]
            return (field?.range ?? FRange(0, 0)) + offset
        }

        public var inLastPlaceholder: Bool {
            !records.isEmpty && records[records.count - 1].snippet.currentField == 0
        }

        public func choices() -> [String] {
            guard let last = records.last else { return [] }
            return last.snippet.fields[last.snippet.currentField]?.choiceList() ?? []
        }

        private mutating func dropForPos(_ pos: FPos) {
            while !records.isEmpty {
                if records[records.count - 1].snippet.currentField == 0 {
                    records.removeLast()
                    continue
                }
                var p = pos
                p.rank = current().from.rank + 1
                if current().contains(p) { return }
                records.removeLast()
            }
        }

        /// Routes an edit through the stack. Returns the (range, text) pairs
        /// to apply to the buffer (in order, with a running adjustment).
        public mutating func replace(range: FRange, replacement: String) -> [(FRange, String)] {
            var res: [(FRange, String)] = [(range, replacement)]
            dropForPos(range.from)
            dropForPos(range.to)
            guard !records.isEmpty else { return res }

            var offsets = [0]
            for record in records {
                let field = record.snippet.fields[record.snippet.currentField]
                offsets.append(offsets[offsets.count - 1] + (field?.range.from.offset ?? 0) + record.caret)
            }

            var range = range
            var replacement = replacement
            for recordIndex in stride(from: records.count - 1, through: 0, by: -1) {
                var snippet = records[recordIndex].snippet
                offsets.removeLast()
                let oldLen = snippet.text.count
                var local = range - offsets[offsets.count - 1]
                local.from.rank = snippet.fields[snippet.currentField]!.range.from.rank + 1
                local.to.rank = snippet.fields[snippet.currentField]!.range.from.rank + 1

                var prepend: [(FRange, String)] = []
                for pair in snippet.replace(range: local, str: replacement) {
                    if pair.0.from < local.from {
                        prepend.append((pair.0 + offsets[offsets.count - 1], pair.1))
                    } else {
                        res.append((pair.0 + offsets[offsets.count - 1], pair.1))
                    }
                }
                res.insert(contentsOf: prepend, at: 0)

                replacement = snippet.string
                range = FRange(offsets[offsets.count - 1], offsets[offsets.count - 1] + oldLen)
                records[recordIndex].snippet = snippet
            }
            return res
        }

        public mutating func next() -> Bool {
            while !records.isEmpty {
                var snippet = records[records.count - 1].snippet
                if snippet.currentField != 0, snippet.nextField() {
                    records[records.count - 1].snippet = snippet
                    return true
                }
                records.removeLast()
            }
            return false
        }

        public mutating func previous() -> Bool {
            while !records.isEmpty {
                var snippet = records[records.count - 1].snippet
                if snippet.currentField == 0 {
                    if snippet.fields.count > 1 {
                        snippet.currentField = snippet.fields.keys.max()!
                        records[records.count - 1].snippet = snippet
                        return true
                    }
                    records.removeLast()
                    continue
                }
                if snippet.previousField() {
                    records[records.count - 1].snippet = snippet
                    return true
                }
                records.removeLast()
            }
            return false
        }
    }
}

/// A minimal buffer + snippet-stack harness reproducing the editor semantics
/// (`editor.cc::replace_helper`): pairs are applied with a running adjustment.
public struct SnippetEditor {
    public private(set) var text: [UInt8]
    public var stack = Snippet.Stack()

    public init(text: [UInt8] = []) { self.text = text }

    public var string: String { String(decoding: text, as: UTF8.self) }

    /// Applies a replacement through the snippet stack; returns the caret
    /// position after the edit.
    @discardableResult
    public mutating func replace(range: TextFormatString.Range, with str: String) -> Int {
        let pairs = stack.replace(range: range, replacement: str)
        var adjustment = 0
        var caret = 0
        for (pairRange, pairStr) in pairs {
            let from = pairRange.from.offset + adjustment
            let to = pairRange.to.offset + adjustment
            let clampedFrom = max(0, min(text.count, from))
            let clampedTo = max(clampedFrom, min(text.count, to))
            text.replaceSubrange(clampedFrom..<clampedTo, with: Array(pairStr.utf8))
            caret = clampedFrom + pairStr.utf8.count
            adjustment += pairStr.utf8.count - (clampedTo - clampedFrom)
        }
        // The caret tracks the snippet's current field (the C++ heuristic).
        return stack.isEmpty ? caret : stack.current().to.offset
    }

    /// `snippet_dispatch` — insert the snippet text and push it on the stack.
    /// Returns the active field's range (the initial selection).
    @discardableResult
    public mutating func dispatch(_ snippetText: String, at offset: Int = 0) -> TextFormatString.Range {
        let snippet = TextFormatString.parseSnippet(snippetText)
        text.insert(contentsOf: snippet.text, at: offset)
        let field = snippet.fields[snippet.currentField]
        let fieldRange = field?.range ?? TextFormatString.Range(offset, offset)
        stack.push(snippet, range: fieldRange)
        return fieldRange
    }

    /// Current caret (point) in buffer coordinates.
    public var caret: Int {
        let r = stack.current()
        return r.to.offset
    }
}
