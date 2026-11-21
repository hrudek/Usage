import Foundation
import Observation
import UserNotifications
import WidgetKit
import UsageKit

/// UI-facing state for every connected account. Wraps one
/// `RefreshService` per account and keeps each account's last known
/// snapshot visible even when a refresh fails (the error is surfaced
/// alongside, per account). Split by feature across
/// `UsageModel+Connections.swift` (connect/reconnect/disconnect, demo),
/// `UsageModel+Naming.swift` (ordering and nicknames),
/// and `UsageModel+Notifications.swift` (per-account toggles); this
/// file holds the state, loading, and the refresh path.
///
/// `isRefreshing` and `needsConnection` below are true aggregates over every
/// connected account (not a first-account shim), read by surfaces that only
/// need a glance-level "is anything busy / is anything connected at all".
/// `@MainActor`: `refreshAll()` fans out concurrent fetches via a
/// `TaskGroup`, and each one mutates a different element of the shared
/// `accounts` array on completion. Isolating the whole class serializes
/// those mutations (safe) while each `refresh(accountID:)` call's own
/// `await service.refresh()` network request still suspends off the main
/// actor, so the fetches themselves still run concurrently — only the
/// bookkeeping before/after each one is serialized.
@MainActor
@Observable
final class UsageModel {
    struct AccountUsage: Identifiable {
        var id: String { account.accountID }
        var account: ConnectedAccount
        var snapshot: UsageSnapshot?
        var lastError: String?
        /// The last failure was one no retry can fix (see
        /// `UsageError.requiresReauthentication`), so the surfaces showing
        /// this account swap the raw message for a "Sign in again" prompt.
        /// Signing in again is the *only* honest recovery here: the
        /// alternative a user would otherwise reach for — disconnect and
        /// add the account back — mints a fresh `accountID`, which orphans
        /// this account's history, notification preferences, and every
        /// already-placed widget configured for it.
        var needsReauthentication = false
        /// The last failure was the network, not the provider: the card
        /// shows a quiet "offline, showing the last update" line instead of
        /// the raw `URLError` in red, since nothing about the account is
        /// wrong and the next successful fetch clears it.
        var isOffline = false
        var isRefreshing = false
    }

    /// `private(set)` in spirit — only this type's own files mutate it.
    var accounts: [AccountUsage] = []
    /// An account the "Open Account" intent asked for; the Dashboard's
    /// navigation stack opens its detail and clears it (`ContentView`).
    var accountToOpen: String?
    /// Transient error from the Connect sheet's own attempt to store fresh
    /// credentials — distinct from an already-connected account's ongoing
    /// `lastError`, since a failed connection never makes it into `accounts`.
    var connectionError: String?

    /// Internal (not private) so the feature extensions in
    /// `UsageModel+*.swift` can reach them; nothing outside this type's
    /// own files should touch either.
    var services: [String: RefreshService] = [:]
    let registry: AccountRegistryStore?
    /// "Order by urgency" (`Preferences.ordersByUrgency`, mirrored here by
    /// Settings so the model never reads the App Group behind the tests' back): `accounts` is sorted by
    /// `AccountOrder` after every load and sweep, the registry's order
    /// left as the user set it (see `UsageModel+Naming.swift`).
    var ordersByUrgency = false
    /// The chart's samples per account, keyed by `Kind.storageKey` — see
    /// `UsageModel+History.swift`. nil store in unit tests.
    var timelines: [String: [String: [TimelineSample]]] = [:]
    let timelineStore: UsageTimelineStore?

    /// True when the user denied notification permission in the system
    /// settings — one OS-level toggle, not per account, so the toggles
    /// card's warning reads this shared state regardless of which
    /// account's card is showing it. Stored here (extensions can't add
    /// storage); managed in `UsageModel+Notifications.swift`.
    var notificationsBlocked = false
    /// Bumped whenever a toggle's stored value changes, so bindings that
    /// read UserDefaults through the notification getters re-evaluate.
    var notificationsRevision = 0

