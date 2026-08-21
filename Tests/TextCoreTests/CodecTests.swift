import XCTest
@testable import TextCore

/// Ported from TextMate Frameworks/text/tests/t_decode.cc + t_encode.cc.
final class CodecTests: XCTestCase {

    func testDecodeEntities() {
        XCTAssertEqual(TextCodec.decodeEntities("Hello world"), "Hello world")
        XCTAssertEqual(TextCodec.decodeEntities("Hello&nbsp;world"), "Hello\u{A0}world")
        XCTAssertEqual(TextCodec.decodeEntities("Hello &quot;world&quot;"), "Hello \"world\"")
        XCTAssertEqual(TextCodec.decodeEntities("Hello &lt;world&gt;"), "Hello <world>")
        XCTAssertEqual(TextCodec.decodeEntities("Hello &lt-world&gt;"), "Hello &lt-world>")
        XCTAssertEqual(TextCodec.decodeEntities("Hello &lt;world&gt-"), "Hello <world&gt-")
        XCTAssertEqual(TextCodec.decodeEntities("&AElig;blegr&oslash;d&hellip;"), "Æblegrød…")
    }

    func testDecodeURL() {
        XCTAssertEqual(TextCodec.decodeURLPart("ActionScript%203%2BR.tbz"), "ActionScript 3+R.tbz")
        XCTAssertEqual(TextCodec.decodeURLPart("%C3%86blegr%C3%B8d"), "Æblegrød")
        XCTAssertEqual(TextCodec.decodeURLPart("foo%2Bbar"), "foo+bar")
        XCTAssertEqual(TextCodec.decodeURLPart("foo+bar"), "foo bar")
    }

    func testEncodeURL() {
        XCTAssertEqual("http://host/" + TextCodec.encodeURLPart("æblegrød.html"), "http://host/%C3%A6blegr%C3%B8d.html")
        XCTAssertEqual(TextCodec.encodeURLPart("http://example?a=b&c=d"), "http%3A%2F%2Fexample%3Fa%3Db%26c%3Dd")
        XCTAssertEqual(TextCodec.encodeURLPart("me@example.org"), "me%40example.org")
        XCTAssertEqual("file://localhost" + TextCodec.encodeURLPart("/foo/bar/file name.txt", excluding: "/"), "file://localhost/foo/bar/file%20name.txt")
    }
}
