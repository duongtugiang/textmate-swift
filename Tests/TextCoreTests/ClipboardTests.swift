import XCTest
@testable import TextCore

/// Ported verbatim from editor/tests/t_clipboard.cc.
final class ClipboardTests: XCTestCase {
    func testEmpty() {
        let cb = Clipboard()

        XCTAssertTrue(cb.isEmpty)
        XCTAssertNil(cb.previous())
        XCTAssertNil(cb.current)
        XCTAssertNil(cb.next())
    }

    func testNonEmpty() {
        let cb = Clipboard()

        cb.push("foo")
        cb.push("bar")
        cb.push("fud")

        XCTAssertEqual(cb.current, "fud")
        XCTAssertEqual(cb.previous(), "bar")
        XCTAssertEqual(cb.previous(), "foo")
        XCTAssertNil(cb.previous())
        XCTAssertEqual(cb.next(), "bar")
        XCTAssertEqual(cb.next(), "fud")
        XCTAssertNil(cb.next())
    }
}
