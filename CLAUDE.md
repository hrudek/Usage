# Usage

An iOS app (iOS 17+, iPhone and iPad, pure SwiftUI, no third-party
dependencies, no server) with a widget extension that shows how much of
an AI subscription is used and when each limit resets. Two provider
families: Claude (Pro, Max, Ultra) and Codex (any ChatGPT plan). Several
accounts, of one family or both, can be connected at once.

The repository is hrudek/Usage, a standalone project (its origin is in
README.md's Acknowledgments): iOS only, with no macOS app, Watch, notch
island, iCloud sync, GitHub Copilot, status pages, Live Activity, demo
mode, release scripts or website. The code is the source of truth; this
file says only what the code does.

## Identifiers

- App: `dev.rudek.usage`; widget extension: `dev.rudek.usage.widgets`.
- App Group: `group.dev.rudek.usage`, in both targets' entitlements and
  `Shared/AppConfig.swift`. It is also the keychain access group, so both
  targets carry `keychain-access-groups` (`$(AppIdentifierPrefix)` + the
  group) as well as `com.apple.security.application-groups`. The App
  Group alone shares `UserDefaults` and files, not Keychain items.
- Keychain service: `dev.rudek.usage`.
- Background task: `dev.rudek.usage.refresh` (`BGAppRefreshTask`).
- Widget kinds: `UsageLimits`, `UsageSingleLimit`, `UsageAllAccounts`;
  control kind (iOS 18+): `UsageControl`. See `UsageWidgets/CLAUDE.md`.

## Layout

- `Usage/`: the app. `Services/` (model, refresh, notifications),
  `Views/`, `Intents/` (App Intents). See `Usage/CLAUDE.md`.
- `UsageWidgets/`: the widget extension. See `UsageWidgets/CLAUDE.md`.
- `WidgetsShared/`: widget code shared by the widget kinds (account
  picker intent, fallback account, accessory views, placeholders).
- `Shared/`: compiled into both targets: `AppConfig`, `ProviderCatalog`,
  preferences, theme and shared views, formatting, the pure display rules
  (`WindowDisplay`, `AccountCardLayout`, `AccountOrder`, `ResetLine`,
  `WidgetSchedule`, `HistoryChartData`, `UsageInsights`), `UsageRecorder`,
  `WidgetReload`, `Localizable.xcstrings`, `PrivacyInfo.xcprivacy`.
- `Design/AppIcon.svg`: the app icon's source, a full-bleed square (iOS
  applies the corner mask). It is exported to
  `Usage/Assets.xcassets/AppIcon.appiconset/AppIcon.png`, 1024 x 1024,
  no alpha (`rsvg-convert`, then flatten).
- `Packages/UsageKit/`: the local Swift package (iOS 17) with the
  provider-agnostic core, the providers and the stores.
- `UsageTests/`: the app's unit tests (hosted in the app).

## Architecture rules

- UsageKit imports only Foundation, Security and CryptoKit: never SwiftUI,
  WidgetKit, UIKit or Combine.
- A provider implements `UsageProvider.fetchUsage() async throws ->
  UsageSnapshot`. A snapshot holds `[UsageWindow]` plus optional `spend`,
  `extraUsage` and `breakdown`. `UsageWindow.Kind` is `.session`,
  `.weekly`, `.modelSpecific(String)` and `.credits`
  (display only, synthesized from `spend`, never stored). Views render
  whatever windows a snapshot has and never key on a provider name.
- A window's length comes from the window (`duration`, read through
  `effectiveDuration`), not from its kind: Codex Free's single window is
  a 30-day `.weekly` titled "Monthly".
- Typed errors (`UsageError`) keep the endpoint's error text so the UI can
  show it; the UI decides how.

## Provider seam

