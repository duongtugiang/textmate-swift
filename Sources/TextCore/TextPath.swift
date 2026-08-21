import Foundation

/// Path string utilities (roadmap 3.T2 / issue #27), ported from the original
/// TextMate `io/path.cc`. The byte-level `normalize` algorithm is transliterated
/// faithfully so the original `io/tests/t_path.cc` cases hold verbatim.
public enum TextPath {

    // MARK: - normalize (byte-level, mirroring path.cc)

    /// Removes `/./` segments and duplicate slashes (path.cc `remove_current_dir`).
    private static func removeCurrentDir(_ path: inout [UInt8]) {
        var src = 0
        var dst = 0
        var prev: UInt8 = 0
        var pprev: UInt8 = 0
        while src < path.count {
            if (src == 1 || pprev == 0x2F) && prev == 0x2E && path[src] == 0x2F {
                dst -= 1 // skip the '.'
            } else if !(src != 0 && prev == 0x2F && path[src] == 0x2F) {
                if src != dst { path[dst] = path[src] }
                dst += 1
            }
            pprev = prev
            prev = path[src]
            src += 1
        }
        if dst > 1 && prev == 0x2F {
            path.removeSubrange((dst - 1)..<path.count) // trim trailing '/'
        } else if pprev == 0x2F && prev == 0x2E {
            path.removeSubrange(max(dst - 2, 0)..<path.count) // trim trailing "/."
        } else {
            path.removeSubrange(dst..<path.count)
        }
    }

    private static func isParentMetaEntry(_ token: ArraySlice<UInt8>) -> Bool {
        switch token.count {
        case 2: return Array(token) == [0x2E, 0x2E]          // ".."
        case 3: return Array(token) == [0x2F, 0x2E, 0x2E]    // "/.."
        default: return false
        }
    }

    /// Resolves `..` components (path.cc `remove_parent_dir`).
    private static func removeParentDir(_ path: inout [UInt8]) {
        guard !path.isEmpty else { return }
        var first = 0
        let last = path.count
        if path[first] == 0x2F { first += 1 }

        var work = Array(path[first..<last].reversed())
        var src = 0
        var dst = 0
        var toSkip = 0
        while src < work.count {
            let from = src
            while src < work.count && (src == from || work[src] != 0x2F) {
                src += 1
            }
            let token = work[from..<src]
            if isParentMetaEntry(token) {
                toSkip += 1
            } else if toSkip > 0 {
                toSkip -= 1
            } else {
                work.replaceSubrange(dst..<(dst + token.count), with: Array(token))
                dst += token.count
            }
        }
        // Build the kept prefix, then append surviving '..' entries and reverse
        // (mirrors path.cc appending parent_str then reversing [first, dst)).
        var kept = Array(work[..<dst])
        while toSkip > 0 {
            kept.append(contentsOf: [0x2F, 0x2E, 0x2E])
            toSkip -= 1
        }
        var result = Array(kept.reversed())
        if !result.isEmpty && result.last == 0x2F { // workaround for trailing '..'
            result.removeLast()
        }
        path.replaceSubrange(first..<last, with: result)
    }

    /// Normalizes a path: removes `/./`, duplicate slashes, and resolves `..`
    /// (path.cc `path::normalize`).
    public static func normalize(_ path: String) -> String {
        var bytes = Array(path.utf8)
        removeCurrentDir(&bytes)
        removeParentDir(&bytes)
        return String(decoding: bytes, as: UTF8.self)
    }

    // MARK: - Components

    /// Basename of a path.
    public static func name(_ path: String) -> String {
        let normalized = normalize(path)
        if let index = normalized.lastIndex(of: "/") {
            return String(normalized[normalized.index(after: index)...])
        }
        return normalized
    }

    /// Parent directory of a path.
    public static func parent(_ path: String) -> String {
        path == "/" ? path : join(path, "..")
    }

    /// Joins a base path with another (absolute `path` replaces `base`).
    public static func join(_ base: String, _ path: String) -> String {
        path.first == "/" ? normalize(path) : normalize(base + "/" + path)
    }

    // MARK: - Extensions

