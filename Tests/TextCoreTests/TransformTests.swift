import XCTest
@testable import TextCore

/// Ported verbatim from editor/tests/t_transform.cc.
final class TransformTests: XCTestCase {
    func testTransform() {
        XCTAssertEqual("dørgelbÆ",       TextTransform.transpose("Æblegrød"))
        XCTAssertEqual("dørgelbÆ\n",     TextTransform.transpose("Æblegrød\n"))
        XCTAssertEqual("bar, foo",       TextTransform.transpose("foo, bar"))
        XCTAssertEqual("bar, (foo)",     TextTransform.transpose("(foo), bar"))
        XCTAssertEqual("(bar), foo",     TextTransform.transpose("foo, (bar)"))
        XCTAssertEqual("(bar, foo)",     TextTransform.transpose("(foo, bar)"))
        XCTAssertEqual("bar + foo",      TextTransform.transpose("foo + bar"))
        XCTAssertEqual("'bar', 'foo'",   TextTransform.transpose("'foo', 'bar'"))
        XCTAssertEqual("bar() : foo()",  TextTransform.transpose("foo() : bar()"))
        XCTAssertEqual("('bar', 'foo')", TextTransform.transpose("('foo', 'bar')"))
        XCTAssertEqual("bar < foo",      TextTransform.transpose("foo < bar"))
        XCTAssertEqual("bar <= foo",     TextTransform.transpose("foo <= bar"))
        XCTAssertEqual("bar == foo",     TextTransform.transpose("foo == bar"))
        XCTAssertEqual("bar != foo",     TextTransform.transpose("foo != bar"))
        XCTAssertEqual("bar > foo",      TextTransform.transpose("foo > bar"))
        XCTAssertEqual("bar >= foo",     TextTransform.transpose("foo >= bar"))
    }
}
