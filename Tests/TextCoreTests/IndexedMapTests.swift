import XCTest
@testable import TextCore

/// Port of `Frameworks/buffer/tests/t_indexed_map.cc` (10 test cases) against
/// the Swift `IndexedMap` port of `indexed_map_t`.
final class IndexedMapTests: XCTestCase {

    private static let testKeys: [Int] = [10, 20, 30, 40, 50]

    /// All permutations of `[10, 20, 30, 40, 50]` (120), matching the
    /// next_permutation loop in the original.
    private func permutations(of array: [Int]) -> [[Int]] {
        guard array.count > 1 else { return [array] }
        var result: [[Int]] = []
        for (index, value) in array.enumerated() {
            var rest = array
            rest.remove(at: index)
            for perm in permutations(of: rest) {
                result.append([value] + perm)
            }
        }
        return result
    }

    private func seedMap() -> IndexedMap<Int> {
        var map = IndexedMap<Int>()
        for i in 1...5 { map.set(i, i) }
        return map
    }

    // MARK: - Ported test cases

    func testBasic() {
        var map = IndexedMap<Bool>()
        var reference = Set<Int>()
        while reference.count < 2000 {
            reference.insert(Int.random(in: -0x7FFFFF...0x7FFFFF))
        }
        var keys = Array(reference).shuffled()
        for key in keys { map.set(key, true) }

        var sorted = map.pairs.map(\.key)
        XCTAssertEqual(sorted.count, reference.count)
        XCTAssertEqual(sorted, reference.sorted())

        keys.shuffle()
        for i in (keys.count >> 1)..<keys.count {
            map.remove(keys[i])
            reference.remove(keys[i])
            sorted = map.pairs.map(\.key)
            XCTAssertEqual(sorted.count, reference.count)
            XCTAssertEqual(sorted, reference.sorted())
        }
        keys = Array(keys[0..<(keys.count >> 1)]).sorted()

        sorted = map.pairs.map(\.key)
        XCTAssertEqual(sorted.count, keys.count)
        XCTAssertEqual(sorted, keys)

        for key in sorted.shuffled() { map.remove(key) }
        XCTAssertTrue(map.isEmpty)
    }

    func testChildCount() {
        for keys in permutations(of: Self.testKeys) {
            var map = IndexedMap<Bool>()
            for key in keys { map.set(key, true) }
            XCTAssertEqual(map.count, 5)

            for (i, expected) in [10, 20, 30, 40, 50].enumerated() {
                XCTAssertEqual(map.nth(i)?.key, expected)
                XCTAssertEqual(map.nth(i)?.index, i)
                XCTAssertEqual(map.find(expected).index, i)
            }

            map.remove(30)
            XCTAssertEqual(map.count, 4)
            for (i, expected) in [10, 20, 40, 50].enumerated() {
                XCTAssertEqual(map.nth(i)?.key, expected)
                XCTAssertEqual(map.nth(i)?.index, i)
                XCTAssertEqual(map.find(expected).index, i)
            }
        }
    }

    func testFind() {
        for keys in permutations(of: Self.testKeys) {
            var map = IndexedMap<Bool>()
            for key in keys { map.set(key, true) }

            for key in [9, 19, 29, 39, 49] { XCTAssertEqual(map.find(key).index, 5) }
            for (i, key) in [10, 20, 30, 40, 50].enumerated() { XCTAssertEqual(map.find(key).index, i) }
            for key in [11, 21, 31, 41, 51] { XCTAssertEqual(map.find(key).index, 5) }
        }
    }

    func testLowerBound() {
        for keys in permutations(of: Self.testKeys) {
            var map = IndexedMap<Bool>()
            for key in keys { map.set(key, true) }

            for (i, key) in [9, 19, 29, 39, 49].enumerated() { XCTAssertEqual(map.lowerBound(key).index, i) }
            for (i, key) in [10, 20, 30, 40, 50].enumerated() { XCTAssertEqual(map.lowerBound(key).index, i) }
            for (i, key) in [11, 21, 31, 41, 51].enumerated() { XCTAssertEqual(map.lowerBound(key).index, i + 1) }
        }
    }

