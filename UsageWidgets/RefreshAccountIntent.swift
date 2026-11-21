import AppIntents
import WidgetKit
import UsageKit

/// Interactive widget button action: force a fetch for one account right
/// now, then reload the widget's timeline so the tap shows fresh data
/// within a couple seconds. Like every widget fetch it renews an expired
/// login itself (`WidgetRefresher`).
///
/// Internal to the widget's own button, not a standalone Shortcuts/Siri
/// action.
struct RefreshAccountIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh"
    static var isDiscoverable: Bool = false

    @Parameter(title: "Account")
    var accountID: String

    init() {}

    init(accountID: String) {
        self.accountID = accountID
    }

    func perform() async throws -> some IntentResult {
        _ = await WidgetRefresher.refreshNow(accountID: accountID)
        await reloadWidgetsAndControl()
        return .result()
    }
}

/// The all-accounts widget's tap: fetch every connected account now (each
/// with its own 5 s floor), then reload the widget kinds.
struct RefreshAllAccountsIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh"
    static var isDiscoverable: Bool = false

    init() {}

    func perform() async throws -> some IntentResult {
        let accounts = AccountRegistryStore(suiteName: AppConfig.appGroupID)?.accounts() ?? []
        await withTaskGroup(of: Void.self) { group in
            for account in accounts {
                group.addTask { _ = await WidgetRefresher.refreshNow(accountID: account.accountID) }
            }
        }
        await reloadWidgetsAndControl()
        return .result()
    }
}

private func reloadWidgetsAndControl() {
        WidgetCenter.shared.reloadTimelines(ofKind: AppConfig.widgetKind)
        WidgetCenter.shared.reloadTimelines(ofKind: AppConfig.singleWidgetKind)
        WidgetCenter.shared.reloadTimelines(ofKind: AppConfig.allAccountsWidgetKind)
        if #available(iOS 18.0, *) {
            ControlCenter.shared.reloadControls(ofKind: AppConfig.controlKind)
        }
}
