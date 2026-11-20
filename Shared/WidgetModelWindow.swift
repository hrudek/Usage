import Foundation
import UsageKit

/// Whether one account's widgets show its per-model window (Claude's
/// Fable, say). On unless the user turned it off on the account's
/// settings page; only the app writes it, the widgets read it. The app's
/// own screens always show the window.
struct WidgetModelWindowPreference {
    let accountID: String
    private let defaults: UserDefaults

    /// `defaults` is the App Group suite; tests hand in a throwaway one.
    init(accountID: String, defaults: UserDefaults = UserDefaults(suiteName: AppConfig.appGroupID) ?? .standard) {
        self.accountID = accountID
        self.defaults = defaults
    }

    /// Stored only while off, so an account that never touched it has no key.
    var isShown: Bool {
        get { defaults.object(forKey: key) as? Bool ?? true }
        nonmutating set {
            if newValue {
                defaults.removeObject(forKey: key)
            } else {
                defaults.set(false, forKey: key)
            }
        }
    }

    /// Run on disconnect with the account's other keys.
    func clear() {
        defaults.removeObject(forKey: key)
    }

    private var key: String { "widget.showsModelWindow.\(accountID)" }
}

extension UsageSnapshot {
    /// The snapshot as `accountID`'s widgets draw it: without its
    /// per-model windows when that account hides them there. The slot
    /// then follows "Usage rows", as for a plan with no per-model limit.
    /// Display only, never saved.
    func forWidgets(
        of accountID: String,
        defaults: UserDefaults = UserDefaults(suiteName: AppConfig.appGroupID) ?? .standard
    ) -> UsageSnapshot {
        guard !WidgetModelWindowPreference(accountID: accountID, defaults: defaults).isShown else { return self }
        var shown = self
        shown.windows.removeAll {
            if case .modelSpecific = $0.kind { return true }
            return false
        }
        return shown
    }
}
