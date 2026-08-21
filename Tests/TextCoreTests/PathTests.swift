import XCTest
@testable import TextCore

/// Ported from the original TextMate `io/tests/t_path.cc` (roadmap 3.T2 /
/// issue #27). The C++ `NULL_STR` cases are degenerate nil-sentinel behavior
/// with no Swift equivalent and are omitted here (recorded in the matrix).
final class PathTests: XCTestCase {

    func testNormalize() {
        XCTAssertEqual(TextPath.normalize("//foo//"), "/foo")
        XCTAssertEqual(TextPath.normalize("/foo/././."), "/foo")
        XCTAssertEqual(TextPath.normalize("/foo/bar/fud/../../baz/.."), "/foo")
        XCTAssertEqual(TextPath.normalize("//foo/bar//.//fud/../../baz/..//."), "/foo")

        XCTAssertEqual(TextPath.normalize("foo/.."), "")
        XCTAssertEqual(TextPath.normalize("foo/../.."), "..")
        XCTAssertEqual(TextPath.normalize("foo/../../bar"), "../bar")
        XCTAssertEqual(TextPath.normalize("./bar"), "bar")
        XCTAssertEqual(TextPath.normalize("../bar"), "../bar")
    }

    func testExtensions() {
        XCTAssertEqual(TextPath.stripExtension("foo"), "foo")
        XCTAssertEqual(TextPath.stripExtension("foo.css.php"), "foo.css")
        XCTAssertEqual(TextPath.stripExtension("/foo.bar/foo.css.php"), "/foo.bar/foo.css")

        XCTAssertEqual(TextPath.stripExtensions("foo"), "foo")
        XCTAssertEqual(TextPath.stripExtensions("foo.css.php"), "foo")
        XCTAssertEqual(TextPath.stripExtensions("/foo.bar/foo.css.php"), "/foo.bar/foo")

        XCTAssertEqual(TextPath.extension("foo"), "")
        XCTAssertEqual(TextPath.extension("foo.css.php"), ".php")
        XCTAssertEqual(TextPath.extension("/foo.bar/foo.css.php"), ".php")

        XCTAssertEqual(TextPath.extensions("foo"), "")
        XCTAssertEqual(TextPath.extensions("foo.css.php"), ".css.php")
        XCTAssertEqual(TextPath.extensions("/foo.bar/foo.css.php"), ".css.php")
    }

    func testDotFiles() {
        XCTAssertEqual(TextPath.extensions(".profile"), ".profile")
        XCTAssertEqual(TextPath.stripExtensions(".profile"), "")

        XCTAssertEqual(TextPath.extensions("/home/me/.profile"), ".profile")
        XCTAssertEqual(TextPath.stripExtensions("/home/me/.profile"), "/home/me/")
    }

    func testDotInBasename() {
        let long = "(allan) ##textmate (103,+nt) Issues with 1.5.10? See h… 2.limechat"
        XCTAssertEqual(TextPath.extensions(long), ".limechat")
        XCTAssertEqual(TextPath.stripExtensions(long), "(allan) ##textmate (103,+nt) Issues with 1.5.10? See h… 2")

        XCTAssertEqual(TextPath.extensions("index.php4"), ".php4")
        XCTAssertEqual(TextPath.stripExtensions("index.php4"), "index")

        XCTAssertEqual(TextPath.extensions("TextMate.tar.bz2"), ".tar.bz2")
        XCTAssertEqual(TextPath.stripExtensions("TextMate.tar.bz2"), "TextMate")

        XCTAssertEqual(TextPath.extensions("TextMate_1.5.10.dmg"), ".dmg")
        XCTAssertEqual(TextPath.stripExtensions("TextMate_1.5.10.dmg"), "TextMate_1.5.10")

        XCTAssertEqual(TextPath.extensions("TextMate_1.5.10.tar.bz2"), ".tar.bz2")
        XCTAssertEqual(TextPath.stripExtensions("TextMate_1.5.10.tar.bz2"), "TextMate_1.5.10")
    }

