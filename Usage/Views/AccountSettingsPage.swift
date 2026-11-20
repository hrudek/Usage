import SwiftUI
import UsageKit

/// One account's own settings and nothing general: signing in again when
/// its login stopped working, its name and icon, its notifications and
/// disconnecting it. Every general setting lives in Settings' other
/// sections, so nothing is in two places. Shown on the account's page
/// (`AccountSettingsPage`, pushed from Settings' account list and from
/// the end of Provider Detail).
struct AccountSettingsCards: View {
    let accountID: String
    /// Called once the account is disconnected, so a pushed page can pop.
    var onDisconnect: (() -> Void)? = nil

    @Environment(UsageModel.self) private var model
    @Environment(AccountPresenter.self) private var presenter

    private var usage: UsageModel.AccountUsage? {
        model.usage(for: accountID)
    }

    /// The nickname, or the provider's name while the account is gone
    /// (the page is mid-dismiss after a disconnect).
    private var accountName: String {
        usage?.account.displayName ?? ProviderCatalog.displayName(for: ProviderCatalog.defaultProviderID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // A login that stopped working comes first: Settings' row for
            // the account says "Sign in again", and this is where it leads.
            if let usage, usage.needsReauthentication {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(String(localized: "Sign-in expired. Usage can't refresh."), systemImage: "exclamationmark.triangle")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.danger)
                        Button {
                            presenter.reconnecting = usage.account
                        } label: {
                            Text("Sign in again")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                SettingsGap()
            }
            // The discoverable route to the same rename and icon the
            // Dashboard header's context menu offers — a context menu
            // announces nothing about itself.
            SectionHeader(title: String(localized: "Account"))
            Card {
                Button {
                    if let account = usage?.account {
                        presenter.rename(account)
                    }
                } label: {
                    HStack(spacing: 12) {
                        Text("Name")
                            .font(Theme.rowTitle)
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Text(accountName)
                            .font(.body)
                            .foregroundStyle(Theme.inkSecondary)
                            .lineLimit(1)
                        Image(systemName: "pencil")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Rename account"))
                .accessibilityValue(Text(accountName))
                Divider().overlay(Theme.track)
                Button {
                    presenter.iconPickerAccountID = accountID
                } label: {
                    HStack(spacing: 12) {
                        Text("Icon")
                            .font(Theme.rowTitle)
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        ProviderMark(size: 24, cornerRadius: 6, icon: usage?.account.icon)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Change icon"))
            }
            SectionFootnote(text: String(localized: "Shown on the dashboard, in widgets, and in notification titles."))
            SettingsGap()

            if usage?.account.providerID == ClaudeProvider.providerID {
                SectionHeader(title: String(localized: "Widgets"))
                WidgetModelWindowCard(accountID: accountID)
                SectionFootnote(text: String(localized: "Shows a model's own limit, such as Fable, on this account's widgets and control. When off, they treat it as missing: its row shows what \"Usage rows\" sets for plans without one. The app always shows it."))
                SettingsGap()
            }

            SectionHeader(title: String(localized: "Reset alerts"))
            NotificationTogglesCard(accountID: accountID)
            SectionFootnote(text: String(localized: "A notification when each limit refills."))

            SettingsGap()
            SectionHeader(title: String(localized: "Smart notifications"))
            SmartNotificationTogglesCard(accountID: accountID)

            SettingsGap()
            SectionHeader(title: String(localized: "Renewal"))
            RenewalReminderCard(accountID: accountID)
            SectionFootnote(text: String(localized: "Usage can't see your billing, so the day is the one you set. The reminder comes that many days before, every month."))

            SettingsGap()
            // Disconnecting deletes the account's history and alerts
            // on this device, so it asks first.
            Button(role: .destructive) {
                presenter.confirmDisconnect(accountID, onDone: onDisconnect)
            } label: {
                Text("Disconnect \(accountName)")
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            }
        }
    }
}

private struct WidgetModelWindowCard: View {
    let accountID: String
    @State private var isShown: Bool

    init(accountID: String) {
        self.accountID = accountID
        _isShown = State(initialValue: WidgetModelWindowPreference(accountID: accountID).isShown)
    }

    var body: some View {
        Card {
            Toggle(isOn: $isShown) {
                Text("Per-model limit in widgets")
                    .font(Theme.rowTitle)
                    .foregroundStyle(Theme.ink)
            }
            .tint(Theme.accent)
        }
        .onChange(of: isShown) { _, shown in
            WidgetModelWindowPreference(accountID: accountID).isShown = shown
            WidgetReload.all()
        }
    }
}

/// Asks before disconnecting an account, saying what goes with it, and
/// calls `onDone` only once it is gone (a failed cascade leaves it, its
/// error on its card).
struct DisconnectConfirmation: ViewModifier {
    let accountID: String
    @Binding var isPresented: Bool
    let onDone: () -> Void
    @Environment(UsageModel.self) private var model

    func body(content: Content) -> some View {
        let name = model.usage(for: accountID)?.account.displayName ?? ""
        content.confirmationDialog(
            Text("Disconnect \(name)?"),
            isPresented: $isPresented,
            titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive) {
                if model.disconnect(accountID: accountID) {
                    onDone()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Usage forgets its sign-in and deletes its usage history and its alerts. Your account with the service isn't touched.")
        }
    }
}

extension View {
    func disconnectConfirmation(accountID: String, isPresented: Binding<Bool>, onDone: @escaping () -> Void) -> some View {
        modifier(DisconnectConfirmation(accountID: accountID, isPresented: isPresented, onDone: onDone))
    }
}

/// The account's settings as a pushed page: from the Settings list's
/// account rows (iOS) and from Provider Detail's "Account settings" row
/// (both platforms, in the Dashboard's navigation stack).
struct AccountSettingsPage: View {
    let accountID: String
    /// Whether disconnecting pops this page. In the Dashboard's stack it
    /// doesn't: the stack goes back to the Dashboard itself once the
    /// account is gone (`ContentView`), since the Provider Detail under
    /// this page has nothing left to show.
    var dismissesOnDisconnect = true

    @Environment(UsageModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            AccountSettingsCards(accountID: accountID, onDisconnect: dismissesOnDisconnect ? { dismiss() } : nil)
                .padding(20)
                .readableWidth()
        }
        .appBackground()
        // Not the account's name alone: that is Provider Detail's title,
        // the page under this one, and the two read as one screen.
        .navigationTitle(String(localized: "\(model.usage(for: accountID)?.account.displayName ?? "") Settings"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The value the Dashboard's stack pushes for an account's settings page
/// (`DashboardView`'s `navigationDestination`): a value, like Provider
/// Detail's, so the stack's path holds the whole stack and going back to
/// the Dashboard after a disconnect is one reset of it.
struct AccountSettingsRoute: Hashable {
    let accountID: String
}