`Shared/ProviderCatalog.swift` is the only switch on `providerID`:
`providerIDs` (Connect sheet order), `displayName(for:)`,
`symbolName(for:)` (an SF Symbol, never a logo) and
`makeProvider(for:keychain:allowsRefresh:transport:)`, which returns the
`UsageProvider` and the `CredentialStore` to clear on disconnect. Each
family lives in `Packages/UsageKit/Sources/UsageKit/Providers/<Family>/`
with its own CLAUDE.md (endpoints, sign-in, mapping). A sign-in flow hands
the model a `ProviderLogin` (`.claude` or `.codex`), which
`UsageModel.completeConnection` and `reconnect(accountID:login:)` take.

## Accounts

- `providerID` names a family (`"claude"`, `"codex"`); `accountID` names
  one connected login and keys everything stored for it (Keychain item,
  snapshot, histories, notification preferences, widget selection).
- `AccountRegistryStore` (App Group `UserDefaults`, key `usage.accounts`)
  is the ordered list of `ConnectedAccount`s. Its order is the display
  order everywhere. Each entry decodes on its own, so one unreadable entry
  drops only itself; a duplicate `accountID` keeps its first entry, on
  read and in `replaceAll`. Only the app writes it; the widget extension
  reads.
- Display names are unique (case-insensitive). Signing in again after a
  login stopped working reconnects in place: same `accountID`, new
  credentials, nothing else changes.
- "Order by urgency" (`Preferences.ordersByUrgency`) sorts the shown
  accounts by their most used window without rewriting the registry.

## Tokens and the Keychain

- Tokens live only in the Keychain (`KeychainStore`), shared access group,
  class `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` on add and on
  update, never synchronizable. Never in `UserDefaults` or git.
- Both services rotate the refresh token on every use. Only the app
  refreshes: the widget extension builds its providers with
  `allowsRefresh: false`, and with an expired access token its fetch fails
  and it keeps the stored snapshot.
- `TokenRefresher.shared` (UsageKit actor) runs one refresh per login at a
  time; a caller that needs one while another runs joins it. The rotation
  and its save run in a task of their own. A rotated pair the Keychain
  refuses is retried and kept in memory until a save succeeds. Other
  writes to a login (the Claude plan write-back) wait until no rotation of
  it runs.
- A refresh rejected with 400 or 401 re-reads the store (once more after
  a short delay) and uses a different pair if one is there; otherwise it
  is `notAuthenticated` and the account shows "Sign in again".
- Codex keeps no `id_token`; its account id is copied out at sign-in and
  refresh.

## Refresh

- `RefreshService` (one per account) fetches, fills missing reset dates
  from the previous snapshot (`fillingMissingResets`), saves the snapshot,
  records history (`UsageRecorder`) and reschedules or fires that
  account's notifications. `UsageModel` fans out over all accounts
  concurrently and reloads widgets once per sweep (`WidgetReload.all()`)
  when any snapshot landed.
- Cold launch: `refreshAll()`. Foreground: `WidgetReload.all()` and
  `refreshAllIfStale()` (accounts older than 60 s). Background:
  `BGAppRefreshTask` at the user's cadence (30 min, 1 h, 3 h),
  `UsageModel.refreshAllInBackground()`.
- Widgets reload at most every 30 min (`AppConfig.widgetRefreshFloor`) and
  a minute after the next reset; a widget whose snapshot is stale fetches
  for its own account, read-only (see `UsageWidgets/CLAUDE.md`).

## Stores (App Group)

- `SnapshotStore`: the last snapshot per account (`UserDefaults`).
- `UsageHistoryStore`: a short, reset-aware sample ring per window, for
  the run-out predictor and the pace warm-up anchor (`UserDefaults`).
- `UsageTimelineStore`: `usage-timeline/<accountID>.json`, the chart's
  series: raw for 48 h, hourly maxima to 30 days, daily maxima to 90 days.
- `UsageRecorder` writes both histories together; disconnecting clears
  the account's credentials, snapshot, histories, pending and delivered
  notifications, and its preference keys (notification toggles and
  `WidgetModelWindowPreference`).