    func testRank() {
        XCTAssertEqual(TextPath.rank("foo.css.php", "hp"), 0)
        XCTAssertGreaterThan(TextPath.rank("foo.css.php", "php"), 0)
        XCTAssertEqual(TextPath.rank("foo.css.php", "gphp"), 0)
        XCTAssertGreaterThan(TextPath.rank("foo.css.php", "css.php"), 0)
        XCTAssertGreaterThan(TextPath.rank("foo.css.php", "css.php"), TextPath.rank("foo.css.php", "php"))

        XCTAssertGreaterThan(TextPath.rank("foo_spec.rb", "rb"), 0)
        XCTAssertGreaterThan(TextPath.rank("foo_spec.rb", "spec.rb"), 0)
        XCTAssertGreaterThan(TextPath.rank("foo_spec.rb", "spec.rb"), TextPath.rank("foo_spec.rb", "rb"))

        XCTAssertGreaterThan(TextPath.rank("CMakeLists.txt", "txt"), 0)
        XCTAssertGreaterThan(TextPath.rank("CMakeLists.txt", "CMakeLists.txt"), 0)
        XCTAssertGreaterThan(TextPath.rank("CMakeLists.txt", "CMakeLists.txt"), TextPath.rank("CMakeLists.txt", "txt"))

        XCTAssertGreaterThan(TextPath.rank("/CMakeLists.txt", "txt"), 0)
        XCTAssertGreaterThan(TextPath.rank("/CMakeLists.txt", "CMakeLists.txt"), 0)
        XCTAssertGreaterThan(TextPath.rank("/CMakeLists.txt", "CMakeLists.txt"), TextPath.rank("/CMakeLists.txt", "txt"))
    }

    func testRelativeTo() {
        XCTAssertEqual(TextPath.relativeTo("/foo/bar/fud", "/foo"), "bar/fud")
        XCTAssertEqual(TextPath.relativeTo("/foo/bar/fud", "/foo/bar"), "fud")
        XCTAssertEqual(TextPath.relativeTo("/foo/fud", "/foo/bar"), "../fud")
        XCTAssertEqual(TextPath.relativeTo("/foo/baz/fud", "/foo/bar"), "../baz/fud")
    }

    func testPathComponents() {
        XCTAssertEqual(TextPath.name("/foo/bar/fud"), "fud")
        XCTAssertEqual(TextPath.parent("/foo/bar/fud"), "/foo/bar")
        XCTAssertEqual(TextPath.join("/foo/bar", "fud"), "/foo/bar/fud")

        XCTAssertEqual(TextPath.name("foo/bar/fud"), "fud")
        XCTAssertEqual(TextPath.parent("foo/bar/fud"), "foo/bar")
        XCTAssertEqual(TextPath.join("foo/bar", "fud"), "foo/bar/fud")
    }

    func testIsAbsolute() {
        XCTAssertFalse(TextPath.isAbsolute("../"))
        XCTAssertFalse(TextPath.isAbsolute("../foo"))
        XCTAssertFalse(TextPath.isAbsolute("./"))
        XCTAssertTrue(TextPath.isAbsolute("/."))
        XCTAssertFalse(TextPath.isAbsolute("/.."))
        XCTAssertFalse(TextPath.isAbsolute("/../"))
        XCTAssertFalse(TextPath.isAbsolute("/../tmp"))
        XCTAssertFalse(TextPath.isAbsolute("/./.."))
        XCTAssertFalse(TextPath.isAbsolute("/./../tmp"))
        XCTAssertTrue(TextPath.isAbsolute("/./foo"))
        XCTAssertTrue(TextPath.isAbsolute("//."))
        XCTAssertFalse(TextPath.isAbsolute("//../../foo"))
        XCTAssertTrue(TextPath.isAbsolute("//./foo"))
        XCTAssertTrue(TextPath.isAbsolute("/foo/.."))
        XCTAssertFalse(TextPath.isAbsolute("/foo/../.."))
        XCTAssertFalse(TextPath.isAbsolute("foo"))
    }

    func testIsParent() {
        XCTAssertTrue(TextPath.isChild("/foo/bar", of: "/foo/bar"))
        XCTAssertTrue(TextPath.isChild("/foo/bar/fud", of: "/foo/bar"))
        XCTAssertFalse(TextPath.isChild("/foo/barry", of: "/foo/bar"))
        XCTAssertFalse(TextPath.isChild("/foo/bar", of: "/foo/barry"))
    }

    func testWithTilde() {
        let home = TextPath.home()
        XCTAssertEqual(TextPath.withTilde(home), "~")
        XCTAssertEqual(TextPath.withTilde(home + "/"), "~/")
        XCTAssertEqual(TextPath.withTilde(home + "//"), "~/")
        XCTAssertEqual(TextPath.withTilde(home + "/./"), "~/")
        XCTAssertEqual(TextPath.withTilde(home + "./"), home + "./")
        XCTAssertEqual(TextPath.withTilde(TextPath.join(home, "foo")), "~/foo")
        XCTAssertEqual(TextPath.withTilde(TextPath.join(home, "foo") + "/"), "~/foo/")
        XCTAssertEqual(TextPath.withTilde("foo" + home), "foo" + home)
        XCTAssertEqual(TextPath.withTilde("/dummy"), "/dummy")
    }
}
