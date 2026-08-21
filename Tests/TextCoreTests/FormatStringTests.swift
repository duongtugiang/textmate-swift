import XCTest
@testable import TextCore

/// Port of `Frameworks/regexp/tests/t_format_string.cc`.
final class FormatStringTests: XCTestCase {

    private func replace(_ src: String, _ pattern: String, _ format: String) -> String {
        TextFormatString.replace(src, pattern: pattern, format: format)
    }

    func testFormatString() {
        XCTAssertEqual(replace("Résumé", ".+", "»${0:/asciify}«"), "»Resume«")
        XCTAssertEqual(replace("æbleGRØD", ".+", "»${0:/upcase}«"), "»ÆBLEGRØD«")
        XCTAssertEqual(replace("æbleGRØD", ".+", "»${0:/downcase}«"), "»æblegrød«")
        XCTAssertEqual(replace("æbleGRØD", ".+", "»${0:/asciify}«"), "»aebleGROD«")
        XCTAssertEqual(replace("æblegrød", ".+", "»${0:/capitalize}«"), "»Æblegrød«")
        XCTAssertEqual(replace("æblegrød", ".+", "»${0:/capitalize/asciify}«"), "»AEblegrod«")
    }

    func testCapitalize() {
        XCTAssertEqual(replace("this is a title", ".+", "${0:/capitalize}"), "This is a Title")
        XCTAssertEqual(replace("word-based capitalization", ".+", "${0:/capitalize}"), "Word-based Capitalization")
        XCTAssertEqual(replace("# 2014-08-22: it works now #", ".+", "${0:/capitalize}"), "# 2014-08-22: It Works Now #")
        XCTAssertEqual(replace("# 2014-08-22: it works now again #", ".+", "${0:/capitalize}"), "# 2014-08-22: It Works now Again #")
        XCTAssertEqual(replace("my NSTableView subclass", ".+", "${0:/capitalize}"), "My NSTableView Subclass")
        XCTAssertEqual(replace("This Is The Wrong", ".+", "${0:/capitalize}"), "This is the Wrong")
        XCTAssertEqual(replace("THIS IS THE WRONG", ".+", "${0:/capitalize}"), "This is the Wrong")
        XCTAssertEqual(replace("RSA", ".+", "${0:/capitalize}"), "Rsa")
    }

    func testVariables() {
        let variables = [
            "a": "hello",
            "b": " ",
            "c": "world",
            "d": "hell",
            "dir": "/path/to",
            "path": "/path/to/file",
        ]
        XCTAssertEqual(TextFormatString.expand("$a$b$c", variables: variables), "hello world")
        XCTAssertEqual(TextFormatString.expand("${a}${b}${c}", variables: variables), "hello world")
        XCTAssertEqual(TextFormatString.expand("${a/hello/hi/}${b}${c}", variables: variables), "hi world")
        XCTAssertEqual(TextFormatString.expand("${a/${d}/hi’y/}${b}${c}", variables: variables), "hi’yo world")
        XCTAssertEqual(TextFormatString.expand("${path/^.*\\///}", variables: variables), "file")
        XCTAssertEqual(TextFormatString.expand("${path/${dir}.//}", variables: variables), "file")
        XCTAssertEqual(TextFormatString.expand("${path/${dir}\\///}", variables: variables), "file")
    }

    func testLegacyConditions() {
        XCTAssertEqual(replace("foo bar", "(foo)? bar", "(?1:baz)"), "baz")
        XCTAssertEqual(replace("fud bar", "(foo)? bar", "(?1:baz)"), "fud")
        XCTAssertEqual(replace("fud bar", "(foo)? bar", "(?1:baz: buz)"), "fud buz")
        XCTAssertEqual(replace("foo bar", "(foo)? bar", "(?1:baz"), "(?1:baz")
        XCTAssertEqual(replace("foo bar", "(foo)? bar", "(?1:baz:"), "(?1:baz:")
        XCTAssertEqual(replace("foo bar", "(foo)? bar", "(?n:baz)"), "(?n:baz)")
        XCTAssertEqual(replace("foo bar", "(foo)? bar", "(?n:baz:)"), "(?n:baz:)")
    }

    func testEscapeFormatString() {
        XCTAssertEqual(TextFormatString.escape("\t\n\r\\q"), "\\t\\n\\r\\q")
        XCTAssertEqual(TextFormatString.expand(TextFormatString.escape("${var}"), variables: [:]), "${var}")
        XCTAssertEqual(TextFormatString.expand(TextFormatString.escape("foo\n"), variables: [:]), "foo\n")
        XCTAssertEqual(TextFormatString.expand(TextFormatString.escape("foo\\n"), variables: [:]), "foo\\n")
        XCTAssertEqual(TextFormatString.expand(TextFormatString.escape("\\No-Escape"), variables: [:]), "\\No-Escape")
        XCTAssertEqual(TextFormatString.expand(TextFormatString.escape("(?bla)"), variables: [:]), "(?bla)")
        XCTAssertEqual(TextFormatString.expand(TextFormatString.escape("Escape\\\\me"), variables: [:]), "Escape\\\\me")
        XCTAssertEqual(TextFormatString.expand(TextFormatString.escape("(?1:baz: buz)"), variables: [:]), "(?1:baz: buz)")
    }

    func testControlCodes() {
        XCTAssertEqual(TextFormatString.expand("\\t", variables: [:]), "\t")
        XCTAssertEqual(TextFormatString.expand("\\r", variables: [:]), "\r")
        XCTAssertEqual(TextFormatString.expand("\\n", variables: [:]), "\n")
        XCTAssertEqual(TextFormatString.expand("\\x", variables: [:]), "\\x")
        XCTAssertEqual(TextFormatString.expand("\\x{foo}", variables: [:]), "\\x{foo}")
        XCTAssertEqual(TextFormatString.expand("\\x{2014}", variables: [:]), "\u{2014}")
        XCTAssertEqual(TextFormatString.expand("\\x{20EF5}", variables: [:]), "\u{20EF5}")
        XCTAssertEqual(TextFormatString.expand("\\x{0010FFFF}", variables: [:]), "\u{10FFFF}")
        XCTAssertEqual(TextFormatString.expand("\\xc3\\x86blegr\\xC3\\xB8d", variables: [:]), "Æblegrød")
    }

    func testImplicitVariables() {
        // $1 from the root match must not be inherited by the inner format string
        XCTAssertEqual(replace("=", "(=+)", "${1/=(=)?(=)?/${2:?2:${1:?1:0}}/}"), "0")
        XCTAssertEqual(replace("==", "(=+)", "${1/=(=)?(=)?/${2:?2:${1:?1:0}}/}"), "1")
        XCTAssertEqual(replace("===", "(=+)", "${1/=(=)?(=)?/${2:?2:${1:?1:0}}/}"), "2")
    }
}
