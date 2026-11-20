import Foundation

/// What the app needs from any provider's credential storage, whatever the
/// credential type: a way to remove it on disconnect. Provider-specific
/// sources (`ClaudeCredentialSource`) refine this with their own typed
/// `load`/`save`; the app's `RefreshService` holds only this, so
/// disconnecting never has to know which provider it's disconnecting.
public protocol CredentialStore: Sendable {
    /// Removes the stored credentials for this account.
    func clear() throws
}
