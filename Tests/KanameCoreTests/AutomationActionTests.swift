import XCTest
@testable import KanameCore

nonisolated final class AutomationActionTests: XCTestCase {

    // MARK: - URL whitelist

    func testEveryActionHasAKnownURL() {
        let expected: [String: AutomationAction] = [
            "kaname://panel": .showPanel,
            "kaname://toggle-panel": .togglePanel,
            "kaname://search": .showSearch,
            "kaname://toggle-surface": .toggleSurface,
            "kaname://close": .closeSurfaces,
            "kaname://settings": .showSettings,
            "kaname://settings/conflicts": .showConflicts,
            "kaname://permissions": .showPermissions,
            "kaname://about": .showAbout
        ]
        XCTAssertEqual(expected.count, AutomationAction.allCases.count)
        for (raw, action) in expected {
            XCTAssertEqual(AutomationURL.parse(URL(string: raw)!), action, raw)
        }
    }

    /// Apple's `open` and several launchers hand over `kaname:panel` without the `//`.
    func testSchemeOnlyFormResolvesIdentically() {
        XCTAssertEqual(AutomationURL.parse(URL(string: "kaname:panel")!), .showPanel)
        XCTAssertEqual(AutomationURL.parse(URL(string: "kaname:settings/conflicts")!), .showConflicts)
    }

    func testSchemeAndHostAreCaseInsensitive() {
        XCTAssertEqual(AutomationURL.parse(URL(string: "KANAME://PANEL")!), .showPanel)
        XCTAssertEqual(AutomationURL.parse(URL(string: "Kaname://Settings/Conflicts")!), .showConflicts)
    }

    /// A query is never interpreted: these actions take no arguments.
    func testQueryIsIgnoredNotParsed() {
        XCTAssertEqual(AutomationURL.parse(URL(string: "kaname://panel?from=browser&run=rm")!), .showPanel)
        XCTAssertEqual(AutomationURL.parse(URL(string: "kaname://settings#conflicts")!), .showSettings)
        XCTAssertEqual(AutomationURL.parse(URL(string: "kaname://settings/conflicts?x=1")!), .showConflicts)
    }

    // MARK: - Refusals

    func testOtherSchemesAreRejected() {
        for raw in ["https://panel", "file:///etc/passwd", "kaname2://panel", "://panel", "panel"] {
            guard let url = URL(string: raw) else { continue }
            XCTAssertNil(AutomationURL.parse(url), raw)
        }
    }

    func testUnknownHostAndExtraSegmentsAreRejected() {
        for raw in [
            "kaname://",
            "kaname://quit",
            "kaname://perform",
            "kaname://panel/close",
            "kaname://settings/conflicts/delete",
            "kaname://settings/permissions",
            "kaname:///panel/../quit"
        ] {
            XCTAssertNil(AutomationURL.parse(URL(string: raw)!), raw)
        }
    }

    /// `kaname://panel@evil.example` has host `evil.example` and user `panel`; without this
    /// guard a crafted URL could name a different authority while looking like ours.
    func testUserinfoAndPortAreRejected() {
        XCTAssertNil(AutomationURL.parse(URL(string: "kaname://panel@evil.example")!))
        XCTAssertNil(AutomationURL.parse(URL(string: "kaname://user:pass@panel")!))
        XCTAssertNil(AutomationURL.parse(URL(string: "kaname://panel:8080")!))
    }

    func testOverlongURLIsRejected() {
        let raw = "kaname://panel?" + String(repeating: "a", count: AutomationURL.maxLength)
        XCTAssertNil(AutomationURL.parse(URL(string: raw)!))
    }

    func testEmptyAndMalformedURLsAreRejected() {
        for raw in ["kaname:", "", "  "] {
            guard let url = URL(string: raw) else { continue }
            XCTAssertNil(AutomationURL.parse(url), raw)
        }
    }

    // MARK: - AppleScript terminology

    func testScriptCommandNamesRoundTrip() {
        for action in AutomationAction.allCases {
            XCTAssertEqual(AutomationAction(scriptCommandName: action.scriptCommandName), action)
        }
    }

    func testEveryScriptCommandNameIsUnique() {
        let names = AutomationAction.allCases.map(\.scriptCommandName)
        XCTAssertEqual(Set(names).count, names.count)
    }

    func testUnknownScriptCommandNamesAreRejected() {
        XCTAssertNil(AutomationAction(scriptCommandName: "quit"))
        XCTAssertNil(AutomationAction(scriptCommandName: "run menu item"))
        XCTAssertNil(AutomationAction(scriptCommandName: ""))
    }

    /// The two entry points must expose exactly the same set. A new case added without a
    /// URL spelling fails here instead of becoming an AppleScript-only command.
    func testActionSetMatchesTheDocumentedURLSet() {
        XCTAssertEqual(AutomationAction.allCases.count, 9)
    }
}
