import XCTest
@testable import KanameCore

nonisolated final class AppVersionTests: XCTestCase {
    func testVersionShowsCommitInsteadOfBuildNumber() {
        XCTAssertEqual(
            AppVersion.display(shortVersion: "2.2.0", commit: "66e5582"),
            "v2.2.0 (66e5582)"
        )
    }

    func testMissingCommitSaysUnknownRatherThanBuildNumber() {
        XCTAssertEqual(AppVersion.display(shortVersion: "2.2.0", commit: nil), "v2.2.0 (unknown)")
        XCTAssertEqual(AppVersion.display(shortVersion: "2.2.0", commit: ""), "v2.2.0 (unknown)")
        XCTAssertEqual(AppVersion.display(shortVersion: "2.2.0", commit: "   "), "v2.2.0 (unknown)")
    }

    func testLongHashIsShortenedToSevenCharacters() {
        XCTAssertEqual(
            AppVersion.display(
                shortVersion: "2.2.0",
                commit: "66e5582f94839433043bc8cdcb450eb4a8e6bfb0"
            ),
            "v2.2.0 (66e5582)"
        )
        XCTAssertEqual(AppVersion.shortCommit("66e5582f94839433043bc8cdcb450eb4a8e6bfb0"), "66e5582")
        XCTAssertEqual(AppVersion.shortCommit("abc"), "abc")
        XCTAssertNil(AppVersion.shortCommit(nil))
    }

    /// `stamp_commit.sh` appends `-dirty` to the hash when the working tree is modified.
    /// Every surface that reads `KanameCommit` must keep that suffix, otherwise the About
    /// tab and the diagnostics report disagree about which commit was built.
    func testBuildSuffixSurvivesShortening() {
        XCTAssertEqual(
            AppVersion.display(shortVersion: "2.3.4", commit: "fe9e2c0-dirty"),
            "v2.3.4 (fe9e2c0-dirty)"
        )
        XCTAssertEqual(AppVersion.shortCommit("fe9e2c0-dirty"), "fe9e2c0-dirty")
        XCTAssertEqual(
            AppVersion.shortCommit("66e5582f94839433043bc8cdcb450eb4a8e6bfb0-dirty"),
            "66e5582-dirty"
        )
        XCTAssertEqual(AppVersion.shortCommit("unknown"), "unknown")
        XCTAssertEqual(AppVersion.shortCommit("unknown-dirty"), "unknown-dirty")
    }
}
