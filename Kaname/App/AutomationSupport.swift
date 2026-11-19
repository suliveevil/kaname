import AppKit
import Foundation

/// The one AppleScript command class behind all nine verbs in `Kaname.sdef`.
///
/// Cocoa scripting resolves `<cocoa class="KanameAutomationCommand"/>` with
/// `NSClassFromString`, so the Objective-C name must be spelled out: a Swift class without
/// an explicit `@objc(...)` name is module-qualified at runtime and the dictionary would
/// find nothing. The command name comes back through `commandDescription`, which lets one
/// class serve every verb and keeps the action set identical to the URL whitelist.
/// Cocoa scripting's two hooks are `nonisolated` in the SDK, while this target defaults to
/// MainActor isolation. The class and both overrides must opt out explicitly or Swift 6
/// refuses the override; the body hops back with `MainActor.assumeIsolated`.
@objc(KanameAutomationCommand)
nonisolated final class KanameAutomationCommand: NSScriptCommand {
    nonisolated override init(commandDescription: NSScriptCommandDescription) {
        super.init(commandDescription: commandDescription)
    }

    nonisolated override func performDefaultImplementation() -> Any? {
        let name = commandDescription.commandName
        guard let action = AutomationAction(scriptCommandName: name) else {
            Diag.warning(.ui, "automation: rejected unknown AppleScript command '\(name)'")
            return nil
        }
        // Apple events are dispatched on the main thread; `assumeIsolated` is the same
        // bridge the workspace observers use to get back onto the MainActor.
        MainActor.assumeIsolated {
            (NSApp.delegate as? AppDelegate)?.handleAutomation(action, source: "applescript")
        }
        return nil
    }
}

/// Maps an ``AutomationAction`` onto the engine. Both entry points call this one switch, so
/// there is no second copy of "what show panel means" to drift out of step.
///
/// `openAbout` is a closure because the About panel belongs to `AppDelegate`, not the
/// engine; keeping it out of `ShortcutEngine` avoids adding a UI dependency to Core.
@MainActor
enum AutomationRouter {
    static func perform(
        _ action: AutomationAction,
        engine: ShortcutEngine,
        openAbout: () -> Void
    ) {
        switch action {
        case .showPanel:
            // `ignoringOwnMenu` stays false: an external request must not cover a popup
            // belonging to the app in front. Only Kaname's own status menu earns that
            // exception (see StatusItemController.togglePanel).
            engine.activatePanel()
        case .togglePanel:
            engine.togglePinnedPanel()
        case .showSearch:
            engine.showSearch()
        case .toggleSurface:
            engine.toggleShortcutSurface()
        case .closeSurfaces:
            engine.closeSurfaces()
        case .showSettings:
            engine.showSettings()
        case .showConflicts:
            engine.showConflicts()
        case .showPermissions:
            engine.showPermissionsWindow()
        case .showAbout:
            openAbout()
        }
    }
}
