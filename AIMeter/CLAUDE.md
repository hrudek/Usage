## The app

`AIMeterApp` opens one `WindowGroup` with `ContentView` (a
`NavigationStack` on the Dashboard) and registers the background refresh
(`.backgroundTask(.appRefresh(AppConfig.refreshTaskID))`). `UsageModel`
(`@MainActor`, `@Observable`) and `PreferencesModel` go into the
environment; every sheet gets both again from its presenter
(`withAppModels(model, prefs)`, `PresentedModels.swift`).

## Services

- `UsageModel.swift`: accounts and their snapshots, one `RefreshService`
  per account, the refresh entry points (`refreshAll`, `refresh(accountID:)`,
  `refreshAllIfStale`, the static `refreshAllInBackground`).
  `+Connections` (connect, reconnect in place, disconnect), `+Naming`
  (order, nicknames, icons), `+Notifications` (per-account toggles,
  authorization), `+History` (the chart timelines in memory),
  `+Insights` (another account's room).
- `RefreshService.swift`: one account's fetch, store, history and
  notifications; `storeConnection` writes a `ProviderLogin` through the
  account's own credential source and refuses one of another family.
- `NotificationScheduler*.swift`, `NotificationPreferences.swift`: the
  notification families in the repo-root CLAUDE.md, per-account toggles
  in the App Group.
- `BackgroundRefresh.swift`: submits the next `BGAppRefreshTaskRequest`
  at the user's cadence when the app goes to the background.
- `AppEnvironment.swift`: the live model for the App Intents.

## Screens

- **Dashboard** (`DashboardView`): one card per account
  (`AccountSectionView`): identity header (icon, name, plan pill, opens
  Provider Detail; context menu with rename, icon, move up/down), the
  window closest to its limit large (`HeroWindowView`, with a 24 h
  sparkline), the others as compact rows, then an error, "Sign in again",
  or a stale hint. Header buttons: Settings and Refresh. Hold and drag to
  reorder (`DashboardView+Reorder`), withheld while "Order by urgency" is
  on. Two columns on iPad. With no account, a prompt to connect.
- **Provider Detail** (`ProviderDetailView`, `ProviderDetailCards`,
  `HistoryCard`): rate limits with pace captions, History (24 h, 7 days,
  30 days, 90 days), Forecast (projected run-outs, after a 20 h pace
  warm-up), Today (a share of a long window), This week by app, Spend,
  Extra usage. Its toolbar opens the account's settings.
- **Account settings** (`AccountSettingsPage`): name, icon, reset alerts,
  smart notifications (near limit with up to three levels, limit reached,
  early reset, run-out, ahead of pace, sign-in), renewal reminder,
  disconnect (with confirmation).
- **Settings** (`SettingsView`, sections in `SettingsSections.swift`):
  the account list with "Add account" and "Order by urgency", then
  Appearance (theme, used or remaining, reset style, usage colors, usage
  rows), Widgets (the Lock Screen window, how to add a widget), Refresh &
  data (background cadence, Privacy & data).
- **Privacy & data** (`PrivacyView`): what is stored where, how each
  family's sign-in works, what the connection can access.
- **Connect sheet** (`ConnectAccountSheet`): pick the service, then
  - Claude (`ConnectClaudeSheet`): opens Claude's sign-in page in the
    browser (PKCE, scope `user:profile`), the user pastes back
    `code#state`, the state must match;
  - Codex (`DeviceCodeConnectView`): a one-time code to enter on ChatGPT's
    device page, polled at the service's interval until approved (15 min
    cap, backs off when throttled).
  The same sheets repair a broken login in place (`reconnecting:`).
- **iPhone Duo side bar** (`SideBar.swift`): Settings and Refresh at the
  side of the screen when the display is split.

## App Intents (`Intents/`)

"Refresh Usage", "Show Usage", "Account Usage", "Next Resets" and "Open
Account" (`AccountEntity` from the registry), all requiring an unlocked
device. Their titles stay in English in every language.
