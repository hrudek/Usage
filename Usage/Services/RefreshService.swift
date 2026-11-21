import Foundation
import WidgetKit
import UsageKit

/// Fetches usage for one connected account, persists the snapshot to the
/// App Group, reloads widget timelines, and reschedules reset
/// notifications. One instance per `ConnectedAccount` — `UsageModel` holds
/// one per registered account and fans refreshes out concurrently.
struct RefreshService {
    /// `private(set) var` rather than `let` for the display-only fields
    /// (`renamed(to:)`, `withIcon(_:)`): the credential source built in
    /// `init` depends on `accountID` and `providerID` alone.
    private(set) var account: ConnectedAccount
    /// Built by `ProviderCatalog.makeProvider` from `account.providerID` —
    /// nothing in this type knows which provider it's refreshing.
    let provider: any UsageProvider
    let credentialSource: any CredentialStore
    private let store: SnapshotStore?
    private let historyStore: UsageHistoryStore?

    init(account: ConnectedAccount) {
        self.account = account
        (provider, credentialSource) = ProviderCatalog.makeProvider(for: account, keychain: Self.keychainStore)
        store = SnapshotStore(suiteName: AppConfig.appGroupID)
        historyStore = UsageHistoryStore(suiteName: AppConfig.appGroupID)
    }

    static var keychainStore: KeychainStore {
        KeychainStore(service: AppConfig.keychainService, accessGroup: AppConfig.keychainAccessGroup)
    }

    /// The same service under a new nickname, keeping its provider.
    func renamed(to displayName: String) -> RefreshService {
        var copy = self
        copy.account.displayName = displayName
        return copy
    }

    /// Same one-field copy as `renamed(to:)`, for the chosen glyph.
    func withIcon(_ icon: AccountIcon?) -> RefreshService {
        var copy = self
        copy.account.icon = icon
        return copy
    }

    func lastSnapshot() -> UsageSnapshot? {
        store?.snapshot(for: account.accountID)
    }

    /// When usage history first started recording — the pace warm-up anchor.
    func paceObservingSince() -> Date? {
        historyStore?.observingSince(for: account.accountID)
    }

    /// - Parameter accountLabel: this account's nickname, to prefix onto
    ///   notification copy once more than one account is connected — nil
    ///   keeps a single-account install's copy reading exactly as it always
    ///   has. The caller already has this in memory (`UsageModel.accountLabel(for:)`
    ///   or the equivalent one-time computation in `refreshAllInBackground()`),
    ///   so `RefreshService` itself never needs to decode the account
    ///   registry just to compute it.
    @discardableResult
    func refresh(accountLabel: String?) async throws -> UsageSnapshot {
        let previous = store?.snapshot(for: account.accountID)
        let prefs = NotificationPreferences(accountID: account.accountID)

        let snapshot: UsageSnapshot
        do {
            snapshot = try await provider.fetchUsage()
                .fillingMissingResets(from: previous)
        } catch {
            // Only `notAuthenticated` alerts, not everything
            // `requiresReauthentication` covers; the others still show the
            // in-app sign-in affordance on the account's card.
            if case UsageError.notAuthenticated = error {
                await NotificationScheduler.notifyReauthenticationNeeded(
                    accountID: account.accountID,
                    accountLabel: accountLabel,
                    providerName: ProviderCatalog.displayName(for: account.providerID),
                    preferences: prefs
                )
            }
            throw error
        }
        // Fetching at all proves the credentials work, so re-arm the alert
        // for a future breakage (no-op unless one was actually delivered).
        NotificationScheduler.clearReauthenticationAlert(accountID: account.accountID, preferences: prefs)

        try store?.save(snapshot, for: account.accountID)
        UsageRecorder.record(snapshot, for: account.accountID)
        // No `reloadAllTimelines()` here: the caller reloads once per sweep
        // (see `UsageModel.fetch(accountID:)`), not once per account.

        await NotificationScheduler.rescheduleResets(
            for: snapshot, accountID: account.accountID, accountLabel: accountLabel, preferences: prefs
        )
        await NotificationScheduler.rescheduleRunOuts(
            runOutProjections(for: snapshot), accountID: account.accountID, accountLabel: accountLabel, preferences: prefs
        )
        await NotificationScheduler.rescheduleRenewal(
            accountID: account.accountID, accountLabel: accountLabel, preferences: prefs
        )
        if let previous {
            await fireDetectionAlerts(previous: previous, current: snapshot, accountLabel: accountLabel, preferences: prefs)
        }
        return snapshot
    }

    /// Re-issues this account's two *scheduled* notification families
    /// (`reset.`, `runout.`) from the stored snapshot, without fetching.
    /// `refresh` already does this after every successful fetch; this is
    /// for the one change that alters pending notification copy with no
    /// fetch involved — a rename, whose new nickname would otherwise wait
    /// for the next refresh to reach titles already queued under the old
    /// one. The detection-based families fire immediately, so they have
    /// nothing pending to rename.
    func rescheduleNotifications(accountLabel: String?) async {
        guard let snapshot = lastSnapshot() else { return }
        let prefs = NotificationPreferences(accountID: account.accountID)
        await NotificationScheduler.rescheduleResets(
            for: snapshot, accountID: account.accountID, accountLabel: accountLabel, preferences: prefs
        )
        await NotificationScheduler.rescheduleRunOuts(
            runOutProjections(for: snapshot), accountID: account.accountID, accountLabel: accountLabel, preferences: prefs
        )
        await NotificationScheduler.rescheduleRenewal(
            accountID: account.accountID, accountLabel: accountLabel, preferences: prefs
        )
    }

