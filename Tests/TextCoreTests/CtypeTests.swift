import XCTest
@testable import TextCore

/// Ported from TextMate Frameworks/text/tests/t_ctype.cc (east-asian width).
final class CtypeTests: XCTestCase {

    func testEastAsiaWidth() {
        XCTAssertFalse(TextCtype.isEastAsianWidth(0x10FF))
        XCTAssertTrue(TextCtype.isEastAsianWidth(0x1100))
        XCTAssertTrue(TextCtype.isEastAsianWidth(0x1101))
        XCTAssertTrue(TextCtype.isEastAsianWidth(0x33FE))
        XCTAssertTrue(TextCtype.isEastAsianWidth(0x33FF))
        XCTAssertTrue(TextCtype.isEastAsianWidth(0x3400))
        XCTAssertTrue(TextCtype.isEastAsianWidth(0x3401))
        XCTAssertTrue(TextCtype.isEastAsianWidth(0x3402))
        XCTAssertTrue(TextCtype.isEastAsianWidth(0x4DBE))
        XCTAssertTrue(TextCtype.isEastAsianWidth(0x4DBF))
        XCTAssertFalse(TextCtype.isEastAsianWidth(0x4DC0))
        XCTAssertFalse(TextCtype.isEastAsianWidth(0x4DC1))

        XCTAssertTrue(TextCtype.isEastAsianWidth(0x2E99))
        XCTAssertFalse(TextCtype.isEastAsianWidth(0x2E9A))
        XCTAssertTrue(TextCtype.isEastAsianWidth(0x2E9B))

        XCTAssertTrue(TextCtype.isEastAsianWidth(0x3FFFC))
        XCTAssertTrue(TextCtype.isEastAsianWidth(0x3FFFD))
        XCTAssertFalse(TextCtype.isEastAsianWidth(0x3FFFE))
    }

    /// Sanity-check a few interior range points to confirm the full table is intact.
    func testRangeInteriors() {
        XCTAssertTrue(TextCtype.isEastAsianWidth(0x4E00))   // start of CJK unified
        XCTAssertTrue(TextCtype.isEastAsianWidth(0x4E01))
        XCTAssertTrue(TextCtype.isEastAsianWidth(0x30A1))   // katakana range
        XCTAssertTrue(TextCtype.isEastAsianWidth(0x30A0))   // fixed singleton
        XCTAssertTrue(TextCtype.isEastAsianWidth(0x30FF))   // fixed singleton
    }
}
