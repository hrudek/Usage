import AppIntents
import WidgetKit
import UsageKit

/// Interactive widget button action: force a fetch for one account right
/// now, then reload the widget's timeline so the tap shows fresh data
/// within a couple seconds. Like every widget fetch it only reads the
/// stored login (`WidgetRefresher`).
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
        WidgetCenter.shared.reloadTimelines(ofKind: AppConfig.widgetKind)
        WidgetCenter.shared.reloadTimelines(ofKind: AppConfig.singleWidgetKind)
        WidgetCenter.shared.reloadTimelines(ofKind: AppConfig.allAccountsWidgetKind)
        if #available(iOS 18.0, *) {
            ControlCenter.shared.reloadControls(ofKind: AppConfig.controlKind)
        }
        return .result()
    }
}
