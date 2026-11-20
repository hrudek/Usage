import SwiftUI

enum SettingsSelection: Hashable {
    case account(String)
    case group(SettingsGroup)
}

/// Settings at a regular width (iPad, an unfolded iPhone Duo held on its
/// side): the Settings list as the sidebar, the chosen account's page or
/// group's sections as the detail. The Dashboard presents it full screen,
/// since a sheet there would be narrow and compact.
struct SettingsSplitView: View {
    @Environment(UsageModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var selection = SettingsSelection.group(.appearance)
    @State private var compactColumn = NavigationSplitViewColumn.sidebar

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all), preferredCompactColumn: $compactColumn) {
            SettingsView(selection: showingDetail)
                .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 440)
                .toolbar(removing: .sidebarToggle)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        SheetDoneButton { dismiss() }
                            .tint(Theme.accent)
                    }
                }
        } detail: {
            NavigationStack {
                detail
            }
            .id(selection)
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: model.accounts.map(\.id)) { _, ids in
            if case .account(let id) = selection, !ids.contains(id) {
                selection = .group(.appearance)
            }
        }
    }

    private var showingDetail: Binding<SettingsSelection> {
        Binding {
            selection
        } set: {
            selection = $0
            compactColumn = .detail
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .account(let accountID):
            AccountSettingsPage(accountID: accountID, dismissesOnDisconnect: false)
        case .group(let group):
            SettingsGroupPage(group: group)
        }
    }
}

extension View {
    func settingsSelected(_ isSelected: Bool) -> some View {
        padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.accentWash)
                }
            }
            .padding(.vertical, -6)
            .padding(.horizontal, -8)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
