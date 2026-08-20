import Foundation

/// A sorted key → value map, ported from `indexed_map_t` (original TextMate,
/// Frameworks/buffer/src/indexed_map.h). Supports index-based lookup (`nth`),
/// `find`/`lower_bound`/`upper_bound`, and the buffer-specific `replace`
/// operation that shifts keys across an edit.
///
/// The C++ original is a balanced tree; this port keeps sorted arrays
/// (O(log n) lookups, O(n) insert/remove) for correctness first. A tree-backed
/// upgrade is tracked in the roadmap.
public struct IndexedMap<Value: Equatable> {
    /// Result of `nth`/`find`/`lower_bound`/`upper_bound`.
    /// `index` is the position (== count when past the end); `key`/`value`
    /// are `nil` when the cursor is at the end.
    public struct Cursor {
        public let key: Int?
        public let value: Value?
        public let index: Int
    }

    private var keys: [Int] = []
    private var values: [Value] = []

    public init() {}

    public var count: Int { keys.count }
    public var isEmpty: Bool { keys.isEmpty }

    /// Sorted (key, value) pairs.
    public var pairs: [(key: Int, value: Value)] {
        zip(keys, values).map { (key: $0.0, value: $0.1) }
    }

    private func lowerBoundIndex(_ key: Int) -> Int {
        var low = 0, high = keys.count
        while low < high {
            let mid = (low + high) / 2
            if keys[mid] < key { low = mid + 1 } else { high = mid }
        }
        return low
    }

    private func upperBoundIndex(_ key: Int) -> Int {
        var low = 0, high = keys.count
        while low < high {
            let mid = (low + high) / 2
            if keys[mid] <= key { low = mid + 1 } else { high = mid }
        }
        return low
    }

    /// Inserts `value` at `key`, replacing any existing value.
    public mutating func set(_ key: Int, _ value: Value) {
        let index = lowerBoundIndex(key)
        if index < keys.count && keys[index] == key {
            values[index] = value
        } else {
            keys.insert(key, at: index)
            values.insert(value, at: index)
        }
    }

    public mutating func remove(_ key: Int) {
        let index = lowerBoundIndex(key)
        if index < keys.count && keys[index] == key {
            keys.remove(at: index)
            values.remove(at: index)
        }
    }

    /// Element at sorted position `i`; `nil` if out of range.
    public func nth(_ i: Int) -> Cursor? {
        guard i >= 0 && i < keys.count else { return nil }
        return Cursor(key: keys[i], value: values[i], index: i)
    }

    /// Cursor for `key`, or end (index == count) when absent — matching the
    /// original `indexed_map_t::find` which returns `end()` (whose `.index()`
    /// is the map size) for missing keys.
    public func find(_ key: Int) -> Cursor {
        let index = lowerBoundIndex(key)
        if index < keys.count && keys[index] == key {
            return Cursor(key: keys[index], value: values[index], index: index)
        }
        return Cursor(key: nil, value: nil, index: count)
    }

    /// First element with key >= `key` (end when none).
    public func lowerBound(_ key: Int) -> Cursor {
        let index = lowerBoundIndex(key)
        if index < keys.count {
            return Cursor(key: keys[index], value: values[index], index: index)
        }
        return Cursor(key: nil, value: nil, index: index)
    }

    /// First element with key > `key` (end when none).
    public func upperBound(_ key: Int) -> Cursor {
        let index = upperBoundIndex(key)
        if index < keys.count {
            return Cursor(key: keys[index], value: values[index], index: index)
        }
        return Cursor(key: nil, value: nil, index: index)
    }

    /// Applies an edit of `[from, to)` becoming length `len`.
    /// - `bindRight == true`  (preserve right): keys in `[from, to)` are dropped;
    ///   keys `>= to` shift by `len - (to - from)`.
    /// - `bindRight == false` (preserve left): keys in `(from, to]` are dropped;
    ///   keys `> to` shift by `len - (to - from)`.
    public mutating func replace(from: Int, to: Int, len: Int, bindRight: Bool) {
        var newKeys: [Int] = []
        var newValues: [Value] = []
        let delta = len - (to - from)
        for (key, value) in zip(keys, values) {
            if bindRight {
                if key >= to {
                    newKeys.append(key + delta); newValues.append(value)
                } else if key < from {
                    newKeys.append(key); newValues.append(value)
                }
            } else {
                if key > to {
                    newKeys.append(key + delta); newValues.append(value)
                } else if key <= from {
                    newKeys.append(key); newValues.append(value)
                }
            }
        }
        keys = newKeys
        values = newValues
    }
}