    /// The last extension, including the dot ("" if none).
    public static func `extension`(_ path: String) -> String {
        let base = name(normalize(path))
        if let index = base.lastIndex(of: ".") {
            return String(base[index...])
        }
        return ""
    }

    /// All extensions, including the dot (e.g. ".tar.bz2"); a leading run of
    /// lowercase letters between dots is folded in.
    public static func extensions(_ path: String) -> String {
        let base = name(normalize(path))
        var n = base.lastIndex(of: ".")
        if let nIndex = n, nIndex != base.startIndex {
            let before = base.index(before: nIndex)
            if let m = base[..<before].lastIndex(of: ".") {
                let between = base[base.index(after: m)..<nIndex]
                if !between.isEmpty && between.allSatisfy({ $0.isLowercase && $0.isASCII }) {
                    n = m
                }
            }
        }
        if let n {
            return String(base[n...])
        }
        return ""
    }

    public static func stripExtension(_ path: String) -> String {
        let normalized = normalize(path)
        return String(normalized.dropLast(`extension`(path).count))
    }

    public static func stripExtensions(_ path: String) -> String {
        let normalized = normalize(path)
        return String(normalized.dropLast(extensions(path).count))
    }

    /// Rank of an extension match: suffix matches score by length, with a bonus
    /// for `.`/`_` separators (path.cc `path::rank`).
    public static func rank(_ path: String, _ ext: String) -> Int {
        if path.count >= ext.count && path.hasSuffix(ext) {
            if path.count == ext.count { return ext.count }
            let index = path.index(path.endIndex, offsetBy: -ext.count - 1)
            if path[index] == "." || path[index] == "_" { return ext.count + 1 }
            if path[index] == "/" { return ext.count }
        }
        return 0
    }

    // MARK: - Comparisons

    public static func isAbsolute(_ path: String) -> Bool {
        if !path.isEmpty && path.first == "/" {
            let normalized = normalize(path)
            if normalized != "/.." && !normalized.hasPrefix("/../") {
                return true
            }
        }
        return false
    }

    public static func isChild(_ child: String, of parent: String) -> Bool {
        let child = normalize(child)
        let parent = normalize(parent)
        return child.hasPrefix(parent) && (parent.count == child.count || child.dropFirst(parent.count).first == "/")
    }

    /// Replaces a leading home-directory prefix with `~`.
    public static func withTilde(_ path: String) -> String {
        let base = home()
        var normalized = normalize(path)
        if path.count > 1 && path.last == "/" { normalized += "/" }
        if normalized.hasPrefix(base) && (normalized.count == base.count || normalized[normalized.index(normalized.startIndex, offsetBy: base.count)] == "/") {
            return "~" + normalized.dropFirst(base.count)
        }
        return normalized
    }

    /// The current user's home directory (path.cc `path::home()`).
    public static func home() -> String {
        FileManager.default.homeDirectoryForCurrentUser.path
    }

    /// Path of `p` relative to base `b` (path.cc `path::relative_to`).
    public static func relativeTo(_ p: String, _ b: String) -> String {
        if b.isEmpty { return p }
        if p.isEmpty { return b }
        let path = normalize(p)
        let base = normalize(b)
        if path.first != "/" { return path }

        let abs = split(base)
        let rel = split(path)
        var i = 0
        while i < abs.count && i < rel.count && abs[i] == rel[i] {
            i += 1
        }
        if i == 1 { // only "/" in common
            return b == "/" ? String(path.dropFirst()) : path
        }
        var res: [String] = Array(repeating: "..", count: abs.count - i)
        res.append(contentsOf: rel[i...])
        return joinComponents(res)
    }

    // MARK: - Helpers

    private static func split(_ path: String) -> [String] {
        var res: [String] = []
        var from = path.startIndex
        while from < path.endIndex {
            if let to = path[from...].firstIndex(of: "/") {
                res.append(String(path[from..<to]))
                from = path.index(after: to)
            } else {
                res.append(String(path[from...]))
                from = path.endIndex
            }
        }
        return res
    }

    private static func joinComponents(_ components: [String]) -> String {
        if components == [""] { return "/" }
        return components.joined(separator: "/")
    }
}
