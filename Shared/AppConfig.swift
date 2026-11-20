import Foundation

/// Identifiers shared between the app and the widget extension.
/// The App Group must match the entitlements of both targets exactly.
///
/// `nonisolated`: plain constants with no mutable state, so there's no
/// reason for them to inherit the project's default MainActor isolation —
/// that default made them inaccessible from `AppIntent.perform()`, which
/// AppIntents runs outside the main actor regardless of this project's
/// build setting.
nonisolated enum AppConfig {
    static let appGroupID = "group.dev.rudek.aimeter"
    static let keychainService = "dev.rudek.aimeter"
    /// Keychain access group shared by app and widget so the widget can
    /// read credentials and refresh usage itself. The App Group doubles as
    /// the keychain group (see both targets' entitlements).
    static let keychainAccessGroup: String? = appGroupID
    static let refreshTaskID = "dev.rudek.aimeter.refresh"
    static let widgetKind = "AIMeterUsage"
    /// Single-window widget: shows one provider/window the user picks from
    /// the widget's own Edit Widget configuration.
    static let singleWidgetKind = "AIMeterSingleUsage"
    /// Large-only widget showing every connected account at once — no
    /// per-instance configuration, since there's nothing to pick.
    static let allAccountsWidgetKind = "AIMeterAllAccounts"
    /// The Watch's complications, one kind for every accessory family.
    static let watchWidgetKind = "AIMeterWatchUsage"
    /// iOS 18's control (Control Center, the Lock Screen, the Action
    /// button): one account's glance figure, a tap refreshing it.
    static let controlKind = "AIMeterControl"
    static let refreshInterval: TimeInterval = 15 * 60
    /// A snapshot older than this is flagged as stale in widgets.
    static let staleAfter: TimeInterval = 30 * 60
    /// Minimum interval between a widget's own timeline reloads,
    /// independent of the user's display cadence. WidgetKit budgets
    /// background refreshes (~a few dozen a day); requesting every 15 min
    /// exhausts that budget and the system stops refreshing the widget —
    /// then even ignores app-initiated `reloadAllTimelines()` until the
    /// budget replenishes (next day). This floor keeps the widget in
    /// budget; the app still pushes fresh data on foreground for active use.
    static let widgetRefreshFloor: TimeInterval = 30 * 60
}
