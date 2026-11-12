import XCTest
@testable import KanameCore

nonisolated final class InjectionPlanTests: XCTestCase {
    func testPrimaryTokenIsUsedWhenItIsMappable() {
        let chord = KeyChord.combo([.command], "c", alternates: ["v"])

        XCTAssertEqual(
            InjectionPlan.steps(for: chord),
            [InjectionStep(keyCode: 0x08, modifiers: [.command])]
        )
    }

    func testAlternateTokenIsUsedWhenPrimaryCannotBeMapped() {
        let chord = KeyChord.combo([.option, .shift], "unmapped-primary", alternates: ["unknown", "left"])

        XCTAssertEqual(
            InjectionPlan.steps(for: chord),
            [InjectionStep(keyCode: 0x7B, modifiers: [.option, .shift])]
        )
    }

    func testChordWithOnlyModifierStateHasNoInjectionPlan() {
        XCTAssertNil(InjectionPlan.steps(for: .modifiers([.command])))
        XCTAssertNil(InjectionPlan.steps(for: .empty))
    }

    func testUnmappableStepRejectsTheWholeSequence() {
        let chord = KeyChord([
            .combo([.command], "k"),
            .combo([.command], "not-a-virtual-key", alternates: ["still-not-a-key"])
        ])

        // In particular, the valid first step must not be posted on its own.
        XCTAssertNil(InjectionPlan.steps(for: chord))
    }

    func testEveryStepKeepsItsOwnModifiersAndOrder() {
        let chord = KeyChord([
            .combo([.command], "k"),
            .combo([.command, .shift], "c")
        ])

        XCTAssertEqual(
            InjectionPlan.steps(for: chord),
            [
                InjectionStep(keyCode: 0x28, modifiers: [.command]),
                InjectionStep(keyCode: 0x08, modifiers: [.command, .shift])
            ]
        )
    }
}
