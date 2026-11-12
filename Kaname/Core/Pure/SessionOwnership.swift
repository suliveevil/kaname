import Foundation

/// A value that names one surface or injection session.
///
/// Tokens are deliberately opaque: callers capture one before an asynchronous hand-off and
/// ask the owner whether it is still current before changing visible state or posting input.
nonisolated struct SessionToken: Equatable, Sendable {
    fileprivate let rawValue: UInt64
}

/// Issues monotonically changing session tokens and rejects work owned by an older session.
nonisolated struct SessionOwnership {
    private(set) var current = SessionToken(rawValue: 0)

    /// Starts a new ownership epoch. Any token issued before this call is stale.
    @discardableResult
    mutating func begin() -> SessionToken {
        current = SessionToken(rawValue: current.rawValue &+ 1)
        return current
    }

    func owns(_ token: SessionToken) -> Bool {
        token == current
    }
}
