import Foundation

/// One fully resolved key stroke, ready for the AppKit injector to turn into CGEvents.
nonisolated struct InjectionStep: Equatable, Sendable {
    let keyCode: UInt16
    let modifiers: ModifierSet
}

/// Resolves a complete chord before the injector activates an app or posts its first key.
///
/// Menu scans can record alternate spellings for one physical key. The primary token wins
/// when it is mappable; otherwise the alternates are tried in their recorded order. A chord
/// with no key steps, or with any step that has no mappable spelling, has no injection plan.
/// Rejecting the whole sequence up front prevents a later bad step from leaving a partial
/// shortcut in the target app.
nonisolated enum InjectionPlan {
    static func steps(for chord: KeyChord) -> [InjectionStep]? {
        let keySteps = chord.steps.filter { !$0.isModifierOnly }
        guard !keySteps.isEmpty else { return nil }

        var resolved: [InjectionStep] = []
        resolved.reserveCapacity(keySteps.count)
        for step in keySteps {
            guard let keyCode = keyCode(for: step) else { return nil }
            resolved.append(InjectionStep(keyCode: keyCode, modifiers: step.modifiers))
        }
        return resolved
    }

    private static func keyCode(for step: KeyStep) -> UInt16? {
        let candidates = [step.key].compactMap { $0 } + step.alternates
        for token in candidates {
            if let keyCode = KeyMapper.keyCode(for: token) {
                return keyCode
            }
        }
        return nil
    }
}
