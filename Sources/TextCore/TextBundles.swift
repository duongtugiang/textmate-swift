import Foundation

/// The bundles framework (4.S6 / 4.T3) — a port of TextMate's `bundles`
/// framework: bundle items (snippets, commands, grammars, settings…), indexed
/// querying by field + scope rank, per-scope environment variables
/// (`shellVariables` with v1 shadowing), and shell-command requirements.
///
/// Item kind bitmask (exact `bundles::kItemType*` values).
public enum BundleItemKind: Int {
    case command = 1
    case dragCommand = 2
    case grammar = 4
    case macro = 8
    case settings = 16
    case snippet = 32
    case proxy = 64
    case theme = 128
    case bundle = 256
    case menu = 512
    case menuItemSeparator = 1024
    case unknown = 2048

    /// `kItemTypeMenuTypes` — kinds shown in menus.
    public static let menuTypes: Int = command.rawValue | macro.rawValue | snippet.rawValue | proxy.rawValue

    /// `kItemTypeMost` — the default query kind: everything except
    /// settings/bundle/menu/separator/unknown.
    public static let most: Int = ~(settings.rawValue | bundle.rawValue | menu.rawValue | menuItemSeparator.rawValue | unknown.rawValue)
}

/// A parsed `requiredCommands` entry.
public struct RequiredCommand {
    public let command: String
    public let moreInfoURL: String?
    public let variable: String?
    public let locations: [String]
}

/// A single bundle item (or a bundle itself).
public final class BundleItem {
    public private(set) var uuid: String
    public let kind: Int
    public let plist: [String: Any]
    /// Parent bundle (nil for top-level bundles). Weak to avoid cycles.
    public weak var bundle: BundleItem?
    /// Filesystem path (for bundles: the `info.plist` path, per C++ `save()`).
    public var path: String?

    public private(set) var name: String?
    public private(set) var disabled = false
    public private(set) var deleted = false
    public private(set) var hiddenFromUser = false
    public private(set) var scopeSelector: ScopeSelector?
    /// Field → values (multimap semantics: a field can hold several values).
    public private(set) var fields: [String: [String]] = [:]
    /// `require` entries (name + uuid of required bundles).
    public private(set) var requiredBundles: [(name: String, uuid: String)] = []
    public private(set) var requiredCommands: [RequiredCommand] = []

    private static let stringKeys: Set<String> = [
        "name", "keyEquivalent", "tabTrigger", "semanticClass",
        "contentMatch", "firstLineMatch", "scope", "injectionSelector",
    ]

    public init(kind: Int, plist: [String: Any], uuid: String = UUID().uuidString.uppercased(), path: String? = nil) {
        self.kind = kind
        self.plist = plist
        self.uuid = uuid
        self.path = path
        parse()
    }

    /// Convenience for tests: parse an old-style plist string.
    public convenience init?(kind: Int, plistText: String, path: String? = nil) {
        guard let dict = TextPlist.parse(plistText) else { return nil }
        self.init(kind: kind, plist: dict, path: path)
    }

    private func parse() {
        if let name = plist["name"] as? String { self.name = name }
        if let uuid = plist["uuid"] as? String, !uuid.isEmpty { self.uuid = uuid }
        if let scope = plist["scope"] as? String { scopeSelector = ScopeSelector(scope) }
        if let disabled = plist["isDisabled"] as? Int, disabled != 0 { self.disabled = true }
        if let deleted = plist["isDeleted"] as? Int, deleted != 0 { self.deleted = true }
        if let hidden = plist["hideFromUser"] as? Int, hidden != 0 { self.hiddenFromUser = true }

        for (key, value) in plist {
            if Self.stringKeys.contains(key) {
                if let str = value as? String {
                    if key == "semanticClass" {
                        for part in str.split(separator: ",") {
                            let trimmed = part.trimmingCharacters(in: .whitespaces)
                            if !trimmed.isEmpty { addField(key, trimmed) }
                        }
                    } else {
                        addField(key, str)
                    }
                }
            } else if key == "dropExtension" || key == "fileTypes" {
                if let array = value as? [Any] {
                    for item in array {
                        if let str = item as? String { addField(key, str) }
                    }
                }
            } else if key == "settings" {
                if let dict = value as? [String: Any] {
                    for dictKey in dict.keys { addField(key, dictKey) }
                }
            }
        }

        if let require = plist["require"] as? [Any] {
            for entry in require {
                if let dict = entry as? [String: Any],
                   let name = dict["name"] as? String {
                    requiredBundles.append((name, (dict["uuid"] as? String) ?? ""))
                }
            }
        }

        if let commands = plist["requiredCommands"] as? [Any] {
            for entry in commands {
                if let dict = entry as? [String: Any], let command = dict["command"] as? String {
                    let locations = (dict["locations"] as? [Any])?.compactMap { $0 as? String } ?? []
                    requiredCommands.append(RequiredCommand(
                        command: command,
                        moreInfoURL: dict["moreInfoURL"] as? String,
                        variable: dict["variable"] as? String,
                        locations: locations
                    ))
                }
            }
        }
    }

