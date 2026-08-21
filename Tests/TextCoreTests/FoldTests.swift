import XCTest
@testable import TextCore

/// Tests for the fold engine (4.S3 / issue #30) — the `foldable_ranges`
/// algorithm and the default indented-block marker detection.
final class FoldTests: XCTestCase {

    func testIndentedBlockFolding() {
        let lines = [
            "func foo() {",
            "    let x = 1",
            "    let y = 2",
            "}",
            "func bar() {",
            "    let z = 3",
            "}",
        ]
        let info = TextFolds.lineInfo(lines: lines, startPattern: nil, stopPattern: nil)
        let ranges = TextFolds.foldableRanges(info)
        // Block 1: marker line 1, hides line 2. Block 2: marker line 5, no
        // hidden lines (single-line block) → dropped by the C++ guard.
        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual(ranges[0].lowerBound, 1)
        XCTAssertEqual(ranges[0].upperBound - 1, 2)
    }

    func testEqualIndentBlock() {
        // Equal-indent block lines must NOT close the block (the marker's
        // closing level is the parent's indent).
        let lines = ["def f():", "    a", "    b", "    c", "g()"]
        let info = TextFolds.lineInfo(lines: lines, startPattern: nil, stopPattern: nil)
        let ranges = TextFolds.foldableRanges(info)
        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual(ranges[0].lowerBound, 1)
        XCTAssertEqual(ranges[0].upperBound - 1, 3)
    }

    func testNestedIndentedBlocks() {
        let lines = [
            "def outer():",
            "    def inner():",
            "        x = 1",
            "        y = 2",
            "    z = 3",
            "w = 4",
        ]
        let info = TextFolds.lineInfo(lines: lines, startPattern: nil, stopPattern: nil)
        let ranges = TextFolds.foldableRanges(info)
        // Outer (1 → hides 2...4) and inner (2 → hides 3), sorted by start
        // line like the C++ — both kept.
        XCTAssertEqual(ranges.count, 2)
        XCTAssertEqual(ranges[0].lowerBound, 1)
        XCTAssertEqual(ranges[0].upperBound - 1, 4)
        XCTAssertEqual(ranges[1].lowerBound, 2)
        XCTAssertEqual(ranges[1].upperBound - 1, 3)
    }

    func testExplicitBraceMarkers() {
        let lines = ["func a() {", "  x", "}", "func b() {", "  y", "}"]
        let info = TextFolds.lineInfo(lines: lines, startPattern: "\\{", stopPattern: "\\}")
        let ranges = TextFolds.foldableRanges(info)
        XCTAssertEqual(ranges.count, 2)
        XCTAssertEqual(ranges[0].lowerBound, 0)
        XCTAssertEqual(ranges[0].upperBound - 1, 1)
        XCTAssertEqual(ranges[1].lowerBound, 3)
        XCTAssertEqual(ranges[1].upperBound - 1, 4)
    }

    func testLeadingIndentTabs() {
        XCTAssertEqual(TextFolds.leadingIndent("    x", tabSize: 4), 4)
        XCTAssertEqual(TextFolds.leadingIndent("\t x", tabSize: 4), 5)
        XCTAssertEqual(TextFolds.leadingIndent("\t\tx", tabSize: 4), 8)
        XCTAssertEqual(TextFolds.leadingIndent("x", tabSize: 4), 0)
        XCTAssertEqual(TextFolds.leadingIndent("", tabSize: 4), 0)
    }
}
