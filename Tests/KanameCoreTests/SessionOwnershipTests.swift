import XCTest
@testable import KanameCore

nonisolated final class SessionOwnershipTests: XCTestCase {
    func testOnlyTheNewestSessionOwnsItsToken() {
        var ownership = SessionOwnership()
        let panel = ownership.begin()
        XCTAssertTrue(ownership.owns(panel))

        let search = ownership.begin()
        XCTAssertFalse(ownership.owns(panel))
        XCTAssertTrue(ownership.owns(search))
    }

    func testStartingAnotherSessionDoesNotRestoreAnOlderToken() {
        var ownership = SessionOwnership()
        let first = ownership.begin()
        let second = ownership.begin()
        let third = ownership.begin()

        XCTAssertFalse(ownership.owns(first))
        XCTAssertFalse(ownership.owns(second))
        XCTAssertTrue(ownership.owns(third))
    }
}