    private func addField(_ field: String, _ value: String) {
        fields[field, default: []].append(value)
    }

    func values(forField field: String) -> [String] {
        fields[field] ?? []
    }

    /// `bundle_variables()` — environment contributed by the item's bundle:
    /// `TM_BUNDLE_ITEM_NAME`/`TM_BUNDLE_ITEM_UUID` for non-bundle items,
    /// `TM_BUNDLE_SUPPORT` for bundles, and `TM_<NAME>_BUNDLE_SUPPORT` for
    /// each required bundle.
    func bundleVariables(in index: BundleIndex) -> [String: String] {
        var result: [String: String] = [:]
        if kind != BundleItemKind.bundle.rawValue {
            if let bundle {
                result.merge(bundle.bundleVariables(in: index)) { _, new in new }
            }
            result["TM_BUNDLE_ITEM_NAME"] = name ?? ""
            result["TM_BUNDLE_ITEM_UUID"] = uuid
        } else {
            if let support = supportPath() {
                result["TM_BUNDLE_SUPPORT"] = support
            }
        }
        for require in requiredBundles {
            let bundles = index.query(
                field: "name", value: require.name,
                scope: Scope(), kind: BundleItemKind.bundle.rawValue,
                bundle: require.uuid.isEmpty ? nil : require.uuid
            )
            if bundles.count == 1, let support = bundles[0].supportPath() {
                let key = TextFormatString.expand(
                    "TM_${name/.*/\\U${0/[^a-zA-Z]+/_/g}/}_BUNDLE_SUPPORT",
                    variables: ["name": require.name]
                )
                result[key] = support
            }
        }
        return result
    }

    /// `support_path()` — for a bundle at `<bundle>/info.plist`, the
    /// `Support` directory next to it (exists-checked).
    func supportPath() -> String? {
        guard let path else { return nil }
        let joined = ((path as NSString).appendingPathComponent("..") as NSString)
            .appendingPathComponent("Support")
        let standardized = (joined as NSString).standardizingPath
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }
        return standardized
    }

    /// `does_match(field, value, scope, kind, bundle)` → rank if it matches.
    func doesMatch(field: String, value: String, scope: Scope, kind: Int, bundle: String?) -> Double? {
        var match = false
        if field.isEmpty {
            match = true
        } else {
            for candidate in values(forField: field) {
                if candidate == value {
                    match = true
                    break
                }
                if field == "semanticClass",
                   candidate.count > value.count,
                   candidate.hasPrefix(value),
                   candidate[candidate.index(candidate.startIndex, offsetBy: value.count)] == "." {
                    match = true
                    break
                }
            }
        }
        guard match else { return nil }
        guard (kind & self.kind) == self.kind else { return nil }
        // bundle_uuid(): the parent bundle's uuid, or the item's own uuid for
        // a top-level bundle item (matches `item_t::bundle_uuid()`).
        let bundleUUID: String?
        if let parent = self.bundle {
            bundleUUID = parent.uuid
        } else if kind == BundleItemKind.bundle.rawValue {
            bundleUUID = uuid
        } else {
            bundleUUID = nil
        }
        if let bundle, bundle != bundleUUID { return nil }
        // An item without a scope selector matches everywhere (rank 1); an
        // item with one only matches when the selector does (nil = no match).
        guard let selector = scopeSelector else { return 1 }
        return selector.doesMatch(scope)
    }
}

/// The bundle index: owns all items and answers queries.
public final class BundleIndex {
    public private(set) var items: [BundleItem] = []

    public init() {}

    @discardableResult
    public func add(_ item: BundleItem) -> BundleItem {
        items.append(item)
        return item
    }

    @discardableResult
    public func add(kind: Int, plistText: String, path: String? = nil) -> BundleItem? {
        guard let item = BundleItem(kind: kind, plistText: plistText, path: path) else { return nil }
        items.append(item)
        return item
    }

    @discardableResult
    public func add(kind: Int, plist: [String: Any], path: String? = nil) -> BundleItem {
        let item = BundleItem(kind: kind, plist: plist, path: path)
        items.append(item)
        return item
    }

