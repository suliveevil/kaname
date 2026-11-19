import Foundation

/// The actions Kaname accepts from outside its own process.
///
/// Both entry points — `kaname://` URLs and the AppleScript dictionary — resolve to this one
/// enum, so an action cannot be reachable from one and silently missing from the other. The
/// set is deliberately small: every case is parameterless, idempotent and presentation-only.
/// A URL scheme has no authentication and no reply channel, so anything that executes a menu
/// item, writes a setting, exports a file or resets data must not become a case here.
///
/// Pure by design: Foundation only, no AppKit and no `NSWorkspace`, which keeps the URL
/// whitelist inside the SwiftPM target where it can be tested (see AGENTS.md).
/// Explicitly `nonisolated`: the app target defaults to MainActor isolation, and the
/// AppleScript command class calls this from a `nonisolated` override. A stateless value
/// type has no reason to carry an actor anyway.
nonisolated enum AutomationAction: String, CaseIterable, Sendable {
    case showPanel
    case togglePanel
    case showSearch
    case toggleSurface
    case closeSurfaces
    case showSettings
    case showConflicts
    case showPermissions
    case showAbout

    /// The sdef command name. Cocoa scripting reports it as
    /// `NSScriptCommandDescription.commandName`, so the one `NSScriptCommand` subclass can
    /// serve every verb instead of needing one class per command.
    var scriptCommandName: String {
        switch self {
        case .showPanel: "show panel"
        case .togglePanel: "toggle panel"
        case .showSearch: "show search"
        case .toggleSurface: "toggle surface"
        case .closeSurfaces: "close surfaces"
        case .showSettings: "show settings"
        case .showConflicts: "show conflicts"
        case .showPermissions: "show permissions"
        case .showAbout: "show about"
        }
    }

    init?(scriptCommandName: String) {
        guard let match = Self.allCases.first(where: { $0.scriptCommandName == scriptCommandName }) else {
            return nil
        }
        self = match
    }
}

/// Parses `kaname://` URLs into an ``AutomationAction``.
///
/// The whitelist is closed: an unrecognised host, path, userinfo or port answers `nil`, and
/// the caller logs the refusal. Query strings are never interpreted — an automation action
/// takes no arguments, so `kaname://panel?from=browser` is the same request as
/// `kaname://panel`, and a future parameterised command must be added here explicitly rather
/// than smuggled in through a query key.
nonisolated enum AutomationURL {
    static let scheme = "kaname"

    /// Bounds the work done on an untrusted string and keeps log lines finite.
    static let maxLength = 256

    static func parse(_ url: URL) -> AutomationAction? {
        guard url.absoluteString.count <= maxLength else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == scheme else { return nil }
        // `kaname://panel@elsewhere` has host "elsewhere" and user "panel". Rejecting
        // userinfo and ports closes that class of spoofed authority before the switch.
        guard components.user == nil, components.password == nil, components.port == nil else {
            return nil
        }

        let path = normalizedPath(components.path)
        let host = (components.host ?? "").lowercased()
        // Join host and path into one segment list so `kaname://panel` and `kaname:panel`
        // (some launchers drop the authority slashes) resolve identically. A trailing
        // segment remains visible as `rest`, so `settings/conflicts/x` cannot be mistaken
        // for `settings/conflicts`.
        var segments = path.split(separator: "/").map(String.init)
        if !host.isEmpty { segments.insert(host, at: 0) }
        let key = segments.first ?? ""
        let rest = segments.dropFirst().joined(separator: "/")

        switch key {
        case "panel":
            return rest.isEmpty ? .showPanel : nil
        case "toggle-panel":
            return rest.isEmpty ? .togglePanel : nil
        case "search":
            return rest.isEmpty ? .showSearch : nil
        case "toggle-surface":
            return rest.isEmpty ? .toggleSurface : nil
        case "close":
            return rest.isEmpty ? .closeSurfaces : nil
        case "settings":
            switch rest {
            case "": return .showSettings
            case "conflicts": return .showConflicts
            default: return nil
            }
        case "permissions":
            return rest.isEmpty ? .showPermissions : nil
        case "about":
            return rest.isEmpty ? .showAbout : nil
        default:
            return nil
        }
    }

    /// Strips slashes and case, but keeps it as a single segment: `settings/conflicts/x`
    /// must not be mistaken for `settings/conflicts`.
    private static func normalizedPath(_ raw: String) -> String {
        raw.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
    }
}
