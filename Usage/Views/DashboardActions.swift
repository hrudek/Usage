import SwiftUI

@MainActor @Observable
final class DashboardActions {
    var showingSettings = false
    var settingsInColumns = false
    var showingConnect = false
    var refreshRequests = 0
    var detailBarHoldsActions = false

    func openSettings(inColumns: Bool) {
        settingsInColumns = inColumns
        showingSettings = true
    }

    func refresh(_ model: UsageModel) {
        refreshRequests += 1
        Task { await model.refreshAll() }
    }

    func addAccount() {
        showingConnect = true
    }
}

struct AccountSelection {
    let selectedID: String?
    let select: (String) -> Void
}

extension EnvironmentValues {
    @Entry var accountSelection: AccountSelection? = nil
}

struct DashboardPresentations: ViewModifier {
    let actions: DashboardActions
    @Environment(UsageModel.self) private var model
    @Environment(PreferencesModel.self) private var prefs
    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        @Bindable var actions = actions
        content
            #if DEBUG
            // `-UsageShowSettings YES` opens Settings at launch, to check or
            // capture it without a tap.
            .onAppear {
                if UserDefaults.standard.bool(forKey: "UsageShowSettings") {
                    actions.openSettings(inColumns: sizeClass == .regular)
                }
            }
            #endif
            .sheet(isPresented: presentsSettings(inColumns: false)) {
                SettingsSheet()
                    .withAppModels(model, prefs)
            }
            .fullScreenCover(isPresented: presentsSettings(inColumns: true)) {
                SettingsSplitView()
                    .withAppModels(model, prefs)
            }
            .sheet(isPresented: $actions.showingConnect) {
                ConnectAccountSheet()
                    .withAppModels(model, prefs)
            }
    }

    private func presentsSettings(inColumns: Bool) -> Binding<Bool> {
        Binding {
            actions.showingSettings && actions.settingsInColumns == inColumns
        } set: {
            actions.showingSettings = $0
        }
    }
}
