import XCTest
@testable import TextCore

/// Ported verbatim from scope/tests/t_scope.cc, t_scope_selector.cc, t_utility.cc.
final class ScopeTests: XCTestCase {

    // MARK: t_scope.cc

    func testScopeAppend() {
        var scope = Scope("foo bar")
        XCTAssertEqual("bar", scope.back)
        scope.pushScope("some invalid..scope")
        XCTAssertEqual("some invalid..scope", scope.back)
        scope.popScope()
        XCTAssertEqual("foo bar", scope.description)
        scope.popScope()
        XCTAssertEqual("foo", scope.description)
    }

    func testEmptyScope() {
        XCTAssertTrue(Scope().isEmpty)
        XCTAssertTrue(Scope("").isEmpty)
        XCTAssertEqual(Scope(""), Scope())
    }

    func testHasPrefix() {
        XCTAssertTrue(Scope("").hasPrefix(Scope("")))
        XCTAssertFalse(Scope("").hasPrefix(Scope("foo")))
        XCTAssertTrue(Scope("foo").hasPrefix(Scope("")))
        XCTAssertFalse(Scope("foo").hasPrefix(Scope("foo bar")))
        XCTAssertTrue(Scope("foo bar").hasPrefix(Scope("foo bar")))
        XCTAssertTrue(Scope("foo bar baz").hasPrefix(Scope("foo bar")))
    }

    func testOperatorBool() {
        var scope = Scope("foo")
        let empty = Scope()
        XCTAssertFalse(scope.isEmpty)
        XCTAssertTrue(empty.isEmpty)
        scope.popScope()
        XCTAssertTrue(scope.isEmpty)
    }

    // MARK: t_scope_selector.cc

    func testChildSelector() {
        XCTAssertNotNil(ScopeSelector("foo fud").doesMatch(Scope("foo bar fud")))
        XCTAssertNil(ScopeSelector("foo > fud").doesMatch(Scope("foo bar fud")))
        XCTAssertNotNil(ScopeSelector("foo > foo > fud").doesMatch(Scope("foo foo fud")))
        XCTAssertNotNil(ScopeSelector("foo > foo > fud").doesMatch(Scope("foo foo fud fud")))
        XCTAssertNotNil(ScopeSelector("foo > foo > fud").doesMatch(Scope("foo foo fud baz")))

        XCTAssertNotNil(ScopeSelector("foo > foo fud > fud").doesMatch(Scope("foo foo bar fud fud")))
    }

    func testMixed() {
        XCTAssertNotNil(ScopeSelector("^ foo > bar").doesMatch(Scope("foo bar foo")))
        XCTAssertNil(ScopeSelector("foo > bar $").doesMatch(Scope("foo bar foo")))
        XCTAssertNotNil(ScopeSelector("bar > foo $").doesMatch(Scope("foo bar foo")))
        XCTAssertNotNil(ScopeSelector("foo > bar > foo $").doesMatch(Scope("foo bar foo")))
        XCTAssertNotNil(ScopeSelector("^ foo > bar > foo $").doesMatch(Scope("foo bar foo")))
        XCTAssertNotNil(ScopeSelector("bar > foo $").doesMatch(Scope("foo bar foo")))
        XCTAssertNotNil(ScopeSelector("^ foo > bar > baz").doesMatch(Scope("foo bar baz foo bar baz")))
        XCTAssertNil(ScopeSelector("^ foo > bar > baz").doesMatch(Scope("foo foo bar baz foo bar baz")))
    }

    func testDollar() {
        var dyn = Scope("foo bar")
        dyn.pushScope("dyn.selection")
        XCTAssertNotNil(ScopeSelector("foo bar$").doesMatch(dyn))
        XCTAssertNil(ScopeSelector("foo bar dyn$").doesMatch(dyn))
        XCTAssertNotNil(ScopeSelector("foo bar dyn").doesMatch(dyn))
    }

    func testAnchor() {
        XCTAssertNotNil(ScopeSelector("^ foo").doesMatch(Scope("foo bar")))
        XCTAssertNil(ScopeSelector("^ bar").doesMatch(Scope("foo bar")))
        XCTAssertNotNil(ScopeSelector("^ foo").doesMatch(Scope("foo bar foo")))
        XCTAssertNil(ScopeSelector("foo $").doesMatch(Scope("foo bar")))
        XCTAssertNotNil(ScopeSelector("bar $").doesMatch(Scope("foo bar")))
    }

    func testScopeSelector() {
        let textScope = Scope("text.html.markdown meta.paragraph.markdown markup.bold.markdown")
        let matchingSelectors = [
            "text.* markup.bold",
            "text markup.bold",
            "markup.bold",
            "text.html meta.*.markdown markup",
            "text.html meta.* markup",
            "text.html * markup",
            "text.html markup",
            "text markup",
            "markup",
            "text.html",
            "text",
        ]

        var lastRank = 1.0
        for selectorString in matchingSelectors {
            let selector = ScopeSelector(selectorString)
            guard let rank = selector.doesMatch(textScope) else {
                XCTFail("selector '\(selectorString)' should match \(textScope)")
                return
            }
            XCTAssertLessThan(rank, lastRank, "selector '\(selectorString)' rank should be below \(lastRank)")
            lastRank = rank
        }
    }

    func testRank() {
        let leftScope = Scope("text.html.php meta.embedded.block.php source.php comment.block.php")
        let rightScope = Scope("text.html.php meta.embedded.block.php source.php")
        let context = ScopeContext(left: leftScope, right: rightScope)

        let globalSelector = ScopeSelector("comment.block | L:comment.block")
        let phpSelector = ScopeSelector("L:source.php - string")

        XCTAssertNotNil(globalSelector.doesMatch(context))
        XCTAssertNotNil(phpSelector.doesMatch(context))
        if let phpRank = phpSelector.doesMatch(context), let globalRank = globalSelector.doesMatch(context) {
            XCTAssertLessThan(phpRank, globalRank)
        }
    }

