import XCTest
@testable import TextCore

/// Ports of `bundles/tests/t_query.cc` (4 cases) and
/// `bundles/tests/t_requirements.cc` (1 case) — issue #36 (4.T3).
final class BundleTests: XCTestCase {

    private static let baseEnvironment = """
    { name = 'Base Environment';
      settings = {
        shellVariables = (
          { name = 'TEST'; value = 'foo'; },
        );
      };
    }
    """

    private static let pathEnvironment = """
    { name = 'Path Environment';
      settings = {
        shellVariables = (
          { name = 'PATH'; value = '/usr/bin';                 },
          { name = 'PATH'; value = '$PATH:/bin';               },
          { name = 'PATH'; value = '$PATH:/tmp'; disabled = 1; },
          { name = 'PATH'; value = '$PATH:/sbin';              },
        );
      };
    }
    """

    private static let texEnvironment = """
    { name = 'TeX Environment';
      scope = 'text.tex';
      settings = {
        shellVariables = (
          { name = 'PATH'; value = '$PATH:/usr/texbin'; },
        );
      };
    }
    """

    private static let cxxEnvironment = """
    { name = 'C++ Environment';
      scope = 'source.c++';
      settings = {
        shellVariables = (
          { name = 'TEST'; value = '${TEST:+$TEST:}bar'; },
        );
      };
    }
    """

    private static let dialogEnvironment = """
    { name = 'Dialog Environment';
      settings = {
        shellVariables = (
          { name = 'DialogPath'; value = '${TM_DIALOG_BUNDLE_SUPPORT:?$TM_DIALOG_BUNDLE_SUPPORT/bin:*** Dialog bundle missing ***}'; },
        );
      };
      require = (
        { name = 'Dialog'; uuid = 'B0B94C92-1870-491C-A928-9528387EEACA'; },
      );
    }
    """

    private static let baseCommentEnvironment = """
    { name = 'Base Environment';
      settings = {
        shellVariables = (
          { name = 'TM_COMMENT_START';    value = '/*'; },
          { name = 'TM_COMMENT_STOP';     value = '*/'; },
          { name = 'TM_COMMENT_START_2';  value = '//'; },
          { name = 'TM_COMMENT_STYLE';    value = '$TM_BUNDLE_ITEM_NAME'; },
        );
      };
    }
    """

    private static let rubyCommentEnvironment = """
    { name = 'Ruby Environment';
      scope = 'source.ruby';
      settings = {
        shellVariables = (
          { name = 'TM_COMMENT_START';    value = '# '; },
          { name = 'TM_COMMENT_START_2';  value = '==begin'; },
          { name = 'TM_COMMENT_STOP_2';   value = '==end'; },
          { name = 'TM_COMMENT_STYLE';    value = '$TM_BUNDLE_ITEM_NAME'; },
        );
      };
    }
    """

    private static let baseSnippet = """
    { name = 'Base Snippet';
      keyEquivalent = '^p';
      tabTrigger = 'bla';
      content = 'foo';
    }
    """

    private static let cxxSnippet = """
    { name = 'C++ Snippet';
      keyEquivalent = '^p';
      tabTrigger = 'bla';
      scope = 'source.c++';
      content = 'bar';
    }
    """

    private static let disabledCxxSnippet = """
    { name = 'Disabled C++ Snippet';
      keyEquivalent = '^p';
      tabTrigger = 'bla';
      scope = 'source.c++';
      content = 'bar';
      isDisabled = 1;
    }
    """

    private static let trueWithLocation = """
    { name = 'TrueWithLocation';
      requiredCommands = (
        { command = 'true';
          locations = ( '/usr/bin/true' );
        },
      );
    }
    """

    private static let trueWithVariable = """
    { name = 'TrueWithVariable';
      requiredCommands = (
        { command = 'true';
          variable = 'TM_TRUE';
        },
      );
    }
    """

    private static let trueWithLocationAndVariable = """
    { name = 'TrueWithLocationAndVariable';
      requiredCommands = (
        { command = 'true';
          locations = ( '/usr/bin/true' );
          variable = 'TM_TRUE';
        },
      );
    }
    """

    private static let trueWithBadLocation = """
    { name = 'TrueWithBadLocation';
      requiredCommands = (
        { command = 'true';
          locations = ( '/foo/bar/true' );
        },
      );
    }
    """

    private static let trueWithBadLocationAndVariable = """
    { name = 'TrueWithBadLocationAndVariable';
      requiredCommands = (
        { command = 'true';
          locations = ( '/foo/bar/true' );
          variable = 'TM_TRUE';
        },
      );
    }
    """

    private static let dialogUUID = "B0B94C92-1870-491C-A928-9528387EEACA"