    /// Immediate, detection-based alerts (compare previous vs new): early
    /// refill, hitting the limit, and nearing it. A single big jump can
    /// cross both the near-limit threshold and the limit — the more severe
    /// "limit reached" wins, so its kinds are excluded from the near-limit
    /// set to avoid a double notification.
    private func fireDetectionAlerts(
        previous: UsageSnapshot,
        current: UsageSnapshot,
        accountLabel: String?,
        preferences prefs: NotificationPreferences
    ) async {
        await NotificationScheduler.notifyEarlyResets(
            ResetDetector.earlyResets(previous: previous, current: current), in: current,
            accountID: account.accountID, accountLabel: accountLabel, preferences: prefs
        )

        let reached = ThresholdDetector.crossedUp(
            previous: previous, current: current,
            threshold: ThresholdDetector.limitReachedThreshold
        )
        let room = roomElsewhere(given: current).map { UsageInsights.roomSentence($0) }
        await NotificationScheduler.notifyLimitReached(
            reached, in: current, accountID: account.accountID, accountLabel: accountLabel,
            room: room, preferences: prefs
        )

        // Every level the user set; a jump past two of them in one fetch
        // is one warning, which reads the figure it reached.
        var nearing: [UsageWindow.Kind] = []
        for threshold in Set(prefs.nearLimitThresholds) {
            for kind in ThresholdDetector.crossedUp(previous: previous, current: current, threshold: threshold)
            where !reached.contains(kind) && !nearing.contains(kind) {
                nearing.append(kind)
            }
        }
        await NotificationScheduler.notifyNearLimit(
            nearing, in: current, accountID: account.accountID, accountLabel: accountLabel,
            room: room, preferences: prefs
        )

        // Pace is withheld until the account has been watched long enough
        // to trust it, here as on every surface (`PaceCalculator.isReady`).
        if PaceCalculator.isReady(observingSince: paceObservingSince()) {
            await NotificationScheduler.notifyAheadOfPace(
                PaceDetector.aheadCrossings(previous: previous, current: current),
                in: current, accountID: account.accountID, accountLabel: accountLabel, preferences: prefs
            )
        }
    }

    /// Another account of this service with room, read from the registry
    /// and the stored snapshots (this service knows only its own account),
    /// for the line the limit alerts end with.
    private func roomElsewhere(given current: UsageSnapshot) -> UsageInsights.Room? {
        guard let store, let registry = AccountRegistryStore(suiteName: AppConfig.appGroupID) else { return nil }
        return UsageInsights.room(
            forUrgency: AccountOrder.urgency(of: current),
            providerID: account.providerID,
            accountID: account.accountID,
            among: registry.accounts().map { ($0, store.snapshot(for: $0.accountID)) }
        )
    }

    /// Run-out projections for alerts: recent-rate from history when there's
    /// enough signal, otherwise the average rate (gated by a minimum used%
    /// so a barely-touched window doesn't warn). Empty before any usage.
    private func runOutProjections(for snapshot: UsageSnapshot) -> [UsageWindow.Kind: RunOutProjection] {
        var result: [UsageWindow.Kind: RunOutProjection] = [:]
        for window in snapshot.windows {
            let samples = historyStore?.samples(for: account.accountID, kind: window.kind) ?? []
            if let recent = RunOutPredictor.recentProjection(for: window, samples: samples) {
                result[window.kind] = recent
            } else if let average = RunOutPredictor.averageProjection(
                for: window, minimumUsedPct: RunOutPredictor.alertMinimumUsedPct
            ) {
                result[window.kind] = average
            }
        }
        return result
    }

    // MARK: - Connection management (in-app OAuth flow)

    /// The connect path: the one place this type is provider-typed,
    /// because the credentials themselves are (`ProviderLogin`: what each
    /// family's sign-in flow hands back). The login must be of the
    /// account's own family; the source built for the account is the only
    /// one that can hold it.
    func storeConnection(_ login: ProviderLogin) async throws {
        switch login {
        case .claude(let credentials):
            guard let source = credentialSource as? any ClaudeCredentialSource else { throw mismatch(login) }
            try await source.save(credentials)
        case .codex(let credentials):
            guard let source = credentialSource as? any CodexCredentialSource else { throw mismatch(login) }
            try await source.save(credentials)
        }
    }

    private func mismatch(_ login: ProviderLogin) -> UsageError {
        .storage("account \(account.accountID) is not a \(ProviderCatalog.displayName(for: login.providerID)) account")
    }

    func disconnect() throws {
        // `CredentialStore.clear` removes the account's Keychain item
        // without this type knowing its family.
        try credentialSource.clear()
        store?.removeSnapshot(for: account.accountID)
        UsageRecorder.clear(accountID: account.accountID)
        WidgetReload.all()
        // Everything else keyed by this accountID goes too: the reset/
        // run-out requests still queued for it (they'd fire at their
        // `resetsAt` for an account that no longer exists), whatever it
        // delivered, and its per-account toggles — otherwise a UUID's
        // worth of keys leaks into the App Group forever.
        let accountID = account.accountID
        Task { await NotificationScheduler.removeAll(accountID: accountID) }
        NotificationPreferences(accountID: accountID).clear()
        WidgetModelWindowPreference(accountID: accountID).clear()
    }
}