    func testUpperBound() {
        for keys in permutations(of: Self.testKeys) {
            var map = IndexedMap<Bool>()
            for key in keys { map.set(key, true) }

            for (i, key) in [9, 19, 29, 39, 49].enumerated() { XCTAssertEqual(map.upperBound(key).index, i) }
            for (i, key) in [10, 20, 30, 40, 50].enumerated() { XCTAssertEqual(map.upperBound(key).index, i + 1) }
            for (i, key) in [11, 21, 31, 41, 51].enumerated() { XCTAssertEqual(map.upperBound(key).index, i + 1) }
        }
    }

    func testPreserve() {
        var nonPreserveLeft = seedMap()
        nonPreserveLeft.replace(from: 2, to: 4, len: 2, bindRight: false)
        XCTAssertEqual(nonPreserveLeft.pairs.map(\.key), [1, 2, 5])
        XCTAssertEqual(nonPreserveLeft.pairs.map(\.value), [1, 2, 5])

        var nonPreserveRight = seedMap()
        nonPreserveRight.replace(from: 2, to: 4, len: 2, bindRight: true)
        XCTAssertEqual(nonPreserveRight.pairs.map(\.key), [1, 4, 5])
        XCTAssertEqual(nonPreserveRight.pairs.map(\.value), [1, 4, 5])
    }

    func testBindRight() {
        for row in [[10, 20, 30], [20, 30, 40], [30, 40, 50], [40, 50, 60], [50, 60, 70]] {
            for keys in permutations(of: row) {
                var map = IndexedMap<Bool>()
                var expected: [Int] = []
                let pivot = 30, pad = 5
                for key in keys {
                    map.set(key, true)
                    expected.append(key < pivot ? key : key + pad)
                }
                map.replace(from: pivot, to: pivot, len: pad, bindRight: true)
                XCTAssertEqual(map.pairs.map(\.key), expected.sorted())
            }
        }
    }

    func testBindLeft() {
        for row in [[10, 20, 30], [20, 30, 40], [30, 40, 50], [40, 50, 60], [50, 60, 70]] {
            for keys in permutations(of: row) {
                var map = IndexedMap<Bool>()
                var expected: [Int] = []
                let pivot = 30, pad = 5
                for key in keys {
                    map.set(key, true)
                    expected.append(key <= pivot ? key : key + pad)
                }
                map.replace(from: pivot, to: pivot, len: pad, bindRight: false)
                XCTAssertEqual(map.pairs.map(\.key), expected.sorted())
            }
        }
    }

    func testDuplicate() {
        var map = IndexedMap<Bool>()
        let keys = [2, 7, 13, 15, 29].shuffled()
        for key in keys { map.set(key, true) }
        var values = map.pairs.map(\.value)
        XCTAssertEqual(values.count, keys.count)
        XCTAssertFalse(values.contains(false))

        for key in keys.shuffled() { map.set(key, false) }
        values = map.pairs.map(\.value)
        XCTAssertEqual(values.count, keys.count)
        XCTAssertFalse(values.contains(true))
    }

    func testBindLeftRight() {
        var map = IndexedMap<Bool>()
        for key in [2, 7, 13, 15, 29] { map.set(key, true) }

        for from in 0..<30 {
            for to in from..<30 {
                for len in 0..<10 {
                    var left = map
                    var right = map
                    left.replace(from: from, to: to, len: len, bindRight: false)
                    right.replace(from: from, to: to, len: len, bindRight: true)

                    var keysLeft: [Int] = []
                    var keysRight: [Int] = []
                    for key in [2, 7, 13, 15, 29] {
                        if !(from < key && key <= to) {
                            keysLeft.append(key > to ? key - (to - from) + len : key)
                        }
                        if !(from <= key && key < to) {
                            keysRight.append(key >= to ? key - (to - from) + len : key)
                        }
                    }
                    XCTAssertEqual(left.pairs.map(\.key), keysLeft.sorted(), "bindLeft from=\(from) to=\(to) len=\(len)")
                    XCTAssertEqual(right.pairs.map(\.key), keysRight.sorted(), "bindRight from=\(from) to=\(to) len=\(len)")
                }
            }
        }
    }
}