    /// The app's model: the App Group registry and the platform services
    /// (the notification sweep).
    convenience init() {
        guard !Self.isTestHost else {
            self.init(registry: nil, platformServices: false)
            return
        }
        self.init(registry: AccountRegistryStore(suiteName: AppConfig.appGroupID), platformServices: true)
    }

    /// The unit-test host is this same app, launched unsigned by
    /// `xcodebuild test`: its own model connects nothing and refreshes
    /// nothing, since every read of an account's Keychain item from a copy
    /// signed another way asks for the login password (Mike, 2026-11-03:
    /// one prompt per test run). The tests build models of their own.
    nonisolated static var isTestHost: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// `platformServices: false` is the unit-test seam: no scheduler or
    /// observers, no notification sweep — just the registry handed in.
    init(registry: AccountRegistryStore?, platformServices: Bool) {
        self.registry = registry
        timelineStore = platformServices ? UsageTimelineStore(appGroupID: AppConfig.appGroupID) : nil
        if platformServices {
            ordersByUrgency = Preferences.load().ordersByUrgency
        }
        loadAccounts()
        guard platformServices else { return }
        AppEnvironment.shared = self
    }

    /// Reuses any already-live `RefreshService` per account (keyed off the
    /// previous `services` dict) instead of rebuilding one from scratch —
    /// `loadAccounts()` may run more than once per process.
    func loadAccounts() {
        let previousServices = services
        let connected = registry?.accounts() ?? []
        services = Dictionary(connected.map { account in
            (account.accountID, previousServices[account.accountID] ?? RefreshService(account: account))
        }, uniquingKeysWith: { first, _ in first })
        accounts = connected.map { AccountUsage(account: $0, snapshot: services[$0.accountID]?.lastSnapshot()) }
        reloadTimelines()
        applyAccountOrder()
    }

    // MARK: - Refresh

    /// Standalone refresh path for the iOS `BGAppRefreshTask`, which runs
    /// in a context with no live `UsageModel` instance to reuse. Its
    /// services are new, but their providers share `ProviderCatalog.refresher`
    /// with the model's, so a login is still refreshed once at a time.
    static func refreshAllInBackground() async {
        guard let registry = AccountRegistryStore(suiteName: AppConfig.appGroupID) else { return }
        let allAccounts = registry.accounts()
        let label: (ConnectedAccount) -> String? = { allAccounts.count > 1 ? $0.displayName : nil }
        let fetched = await withTaskGroup(of: Bool.self) { group in
            for account in allAccounts {
                group.addTask { @MainActor in
                    let service = RefreshService(account: account)
                    return (try? await service.refresh(accountLabel: label(account))) != nil
                }
            }
            return await group.reduce(false) { $0 || $1 }
        }
        if fetched { WidgetReload.all() }
    }

    func refreshAll() async {
        let fetched = await withTaskGroup(of: Bool.self) { group in
            for account in accounts.map(\.account) {
                group.addTask { await self.fetch(accountID: account.accountID) }
            }
            return await group.reduce(false) { $0 || $1 }
        }
        if fetched { WidgetReload.all() }
        applyAccountOrder()
    }

    /// This account's current array index. Never captured across an
    /// `await`: `refresh(accountID:)` runs concurrently with other accounts'
    /// refreshes on the same actor, and a concurrent disconnect or
    /// `credentialsNotFound` revert can shift or remove elements while this
    /// one is suspended — re-resolving right before each mutation is what
    /// keeps that safe instead of writing through a stale/out-of-range index.
    func index(for accountID: String) -> Int? {
        accounts.firstIndex(where: { $0.account.accountID == accountID })
    }

    func refresh(accountID: String) async {
        if await fetch(accountID: accountID) {
            WidgetReload.all()
        }
        applyAccountOrder()
    }