## Notifications (local only, per account, off by default)

Identifiers are `<prefix><accountID>.…`. Scheduled: `reset.` (at each
window's reset), `runout.` (a projected early run-out), `renewal.` (a
user-set day of the month, 10:00). Fired on detection between two
snapshots: `earlyreset.`, `nearlimit.` (up to three levels),
`limitreached.`, `ahead.` (ahead of pace). `reauth.` fires when a fetch
fails with `notAuthenticated`; it is the one family on by default. With
two or more accounts, titles start with the account's name.

## Presentation

- Up to three rows per account (`WindowSlots`): session, the overall
  period, then a per-model window, or credits per "Usage rows".
- Colors live in `Shared/Theme.swift`. Dark: backdrop a diagonal
  gradient #2B2D42 to #0D0E14 (`Theme.backdrop`, app screens and widget
  backgrounds), cards #2B2D42, bar track #3A3D52, ink #FFFFFF, secondary ink
  #8D99AE, accent #5DCAA5, red #E24B4A. Light keeps ivory surfaces with
  the same accent and red darkened to 4.5:1 (#387963, #C24040). Text on
  a filled accent shape uses `Theme.onAccent`.
- Bar color (`UsageLevel`): accent up to 70 % used, yellow above 70 %,
  red above 85 % or when the provider flags critical/exceeded; the yellow
  and red can be turned off ("Usage colors").
- Display preferences (used or remaining, relative or absolute resets,
  appearance, cadence, glance metric, usage rows, colors) live in the App
  Group so widgets read them.

## Localization

English source plus de, es, fr, ja, ko, pt-BR, zh-Hans, in
`Shared/Localizable.xcstrings` (app and widgets) and UsageKit's own
`Resources/Localizable.xcstrings` (errors). A changed string changes its
key: update every language. Brand names (Claude, Codex, ChatGPT,
Anthropic, OpenAI, Usage) are not translated. No em dash or en dash in
any user-facing text, in any language.

## Build and CI

- No local Xcode is assumed. The gate is the GitHub Actions workflow
  "iOS build check" (`.github/workflows/ios-build.yml`): an unsigned iOS
  Simulator build of the `Usage` scheme, on pull requests. It runs no
  tests.
- Release: every push to `main` runs "TestFlight"
  (`.github/workflows/testflight.yml`, environment `testflight`): a signed
  archive (manual signing, build number = run number) uploaded to
  TestFlight. `.github/testflight/profiles.py` reuses or creates the
  "Usage CI" App Store profiles through the App Store Connect API and
  writes the CI's `Config.local.xcconfig` and export options. Secrets
  (environment): `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY_BASE64`,
  `IOS_CERTIFICATE_P12_BASE64`, `IOS_CERTIFICATE_PASSWORD`; variables:
  `APPLE_TEAM_ID`, `APPLE_CERTIFICATE_ID`.
- Signing: `Config.local.xcconfig` (gitignored, from
  `Config.local.xcconfig.example`) sets `DEVELOPMENT_TEAM`.
- Unit tests: `UsageTests` (scheme `Usage`) and UsageKit's
  `UsageKitTests`, run in Xcode on a simulator.

## Repo rules

- Git history is linear: one feature or fix per branch from
  `main`, rebased and merged with rebase (never squash, never merge
  commits), plain imperative commit subjects, no Co-Authored-By.
- Pull requests go to hrudek/Usage (`gh ... -R hrudek/Usage`).
- Never commit `xcuserdata`, `Config.local.xcconfig`, credentials or
  tokens.
- Keep files under about 300 lines; async/await, no Combine.
- Accessibility: each usage row is one VoiceOver element, bars are
  hidden from it, icon-only buttons have labels.
- Docs follow the code: a change in behavior updates the CLAUDE.md that
  describes it.