    func testMatch() {
        func match(_ sel: String, _ scope: String) -> Bool {
            ScopeSelector(sel).doesMatch(Scope(scope)) != nil
        }

        XCTAssertTrue(match("foo", "foo.qux bar.quux.grault baz.corge.garply"))
        XCTAssertTrue(match("foo bar", "foo.qux bar.quux.grault baz.corge.garply"))
        XCTAssertTrue(match("foo bar baz", "foo.qux bar.quux.grault baz.corge.garply"))
        XCTAssertTrue(match("foo baz", "foo.qux bar.quux.grault baz.corge.garply"))
        XCTAssertTrue(match("foo.*", "foo.qux bar.quux.grault baz.corge.garply"))
        XCTAssertTrue(match("foo.qux", "foo.qux bar.quux.grault baz.corge.garply"))
        XCTAssertTrue(match("foo.qux baz.*.garply", "foo.qux bar.quux.grault baz.corge.garply"))
        XCTAssertTrue(match("bar", "foo.qux bar.quux.grault baz.corge.garply"))
        XCTAssertFalse(match("foo qux", "foo.qux bar.quux.grault baz.corge.garply"))
        XCTAssertFalse(match("foo.bar", "foo.qux bar.quux.grault baz.corge.garply"))
        XCTAssertFalse(match("foo.qux baz.garply", "foo.qux bar.quux.grault baz.corge.garply"))
        XCTAssertFalse(match("bar.*.baz", "foo.qux bar.quux.grault baz.corge.garply"))

        XCTAssertTrue(match("foo > bar", "foo bar baz bar baz"))
        XCTAssertTrue(match("bar > baz", "foo bar baz bar baz"))
        XCTAssertTrue(match("foo > bar baz", "foo bar baz bar baz"))
        XCTAssertTrue(match("foo bar > baz", "foo bar baz bar baz"))
        XCTAssertTrue(match("foo > bar > baz", "foo bar baz bar baz"))
        XCTAssertTrue(match("foo > bar bar > baz", "foo bar baz bar baz"))
        XCTAssertFalse(match("foo > bar > bar > baz", "foo bar baz bar baz"))

        XCTAssertTrue(match("baz $", "foo bar baz bar baz"))
        XCTAssertTrue(match("bar > baz $", "foo bar baz bar baz"))
        XCTAssertTrue(match("bar > baz $", "foo bar baz bar baz"))
        XCTAssertTrue(match("foo bar > baz $", "foo bar baz bar baz"))
        XCTAssertTrue(match("foo > bar > baz", "foo bar baz bar baz"))
        XCTAssertFalse(match("foo > bar > baz $", "foo bar baz bar baz"))
        XCTAssertFalse(match("bar $", "foo bar baz bar baz"))

        XCTAssertTrue(match("baz $", "foo bar baz bar baz dyn.qux"))
        XCTAssertTrue(match("bar > baz $", "foo bar baz bar baz dyn.qux"))
        XCTAssertTrue(match("bar > baz $", "foo bar baz bar baz dyn.qux"))
        XCTAssertTrue(match("foo bar > baz $", "foo bar baz bar baz dyn.qux"))
        XCTAssertFalse(match("foo > bar > baz $", "foo bar baz bar baz dyn.qux"))
        XCTAssertFalse(match("bar $", "foo bar baz bar baz dyn.qux"))

        XCTAssertTrue(match("^ foo", "foo bar foo bar baz"))
        XCTAssertTrue(match("^ foo > bar", "foo bar foo bar baz"))
        XCTAssertTrue(match("^ foo bar > baz", "foo bar foo bar baz"))
        XCTAssertTrue(match("^ foo > bar baz", "foo bar foo bar baz"))
        XCTAssertFalse(match("^ foo > bar > baz", "foo bar foo bar baz"))
        XCTAssertFalse(match("^ bar", "foo bar foo bar baz"))

        XCTAssertTrue(match("foo > bar > baz", "foo bar baz foo bar baz"))
        XCTAssertTrue(match("^ foo > bar > baz", "foo bar baz foo bar baz"))
        XCTAssertTrue(match("foo > bar > baz $", "foo bar baz foo bar baz"))
        XCTAssertFalse(match("^ foo > bar > baz $", "foo bar baz foo bar baz"))
    }

    // MARK: t_utility.cc

    func testSharedPrefix() {
        XCTAssertEqual("", Scope.sharedPrefix(Scope("foo"), Scope("bar")).description)
        XCTAssertEqual("foo", Scope.sharedPrefix(Scope("foo bar"), Scope("foo")).description)
        XCTAssertEqual("foo", Scope.sharedPrefix(Scope("foo"), Scope("foo bar")).description)
        XCTAssertEqual("foo bar", Scope.sharedPrefix(Scope("foo bar quux"), Scope("foo bar baz qux")).description)
    }

    func testXMLDifference() {
        let empty = Scope()
        let first = Scope("foo bar")
        let second = Scope("foo")
        let third = Scope("baz qux")

        XCTAssertEqual("<foo><bar>", Scope.xmlDifference(empty, first))
        XCTAssertEqual("</bar>", Scope.xmlDifference(first, second))
        XCTAssertEqual("</foo><baz><qux>", Scope.xmlDifference(second, third))
        XCTAssertEqual("</qux></baz>", Scope.xmlDifference(third, empty))
    }
}
