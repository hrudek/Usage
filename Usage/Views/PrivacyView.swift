import SwiftUI
import UsageKit

/// Privacy & data: where data lives, how connecting works, and exactly
/// what the connection can access. Every claim here must stay true to the
/// code — update this screen when the data flow changes.
struct PrivacyView: View {

    @Environment(UsageModel.self) private var model

    /// The families this install has accounts of (all three with none,
    /// and in demo mode, whose accounts stand for any of them): how each
    /// connects and what it can reach is said only for those.
    private var families: [String] {
        ProviderCatalog.familiesToDescribe(connected: model.accounts.map(\.account.providerID))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: String(localized: "Private by default"))
                Card {
                    VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                        PrivacyRow(
                            systemName: "iphone",
                            title: String(localized: "Everything stays on your device"),
                            text: String(localized: "Usage has no server and no account of its own. Your limits are read directly from each provider and cached on this device so widgets can show it. Nothing is sent anywhere else.")
                        )
                        Divider().overlay(Theme.track)
                        PrivacyRow(
                            systemName: "chart.xyaxis.line",
                            title: String(localized: "Up to 90 days of history"),
                            text: String(localized: "To draw the history chart, Usage keeps the percentages it has already fetched (just the numbers and their dates, nothing about what you did) on this device for 90 days. Disconnecting an account deletes its history.")
                        )
                        Divider().overlay(Theme.track)
                        PrivacyRow(
                            systemName: "key.fill",
                            title: String(localized: "Tokens live in the Keychain"),
                            text: keychainRowText
                        )
                        Divider().overlay(Theme.track)
                        PrivacyRow(
                            systemName: "eye.slash.fill",
                            title: String(localized: "No tracking, no analytics"),
                            text: String(localized: "No analytics SDKs, no ad networks, no crash reporting. The app collects no data at all.")
                        )
                    }
                }

                sectionGap
                SectionHeader(title: String(localized: "How connecting works"))
                Card {
                    VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                        ForEach(Array(families.enumerated()), id: \.element) { index, family in
                            if index > 0 {
                                Divider().overlay(Theme.track)
                            }
                            Text(Self.connectingText(for: family))
                                .font(.callout)
                                .foregroundStyle(Theme.ink)
                        }
                    }
                }
                SectionFootnote(text: String(localized: "Each one is the sign-in flow the provider's own tools use; Usage only receives the token the provider hands back."))

                sectionGap
                SectionHeader(title: String(localized: "What the connection can access"))
                Card {
                    VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                        ForEach(families, id: \.self) { family in
                            access(for: family)
                            if family != families.last {
                                Divider().overlay(Theme.track)
                            }
                        }
                    }
                }

                sectionGap
                Card {
                    Text("Usage is an independent open source project (MIT). It is not affiliated with, endorsed by, or sponsored by Anthropic or OpenAI. \"Claude\" and \"Anthropic\" are trademarks of Anthropic, PBC; \"ChatGPT\", \"Codex\" and \"OpenAI\" of OpenAI. They are used only to identify the services whose usage this app displays.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            .padding(20)
        }
        .appBackground()
        .navigationTitle(String(localized: "Privacy & data"))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// How one family connects, on this platform.
    static func connectingText(for family: String) -> String {
        switch family {
        case CodexProvider.providerID:
            String(localized: "Codex: Usage shows you a one-time code that you enter on ChatGPT's own device page in your browser, the same device code sign-in the Codex CLI offers.")
        default:
            String(localized: "Claude: you sign in on Claude's own page in your browser, never in an embedded web view, so Usage can't see your password. You only paste back the code Claude shows after you approve.")
        }
    }

    /// What one family's connection can reach.
    @ViewBuilder
    private func access(for family: String) -> some View {
        HStack(spacing: 8) {
            ProviderMark(size: 22, cornerRadius: 6, icon: family == ClaudeProvider.providerID ? nil : .symbol(ProviderCatalog.symbolName(for: family)))
            Text(verbatim: ProviderCatalog.displayName(for: family))
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.ink)
        }
        switch family {
        case CodexProvider.providerID:
            Text("The sign-in is ChatGPT's own device code login, with the access the Codex CLI gets; Usage calls one read-only endpoint with it, your Codex limits (the same figures the CLI's /status shows), and nothing else.")
                .font(Theme.caption)
                .foregroundStyle(Theme.inkSecondary)
        default:
            Text("Requested OAuth scope:")
                .font(Theme.caption)
                .foregroundStyle(Theme.inkSecondary)
            HStack(spacing: 8) {
                // Exactly what `ClaudeOAuth.scope` requests — keep
                // the two in sync; this chip is the user-facing
                // proof that the inference scope is never asked for.
                ScopeChip(name: "user:profile")
            }
            Text("When you sign in through Usage it requests only the user:profile scope (what the usage and profile endpoints need) and never asks for the inference scope. It never calls an inference endpoint: it only ever calls two read-only endpoints, your usage windows and your profile (to show the plan). The source is open if you want to verify.")
                .font(Theme.caption)
                .foregroundStyle(Theme.inkSecondary)
        }
    }

    private var sectionGap: some View {
        Spacer().frame(height: Theme.sectionSpacing - 16)
    }

    /// The widget reads the login through the App Group's keychain access
    /// group and renews it like the app (`ProviderCatalog.refresher`).
    private var keychainRowText: String {
        String(localized: "Your sign-in token is stored encrypted in the system Keychain and shared only with the widget. The app and the widget use it to load your usage and renew it when it expires. It is used exclusively to read your usage.")
    }
}

/// Icon + title + explanation row (Private by default card).
private struct PrivacyRow: View {
    let systemName: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemName)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 28, height: 28)
                .background(Theme.accentWash, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text(text)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Monospaced OAuth scope pill.
private struct ScopeChip: View {
    let name: String

    var body: some View {
        Text(verbatim: name)
            .font(.caption.monospaced())
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Theme.track.opacity(0.7), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