    /// One account's fetch + bookkeeping. Returns whether a new snapshot
    /// reached the store — the caller's cue to reload widget timelines,
    /// which is deliberately *not* done here: the `refreshAll` sweeps fan
    /// this out per account and reload once at the end, since each
    /// `reloadAllTimelines()` draws on WidgetKit's per-kind budget and N
    /// accounts would otherwise spend it N times per sweep.
    func fetch(accountID: String) async -> Bool {
        guard let service = services[accountID],
              let startIndex = index(for: accountID), !accounts[startIndex].isRefreshing else { return false }
        accounts[startIndex].isRefreshing = true
        defer {
            if let i = index(for: accountID) { accounts[i].isRefreshing = false }
        }
        do {
            let snapshot = try await service.refresh(accountLabel: accountLabel(for: accountID))
            guard let i = index(for: accountID) else {
                guard services[accountID] == nil else { return true }
                // Disconnected while this fetch was in flight, which has
                // just written back what the disconnect cleared: the
                // snapshot, the history, the notifications, a rotated
                // token. Clear them again. (Demo mode also empties this
                // account's row, but keeps its service.)
                try? service.disconnect()
                return false
            }
            accounts[i].snapshot = snapshot
            accounts[i].lastError = nil
            accounts[i].needsReauthentication = false
            accounts[i].isOffline = false
            reloadTimeline(for: accountID)
            if accounts[i].account.displayName != service.account.displayName {
                // A rename landed while this fetch was in flight. The
                // `service` captured above still carried the old nickname,
                // so it just re-issued the reset/run-out notifications under it — redo those nudges
                // from the current name rather than leave the old one on
                // screen until the next refresh.
                propagateName(accountID: accountID)
            }
            return true
        } catch let error as UsageError {
            if let i = index(for: accountID) {
                accounts[i].lastError = error.errorDescription
                accounts[i].needsReauthentication = error.requiresReauthentication
                accounts[i].isOffline = false
            }
        } catch is CancellationError {
            // A superseded refresh (pull-to-refresh released, scene change)
            // is not an error worth showing.
        } catch let error as URLError where error.code == .cancelled {
            // Same: the URL task was cancelled by a newer refresh.
        } catch let error as URLError where Self.offlineCodes.contains(error.code) {
            // No route to the endpoint at all — nothing to act on, and the
            // last snapshot is still the best information there is.
            if let i = index(for: accountID) {
                accounts[i].lastError = String(localized: "Offline. Showing the last update.")
                accounts[i].isOffline = true
            }
        } catch {
            if let i = index(for: accountID) {
                accounts[i].lastError = error.localizedDescription
            }
        }
        return false
    }

    /// The `URLError`s that mean "the network, not the provider": shown as
    /// the quiet offline line rather than a red error with the raw text.
    private static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
        .dnsLookupFailed, .timedOut, .internationalRoamingOff, .dataNotAllowed,
    ]

    /// Foreground-activation refresh: skips accounts whose snapshot is
    /// still fresh, so quick app switches don't refetch, but returning
    /// after a while updates the dashboard — and, via the refresh flow,
    /// pushes new snapshots to the widgets immediately.
    func refreshAllIfStale(maxAge: TimeInterval = 60) async {
        // A widget may have recorded samples while the app was away.
        reloadTimelines()
        let fetched = await withTaskGroup(of: Bool.self) { group in
            for entry in accounts {
                let isFresh = entry.snapshot.map { Date().timeIntervalSince($0.fetchedAt) < maxAge } ?? false
                guard !isFresh else { continue }
                group.addTask { await self.fetch(accountID: entry.account.accountID) }
            }
            return await group.reduce(false) { $0 || $1 }
        }
        if fetched { WidgetReload.all() }
        applyAccountOrder()
    }

    var isRefreshing: Bool { accounts.contains { $0.isRefreshing } }
    /// True when there are no usable accounts — dashboard shows the connect
    /// card instead of usage rows.
    var needsConnection: Bool { accounts.isEmpty }

    /// This account's current `AccountUsage`, if still connected.
    func usage(for accountID: String) -> AccountUsage? {
        accounts.first { $0.account.accountID == accountID }
    }

    /// True once pace has warmed up (a couple of sessions observed since
    /// this account connected). Until then, views withhold the pace caption
    /// and the forecast, showing a "learning" state instead of asserting a
    /// pace from too little history.
    func paceReady(for accountID: String) -> Bool {
        return PaceCalculator.isReady(observingSince: services[accountID]?.paceObservingSince())
    }

}
