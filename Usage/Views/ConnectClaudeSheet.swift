import SwiftUI
import UsageKit

/// OAuth connect flow: open Claude's sign-in page in the browser, the user
/// approves and copies the authentication code shown, pastes it back here,
/// and we exchange it for tokens stored in the Keychain.
///
/// Doubles as the re-sign-in flow: pass `reconnecting` and the exact same
/// exchange lands on an existing account's credential key instead of
/// creating a new account (`UsageModel.reconnect`), which is what keeps
/// that account's history, toggles, and placed widgets intact. Only the
/// copy differs, plus dropping the nickname field — the account already has
/// a name the user chose.
struct ConnectClaudeSheet: View {
    /// nil for a brand-new connection; the account being repaired otherwise.
    var reconnecting: ConnectedAccount?

    @Environment(UsageModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var session = ClaudeOAuth.startSession()
    @State private var code = ""
    @State private var nickname = ""
    @State private var isExchanging = false
    @State private var errorText: String?
    /// The pasteboard's change count when the code was pasted from it.
    @State private var pastedChangeCount: Int?

    var body: some View {
        // Scrollable so content is never clipped/truncated at the `.medium`
        // detent (or with larger Dynamic Type sizes) — it just scrolls
        // instead, and dragging up to `.large` still shows it all at once.
        ScrollView {
            VStack(spacing: 18) {
                ProviderMark(size: 72, cornerRadius: 20, prominent: true)
                    .padding(.top, 8)

                Text(reconnecting == nil ? String(localized: "Connect your Claude account") : String(localized: "Sign in again"))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.ink)

                Text(explainer)
                    .font(.callout)
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)

                Button {
                    openURL(session.authorizeURL)
                } label: {
                    Label("Open Claude Sign-In", systemImage: "safari")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        // The capsule is drawn *outside* the button (below),
                        // so without this only the label's glyphs would be
                        // tappable — a `.plain` button hit-tests its label,
                        // and a transparent frame is not opaque content.
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .background(Theme.accentWash, in: Capsule())

                if reconnecting == nil, !model.accounts.isEmpty {
                    // Only relevant once there's more than one account to tell
                    // apart — a single connected account never needed a name.
                    // Never when reconnecting: that account keeps its name.
                    TextField(defaultNickname, text: $nickname)
                        .textFieldStyle(.plain)
                        .font(.callout)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Theme.track.opacity(0.6), in: Capsule())

                    if nicknameTaken {
                        Text("Another account is already called that.")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.danger)
                            .multilineTextAlignment(.center)
                    }
                }

                HStack(spacing: 8) {
                    TextField("Paste the code Claude shows…", text: $code)
                        .textFieldStyle(.plain)
                        .font(.callout.monospaced())
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Theme.track.opacity(0.6), in: Capsule())

                    Button(action: pasteFromClipboard) {
                        Image(systemName: "doc.on.clipboard")
                            .accessibilityLabel(Text("Paste"))
                            .font(.body.weight(.medium))
                            .foregroundStyle(Theme.onAccent)
                            .frame(width: 44, height: 44)
                            .background(Theme.accent, in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                Button(action: connect) {
                    Group {
                        if isExchanging {
                            ProgressView().controlSize(.small).tint(Theme.onAccent)
                        } else {
                            Text("Connect")
                        }
                    }
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    // Whole capsule tappable, not just the word — see the
                    // sign-in button above.
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                // Disabled, its word in the secondary ink: white on the
                // track (1.2:1) hid the button altogether.
                .foregroundStyle(canConnect ? Theme.onAccent : Theme.inkSecondary)
                .background(
                    (canConnect ? Theme.accent : Theme.track) , in: Capsule()
                )
                .disabled(!canConnect)
                .keyboardShortcut(.defaultAction)

                // Said here, at the moment of connecting, not only buried in
                // Privacy & data: what this app is, what the token is for,
                // and where it stays. Every clause must remain true to the
                // code (read-only endpoints, Keychain-only storage, no server).
                Text("Usage is an independent app, not affiliated with Anthropic. It only reads your own usage limits, never sends prompts or spends your plan's usage, and your sign-in token stays on this device.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)

                if let errorText {
                    Text(errorText)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.danger)
                        .multilineTextAlignment(.center)
                }

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .tapTarget()
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(.bottom, 8)
            }
            .padding(24)
        }
        .appBackground()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var explainer: String {
        if reconnecting != nil {
            return String(localized: "Claude no longer accepts this account's saved sign-in. Sign in again to restore it. Its history, alerts, and widgets all stay as they are.")
        }
        return String(localized: "Usage will open Claude's sign-in page in your browser. After you approve, copy the code it shows and paste it back here to finish. Any sign-in method works.")
    }

    /// Why the pasted code can't be this sign-in's, said before sending
    /// it: the page shows `code#state`, and the state must be this one's.
    private var codeProblem: String? {
        let parts = code.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "#", maxSplits: 1).map(String.init)
        guard parts.count == 2 else {
            return String(localized: "Paste the whole code from the sign-in page, including the part after #.")
        }
        guard parts[1] == session.state else {
            return String(localized: "This code is from an earlier sign-in. Open the sign-in page again and paste the new code.")
        }
        return nil
    }

    private var canConnect: Bool {
        !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isExchanging && !nicknameTaken
    }

    /// Placeholder for the nickname field — see `UsageModel.suggestedNickname`.
    private var defaultNickname: String {
        model.suggestedNickname(providerID: ClaudeProvider.providerID)
    }

    /// The typed nickname collides with another account's: Connect is
    /// disabled and the field says why. Never true for the placeholder,
    /// which is chosen to be free.
    private var nicknameTaken: Bool {
        reconnecting == nil && model.isNameTaken(resolvedNickname)
    }

    private var resolvedNickname: String {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultNickname : trimmed
    }

    private func pasteFromClipboard() {
        if let pasted = UIPasteboard.general.string {
            code = pasted
            pastedChangeCount = UIPasteboard.general.changeCount
        }
    }

    private func connect() {
        if let problem = codeProblem {
            errorText = problem
            return
        }
        isExchanging = true
        errorText = nil
        Task {
            defer { isExchanging = false }
            do {
                let credentials = try await obtainCredentials()
                if let reconnecting {
                    await model.reconnect(accountID: reconnecting.accountID, login: .claude(credentials))
                } else {
                    await model.completeConnection(.claude(credentials), displayName: resolvedNickname)
                }
                if let connectionError = model.connectionError {
                    errorText = connectionError
                } else {
                    // The code is spent; take it off the pasteboard (and
                    // the Universal Clipboard) unless something else was
                    // copied since it was pasted.
                    if pastedChangeCount == UIPasteboard.general.changeCount {
                        UIPasteboard.general.items = []
                    }
                    dismiss()
                }
            } catch {
                errorText = (error as? UsageError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    /// The field accepts the OAuth code from the sign-in page, nothing else.
    private func obtainCredentials() async throws -> ClaudeCredentials {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await ClaudeOAuth().exchange(pastedCode: trimmed, session: session)
    }
}