    /// The fixture index from `setup_fixtures()`.
    private func makeIndex() -> (BundleIndex, String) {
        let index = BundleIndex()
        index.add(kind: BundleItemKind.settings.rawValue, plistText: Self.baseEnvironment)
        index.add(kind: BundleItemKind.settings.rawValue, plistText: Self.baseCommentEnvironment)
        index.add(kind: BundleItemKind.settings.rawValue, plistText: Self.pathEnvironment)
        index.add(kind: BundleItemKind.settings.rawValue, plistText: Self.dialogEnvironment)
        index.add(kind: BundleItemKind.settings.rawValue, plistText: Self.texEnvironment)
        index.add(kind: BundleItemKind.settings.rawValue, plistText: Self.cxxEnvironment)
        index.add(kind: BundleItemKind.settings.rawValue, plistText: Self.rubyCommentEnvironment)
        index.add(kind: BundleItemKind.snippet.rawValue, plistText: Self.baseSnippet)
        index.add(kind: BundleItemKind.snippet.rawValue, plistText: Self.cxxSnippet)
        index.add(kind: BundleItemKind.snippet.rawValue, plistText: Self.disabledCxxSnippet)
        index.add(kind: BundleItemKind.command.rawValue, plistText: Self.trueWithLocation)
        index.add(kind: BundleItemKind.command.rawValue, plistText: Self.trueWithVariable)
        index.add(kind: BundleItemKind.command.rawValue, plistText: Self.trueWithLocationAndVariable)
        index.add(kind: BundleItemKind.command.rawValue, plistText: Self.trueWithBadLocation)
        index.add(kind: BundleItemKind.command.rawValue, plistText: Self.trueWithBadLocationAndVariable)

        // The "Dialog" bundle saved to a jail, with a Support directory
        // (mirrors `dialogBundle->save()` + `jail.mkdir(.../Support)`).
        let jail = NSTemporaryDirectory() + "textmateswift-bundle-\(UUID().uuidString)/"
        let bundlePath = jail + "Bundles/Dialog.tmbundle/info.plist"
        try? FileManager.default.createDirectory(
            atPath: jail + "Bundles/Dialog.tmbundle/Support",
            withIntermediateDirectories: true
        )
        index.add(kind: BundleItemKind.bundle.rawValue, plistText: "{ name = 'Dialog'; uuid = '\(Self.dialogUUID)'; }", path: bundlePath)
        return (index, jail)
    }

    // MARK: - t_query.cc

    func testEnvironmentFormatStrings() {
        let (index, _) = makeIndex()
        XCTAssertEqual(index.scopeVariables([:], scope: Scope(""))["TEST"], "foo")
        XCTAssertEqual(index.scopeVariables([:], scope: Scope("source.c++"))["TEST"], "foo:bar")
        XCTAssertEqual(index.scopeVariables([:], scope: Scope("source.any"))["TM_COMMENT_STYLE"], "Base Environment")
        XCTAssertEqual(index.scopeVariables([:], scope: Scope("source.ruby"))["TM_COMMENT_STYLE"], "Ruby Environment")

        XCTAssertEqual(index.scopeVariables([:], scope: Scope("text.plain"))["PATH"], "/usr/bin:/bin:/sbin")
        XCTAssertEqual(index.scopeVariables([:], scope: Scope("text.tex"))["PATH"], "/usr/bin:/bin:/sbin:/usr/texbin")
    }

    func testV1VariableShadowing() {
        let (index, _) = makeIndex()
        let baseEnv = index.scopeVariables([:], scope: Scope(""))
        XCTAssertEqual(baseEnv["TM_COMMENT_START"], "/*")
        XCTAssertEqual(baseEnv["TM_COMMENT_STOP"], "*/")
        XCTAssertEqual(baseEnv["TM_COMMENT_START_2"], "//")
        XCTAssertNil(baseEnv["TM_COMMENT_STOP_2"])

        let rubyEnv = index.scopeVariables([:], scope: Scope("source.ruby"))
        XCTAssertEqual(rubyEnv["TM_COMMENT_START"], "# ")
        XCTAssertNil(rubyEnv["TM_COMMENT_STOP"])
        XCTAssertEqual(rubyEnv["TM_COMMENT_START_2"], "==begin")
        XCTAssertEqual(rubyEnv["TM_COMMENT_STOP_2"], "==end")
    }

