import SwiftUI
import UsageKit

/// Settings on iOS: one screen (Mike's reorganization, 2026-10-22).
/// The accounts first, inline, since they are what people come for (each
/// row opens its page, which holds that account's notifications; "Add
/// account" opens the Connect sheet over Settings; "Order by urgency"
/// under them), then one row per group, each opening its own screen:
/// Appearance, Widgets, Refresh & data, About. No Notifications group:
/// every alert is an account's, so it would only have listed the accounts
/// above again (Mike, 2026-10-22). Built from the section views in
/// `SettingsSections.swift`.
struct SettingsView: View {
    var selection: Binding<SettingsSelection>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                AccountListSettings(selection: selection)
                SettingsGap()
                Card {
                    VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                        ForEach(SettingsGroup.allCases, id: \.self) { group in
                            if group != SettingsGroup.allCases.first {
                                Divider().overlay(Theme.track)
                            }
                            groupRow(group)
                        }
                    }
                }
            }
            .padding(20)
            .readableWidth()
        }
        .appBackground()
        .navigationTitle("Settings")
    }

    @ViewBuilder
    private func groupRow(_ group: SettingsGroup) -> some View {
        if let selection {
            Button {
                selection.wrappedValue = .group(group)
            } label: {
                SettingsGroupRow(group: group, chevron: false)
                    .settingsSelected(selection.wrappedValue == .group(group))
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                SettingsGroupPage(group: group)
            } label: {
                SettingsGroupRow(group: group, chevron: true)
            }
            .buttonStyle(.plain)
        }
    }
}

enum SettingsGroup: Hashable, CaseIterable {
    case appearance, widgets, refresh

    var title: String {
        switch self {
        case .appearance: String(localized: "Appearance")
        case .widgets: String(localized: "Widgets")
        case .refresh: String(localized: "Refresh & data")
        }
    }

    var symbol: String {
        switch self {
        case .appearance: "paintbrush"
        case .widgets: "square.grid.2x2"
        case .refresh: "arrow.clockwise"
        }
    }
}

struct SettingsGroupPage: View {
    let group: SettingsGroup

    @Environment(UsageModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                switch group {
                case .appearance:
                    AppearanceSettings()
                    if UsageRowsSettings.isOffered(model) {
                        SettingsGap()
                        UsageRowsSettings()
                    }
                case .widgets:
                    GlanceMetricSettings()
                    SettingsGap()
                    WidgetHowToSettings()
                case .refresh:
                    BackgroundRefreshSettings()
                    SettingsGap()
                    PrivacyLinkSettings()
                }
            }
            .padding(20)
            .readableWidth()
        }
        .appBackground()
        .navigationTitle(group.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SettingsGroupRow: View {
    let group: SettingsGroup
    let chevron: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: group.symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 28, height: 28)
                .background(Theme.accentWash, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(verbatim: group.title)
                .font(.body.weight(.medium))
                .foregroundStyle(Theme.ink)
            Spacer()
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
    }
}

/// Widgets: how to put one on the Home Screen or the Lock Screen, since
/// the app can't place them itself.
private struct WidgetHowToSettings: View {
    var body: some View {
        SectionHeader(title: String(localized: "Add a widget"))
        Card {
            Text("Touch and hold your Home Screen or Lock Screen, tap Edit, then Add Widget, and search for Usage. Each widget can show any of your accounts: touch and hold it, then Edit Widget.")
                .font(.callout)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Sheet wrapper with a Done button, matching the reference presentation.
struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SettingsView()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        SheetDoneButton { dismiss() }
                            .tint(Theme.accent)
                    }
                }
        }
    }
}
