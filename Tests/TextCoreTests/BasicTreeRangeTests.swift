import XCTest
@testable import TextCore

/// Re-expressed from layout/tests/t_basic_tree_range.cc: the C++ position-keyed
/// range tree maps onto Buffer edits where each key is an absolute byte offset.
/// The tree's `set`/`unset` place/remove a zero-width marker at a position
/// without shifting neighbours — the byte equivalent is replacing the space at
/// that offset with `X` (and back). Only `adjust` shifts: inserting/removing
/// `distance` bytes at `pos` moves every marker at/after `pos`, exactly like the
/// C++ annotation update. An array oracle drives the same operations so the
/// engine is checked against a model.
final class BasicTreeRangeTests: XCTestCase {
    private func markerPositions(_ bytes: [UInt8]) -> [Int] {
        bytes.enumerated().compactMap { $0.element == 0x58 ? $0.offset : nil }
    }

    /// set(pos): the marker occupies position `pos` without shifting (C++ set).
    private func set(_ buffer: inout Buffer, _ oracle: inout [UInt8], at pos: Int) {
        buffer.replace(pos..<(pos + 1), with: "X")
        oracle[pos] = 0x58
    }

    /// unset(pos): remove the marker without shifting (C++ unset).
    private func unset(_ buffer: inout Buffer, _ oracle: inout [UInt8], at pos: Int) {
        buffer.replace(pos..<(pos + 1), with: " ")
        oracle[pos] = 0x20
    }

    /// adjust(pos, d): shift markers at/after `pos` by `d` (C++ adjust).
    private func adjust(_ buffer: inout Buffer, _ oracle: inout [UInt8], at pos: Int, by distance: Int) {
        if distance > 0 {
            let spaces = [UInt8](repeating: 0x20, count: distance)
            buffer.insert(String(decoding: spaces, as: UTF8.self), at: pos)
            oracle.insert(contentsOf: spaces, at: pos)
        } else {
            let amount = -distance
            buffer.erase((pos - amount)..<pos)
            oracle.removeSubrange((pos - amount)..<pos)
        }
    }

    func testAdjustment() {
        // Padding so positions 20/30 exist (a byte buffer can't hold a marker
        // beyond its end, unlike the C++ virtual-key tree).
        var buffer = Buffer(String(repeating: " ", count: 60))
        var oracle: [UInt8] = Array(repeating: 0x20, count: 60)

        set(&buffer, &oracle, at: 20)
        set(&buffer, &oracle, at: 30)

        adjust(&buffer, &oracle, at: 15, by: 5) // 20 → 25, 30 → 35
        adjust(&buffer, &oracle, at: 25, by: 5) // 25 → 30, 35 → 40
        adjust(&buffer, &oracle, at: 35, by: 5) // 30 → 30, 40 → 45
        adjust(&buffer, &oracle, at: 45, by: 5) // 30 → 30, 45 → 50
        adjust(&buffer, &oracle, at: 55, by: 5) // 30 → 30, 50 → 50

        XCTAssertEqual(buffer.bytes, oracle)
        XCTAssertEqual(markerPositions(buffer.bytes), [30, 50])

        adjust(&buffer, &oracle, at: 60, by: -5) // 30 → 30, 50 → 50
        adjust(&buffer, &oracle, at: 50, by: -5) // 30 → 30, 50 → 45
        adjust(&buffer, &oracle, at: 40, by: -5) // 30 → 30, 45 → 40
        adjust(&buffer, &oracle, at: 30, by: -5) // 30 → 25, 40 → 35
        adjust(&buffer, &oracle, at: 20, by: -5) // 25 → 20, 35 → 30

        XCTAssertEqual(buffer.bytes, oracle)
        XCTAssertEqual(markerPositions(buffer.bytes), [20, 30])
    }

    func testRangeTree() {
        var rng = SplitMix64(seed: 0xBEEF)
        var keys = Set<Int>()
        while keys.count < 32 {
            keys.insert(Int(rng.next() % 5000))
        }

        // Padding covers every possible marker position.
        var buffer = Buffer(String(repeating: " ", count: 6000))
        var oracle: [UInt8] = Array(repeating: 0x20, count: 6000)

        // set each key (shuffled order, like the C++ random shuffle)
        var shuffled = Array(keys)
        for j in stride(from: shuffled.count - 1, through: 1, by: -1) {
            let k = Int(rng.next() % UInt64(j + 1))
            shuffled.swapAt(j, k)
        }
        for key in shuffled {
            set(&buffer, &oracle, at: key)
        }
        XCTAssertEqual(buffer.bytes, oracle)
        XCTAssertEqual(markerPositions(buffer.bytes), keys.sorted())

        // adjust one key by +200; all markers remain findable
        let pos = shuffled[0]
        adjust(&buffer, &oracle, at: pos, by: 200)
        XCTAssertEqual(buffer.bytes, oracle)
        XCTAssertEqual(markerPositions(buffer.bytes).count, 32)

        // erase half the markers (at their shifted positions)
        var remaining = Array(keys)
        for j in stride(from: remaining.count - 1, through: 1, by: -1) {
            let k = Int(rng.next() % UInt64(j + 1))
            remaining.swapAt(j, k)
        }
        for key in remaining[(remaining.count / 2)...] {
            unset(&buffer, &oracle, at: key >= pos ? key + 200 : key)
        }
        XCTAssertEqual(buffer.bytes, oracle)
        XCTAssertEqual(markerPositions(buffer.bytes).count, 16)

        // erase the rest → no markers remain (padding spaces stay)
        for key in remaining[..<(remaining.count / 2)] {
            unset(&buffer, &oracle, at: key >= pos ? key + 200 : key)
        }
        XCTAssertEqual(buffer.bytes, oracle)
        XCTAssertTrue(markerPositions(buffer.bytes).isEmpty)
    }
}
