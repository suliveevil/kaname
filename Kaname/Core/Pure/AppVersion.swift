import Foundation

/// The one spelling of the app's version, for every surface that shows it.
///
/// A build is identified by the source it was built from, not by a monotonic build number
/// that only repeats the marketing version. `scripts/stamp_commit.sh` writes the short
/// commit into `Info.plist` as `KanameCommit`; the parentheses carry it, suffix included
/// (`fe9e2c0-dirty` for a build from a modified tree).
///
/// A bundle built outside that script (an Xcode Run, a downloaded release without the key)
/// has no commit to show. It says `unknown` rather than falling back to `CFBundleVersion`:
/// the build number was the thing this format exists to stop displaying.
nonisolated enum AppVersion {
    /// The short form git itself prints: seven characters.
    static let shortCommitLength = 7

    /// `v<marketing version> (<short commit>)`, e.g. `v2.3.0 (66e5582)` or
    /// `v2.3.4 (fe9e2c0-dirty)`.
    static func display(shortVersion: String?, commit: String?) -> String {
        let version = trimmed(shortVersion) ?? "?"
        let hash = shortCommit(commit) ?? "unknown"
        return "v\(version) (\(hash))"
    }

    /// The short hash plus whatever the build stamped after it, or nil when there is no
    /// commit to shorten. Truncating the whole string to seven characters used to drop
    /// `-dirty`, so the About tab and the diagnostics report named different commits for
    /// the same bundle.
    static func shortCommit(_ commit: String?) -> String? {
        guard let commit = trimmed(commit) else { return nil }
        let hexDigits: Set<Character> = [
            "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
            "a", "b", "c", "d", "e", "f", "A", "B", "C", "D", "E", "F"
        ]
        let hash = commit.prefix(while: { hexDigits.contains($0) })
        guard !hash.isEmpty else { return commit }
        return String(hash.prefix(shortCommitLength)) + String(commit.dropFirst(hash.count))
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension Bundle {
    /// The version line every surface should show. Reads the bundle once so the About tab,
    /// the launch log, the diagnostics export and the crash report cannot drift apart.
    nonisolated var kanameVersionDisplay: String {
        AppVersion.display(
            shortVersion: object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            commit: object(forInfoDictionaryKey: "KanameCommit") as? String
        )
    }
}