    func testScopeQuery() {
        let (index, _) = makeIndex()

        XCTAssertEqual(index.query(field: "keyEquivalent", value: "^p", scope: Scope("source.c++")).count, 1)
        XCTAssertEqual(index.query(
            field: "keyEquivalent", value: "^p", scope: Scope("source.c++"),
            kind: BundleItemKind.menuTypes, filter: false
        ).count, 2)
        XCTAssertEqual(index.query(
            field: "keyEquivalent", value: "^p", scope: Scope("source.c++"),
            kind: BundleItemKind.menuTypes, filter: false, includeDisabled: true
        ).count, 3)

        let anyTrigger = index.query(field: "tabTrigger", value: "bla", scope: Scope("source.any"))
        XCTAssertEqual(anyTrigger.count, 1)
        XCTAssertEqual(anyTrigger[0].name, "Base Snippet")

        let cxxTrigger = index.query(field: "tabTrigger", value: "bla", scope: Scope("source.c++"))
        XCTAssertEqual(cxxTrigger.count, 1)
        XCTAssertEqual(cxxTrigger[0].name, "C++ Snippet")

        let both = index.query(
            field: "tabTrigger", value: "bla", scope: Scope("source.c++"),
            kind: BundleItemKind.menuTypes, filter: false
        )
        XCTAssertEqual(both.count, 2)
        XCTAssertEqual(both[0].name, "C++ Snippet")
        XCTAssertEqual(both[1].name, "Base Snippet")
    }

    func testRequire() {
        let (index, _) = makeIndex()
        let dialogPath = index.scopeVariables([:], scope: Scope("text"))["DialogPath"] ?? ""
        let pathSuffix = "/Bundles/Dialog.tmbundle/Support/bin"
        XCTAssertTrue(dialogPath.hasSuffix(pathSuffix), "DialogPath = \(dialogPath)")
    }

    // MARK: - t_requirements.cc

    func testRequirements() {
        let (index, _) = makeIndex()
        let find: (String) -> BundleItem? = { name in
            index.query(field: "name", value: name).first
        }
        guard let location = find("TrueWithLocation"),
              let variable = find("TrueWithVariable"),
              let locationAndVariable = find("TrueWithLocationAndVariable"),
              let badLocation = find("TrueWithBadLocation"),
              let badLocationAndVariable = find("TrueWithBadLocationAndVariable") else {
            XCTFail("fixture items not found")
            return
        }

        var env = ["PATH": "/usr"]
        XCTAssertFalse(index.missingRequirement(for: location, environment: &env).missing)
        XCTAssertEqual(env["PATH"], "/usr:/usr/bin")

        env = ["PATH": "/usr"]
        XCTAssertTrue(index.missingRequirement(for: badLocation, environment: &env).missing)

        env = ["PATH": "/usr/bin"]
        XCTAssertFalse(index.missingRequirement(for: badLocation, environment: &env).missing)
        XCTAssertEqual(env["PATH"], "/usr/bin")

        env = ["PATH": "/usr"]
        XCTAssertTrue(index.missingRequirement(for: variable, environment: &env).missing)

        env = ["PATH": "/usr/bin"]
        XCTAssertFalse(index.missingRequirement(for: variable, environment: &env).missing)
        XCTAssertEqual(env["TM_TRUE"], "/usr/bin/true")
        XCTAssertEqual(env["PATH"], "/usr/bin")

        env = ["PATH": "/usr", "TM_TRUE": "/usr/bin/true"]
        XCTAssertFalse(index.missingRequirement(for: variable, environment: &env).missing)
        XCTAssertEqual(env["TM_TRUE"], "/usr/bin/true")
        XCTAssertEqual(env["PATH"], "/usr")

        env = ["PATH": "/usr", "TM_TRUE": "/usr/bin/true --help"]
        XCTAssertFalse(index.missingRequirement(for: variable, environment: &env).missing)
        XCTAssertEqual(env["TM_TRUE"], "/usr/bin/true --help")
        XCTAssertEqual(env["PATH"], "/usr")

        env = ["PATH": "/usr", "TM_TRUE": "/foo/bar/true"]
        XCTAssertFalse(index.missingRequirement(for: locationAndVariable, environment: &env).missing)
        XCTAssertEqual(env["TM_TRUE"], "/usr/bin/true")
        XCTAssertEqual(env["PATH"], "/usr")

        env = ["PATH": "/usr", "TM_TRUE": "/usr/bin/true --help"]
        XCTAssertFalse(index.missingRequirement(for: locationAndVariable, environment: &env).missing)
        XCTAssertEqual(env["TM_TRUE"], "/usr/bin/true --help")
        XCTAssertEqual(env["PATH"], "/usr")

        env = ["PATH": "/usr", "TM_TRUE": "/foo/bar/true"]
        XCTAssertTrue(index.missingRequirement(for: badLocationAndVariable, environment: &env).missing)

        env = ["PATH": "/usr", "TM_TRUE": "/usr/bin/true --help"]
        XCTAssertFalse(index.missingRequirement(for: badLocationAndVariable, environment: &env).missing)
        XCTAssertEqual(env["TM_TRUE"], "/usr/bin/true --help")
        XCTAssertEqual(env["PATH"], "/usr")

        env = ["PATH": "/usr/bin"]
        XCTAssertFalse(index.missingRequirement(for: badLocationAndVariable, environment: &env).missing)
        XCTAssertEqual(env["TM_TRUE"], "/usr/bin/true")
        XCTAssertEqual(env["PATH"], "/usr/bin")
    }
}