    /// `bundles::query(field, value, scope, kind, bundle, filter,
    /// includeDisabled)` — items matching field+scope+kind, ordered by rank
    /// descending; `filter` keeps only the top rank.
    public func query(
        field: String,
        value: String,
        scope: Scope = Scope(),
        kind: Int = BundleItemKind.most,
        bundle: String? = nil,
        filter: Bool = true,
        includeDisabled: Bool = false
    ) -> [BundleItem] {
        var ranked: [(Double, BundleItem)] = []
        for item in items {
            if item.deleted || (!includeDisabled && item.disabled) { continue }
            if let rank = item.doesMatch(field: field, value: value, scope: scope, kind: kind, bundle: bundle) {
                ranked.append((rank, item))
            }
        }
        ranked.sort { $0.0 > $1.0 }
        let topRank = ranked.first?.0
        return ranked.compactMap { pair in
            if filter, let topRank, pair.0 != topRank { return nil }
            return pair.1
        }
    }

    /// `scope_variables(base, scope)` — collect `shellVariables` from all
    /// settings items matching the scope, expand in lowest-rank-first order
    /// (highest rank wins), and apply v1 shadowing.
    public func scopeVariables(_ base: [String: String], scope: Scope) -> [String: String] {
        var result = base
        let items = query(
            field: "settings", value: "shellVariables", scope: scope,
            kind: BundleItemKind.settings.rawValue, filter: false
        )

        var stack: [Set<String>] = []
        for item in items.reversed() {
            var names = Set<String>()
            for pair in shellVariables(of: item) {
                // C++ `tmp << res`: each expansion sees the accumulated
                // result (earlier pairs of this item and all lower-ranked
                // items).
                var vars = item.bundleVariables(in: self)
                vars.merge(result) { _, new in new }
                result[pair.name] = TextFormatString.expand(pair.value, variables: vars)
                names.insert(pair.name)
            }
            stack.append(names)
        }

        // Shadowing: walk the stack most-specific-first; an item whose var
        // names overlap a more-specific item's is wholly shadowed (v1
        // semantics — `riterate` in the C++).
        var didSet = Set<String>()
        var shouldUnset = Set<String>()
        for set in stack.reversed() {
            if set.intersection(didSet).isEmpty {
                didSet.formUnion(set)
            } else {
                shouldUnset.formUnion(set)
            }
        }
        for key in shouldUnset.subtracting(didSet) {
            result.removeValue(forKey: key)
        }
        return result
    }

    private func shellVariables(of item: BundleItem) -> [(name: String, value: String)] {
        guard let settings = item.plist["settings"] as? [String: Any],
              let variables = settings["shellVariables"] as? [Any] else {
            return []
        }
        var result: [(String, String)] = []
        for entry in variables {
            guard let dict = entry as? [String: Any] else { continue }
            if let disabled = dict["disabled"] as? Int, disabled != 0 { continue }
            if let name = dict["name"] as? String, let value = dict["value"] as? String {
                result.append((name, value))
            }
        }
        return result
    }

    /// `missing_requirement(item, &environment)` — resolves `requiredCommands`
    /// against the environment; returns the first unsatisfied requirement.
    @discardableResult
    public func missingRequirement(
        for item: BundleItem,
        environment: inout [String: String]
    ) -> (missing: Bool, failed: RequiredCommand?) {
        var requirements: [RequiredCommand] = []
        if item.kind != BundleItemKind.bundle.rawValue {
            requirements.append(contentsOf: item.bundle?.requiredCommands ?? [])
        }
        requirements.append(contentsOf: item.requiredCommands)

        for requirement in requirements {
            var candidates: [String] = []

            if let variable = requirement.variable, let value = environment[variable] {
                if let firstSpace = value.firstIndex(of: " ") {
                    candidates.append(String(value[..<firstSpace]))
                }
                candidates.append(value)
                if candidates.contains(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
                    continue
                }
            }

            candidates.removeAll()
            let searchPaths = environment["PATH"]?
                .split(separator: ":").map(String.init) ?? []
            for path in searchPaths where !path.isEmpty {
                candidates.append((path as NSString).appendingPathComponent(requirement.command))
            }
            if let exe = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
                if let variable = requirement.variable {
                    environment[variable] = exe
                }
                continue
            }

            candidates.removeAll()
            for location in requirement.locations {
                candidates.append(TextFormatString.expand(location, variables: environment))
            }
            if let exe = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
                if let variable = requirement.variable {
                    environment[variable] = exe
                } else {
                    let parent = (exe as NSString).deletingLastPathComponent
                    environment["PATH", default: ""] += ":\(parent)"
                }
            } else {
                return (true, requirement)
            }
        }
        return (false, nil)
    }
}
