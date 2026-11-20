## The app

`UsageApp` opens one `WindowGroup` with `ContentView` and registers the background refresh
(`.backgroundTask(.appRefresh(AppConfig.refreshTaskID))`). `UsageModel`
(`@MainActor`, `@Observable`) and `PreferencesModel` go into the
environment; every sheet gets both again from its presenter
(`withAppModels(model, prefs)`, `PresentedModels.swift`).

`ContentView` lays the Dashboard out by `DashboardLayout` (pure, tested),
from the size class, its own size and the iPhone Duo's fold
(`reservedRegions(kind: .division)`, iOS 27.1):
- `stack`: a `NavigationStack` on the Dashboard whose cards push an
  account's detail. A compact width (every iPhone, the Duo's outer
  display), a regular width taller than wide (iPad and the open Duo
  upright), or no account.
- `sideBySide`: a regular width wider than tall (iPad and the open Duo on
  their side) or a fold running down the display (the Duo partly open
  like a book). `DashboardSplitView`: the cards in one column as the
  sidebar, half the width, the selected account's detail beside it.
- `aboveAndBelow`: a fold across the display (the Duo partly open like a
  laptop). `DashboardPanes`: the cards above the fold, the detail below,
  nothing on the fold.
Beside or below, a tap anywhere on a card selects its account (outlined
in the accent) instead of pushing, and the card is one VoiceOver element
(selected trait, its menu as actions); the detail shows the selected
account, or the first once that one is gone, and the "Open Account"
intent selects.
Only an account chosen explicitly (a card tapped beside or below, a
detail opened in the stack, the intent) is the selection
(`DashboardActions.selectedAccountID`); the first account shown by
default is not, and a disconnected one is dropped. Turning the device
from the split to the stack opens the selection's detail, or the
Dashboard when there is none; the other way the split shows it.
Settings, Connect, the selection and the refresh haptic hang on
`DashboardActions`; reconnect, rename, icon and disconnect confirmation,
from a card, a detail or an account's settings, on `AccountPresenter`
(`presentsAccountSheets()`, applied above the layouts and again inside
Settings, which presents its own). Both sit above the switch between
the stack and the split, so a turn of the device keeps an open sheet.

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
  session large (`HeroWindowView`, with a 24 h sparkline; without a
  session, the window closest to its limit; `AccountCardLayout`), the
  others as compact rows, then an error, "Sign in again",
  or a stale hint. Header buttons: Settings and Refresh. Hold and drag to
  reorder (`DashboardView+Reorder`), withheld while "Order by urgency" is
  on. Two columns at a regular width in the stack (iPad and the open
  iPhone Duo upright), one beside or above a detail: held sideways
  (`verticalSizeClass` compact) only drops the sparklines and the status
  bar. With no account, a prompt
  to connect.
- **Provider Detail** (`ProviderDetailView`, `ProviderDetailCards`,
  `HistoryCard`): rate limits with pace captions, History (24 h, 7 days,
  30 days, 90 days), Forecast (projected run-outs, after a 20 h pace
  warm-up), Today (a share of a long window), This week by app, Spend,
  Extra usage. Its toolbar opens the account's settings.
- **Account icon** (`AccountIconPicker`): the default sparkle, the
  bundled marks (Claude, Claude Code, OpenAI; `ProviderMark.assetName`),
  curated SF Symbols, or any SF Symbol by name.
- **Account settings** (`AccountSettingsPage`): name, icon, for Claude
  accounts "Per-model limit in widgets" (`WidgetModelWindowPreference`,
  on by default; a change reloads widgets), reset alerts,
  smart notifications (near limit with up to three levels, limit reached,
  early reset, run-out, ahead of pace, sign-in), renewal reminder,
  disconnect (with confirmation).
- **Settings** (`SettingsView`, sections in `SettingsSections.swift`):
  the account list with "Add account" and "Order by urgency", then
  Appearance (theme, used or remaining, reset style, usage colors, usage
  rows), Widgets (the Lock Screen window, how to add a widget), Refresh &
  data (background cadence, Privacy & data) (`SettingsGroup`). At a
  compact width a sheet whose rows push their screens; at a regular width
  (`SettingsSplitView`, full screen) a `NavigationSplitView` with that
  list as the sidebar and the chosen account's page or group's sections
  as the detail.
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
- **iPhone Duo side bar** (`SideBar.swift`): where the system lays the
  bars vertically (`toolbarVerticalEdge` not nil, iOS 27.1: the outer
  display, the inner one in landscape), `DashboardSideBar` puts Settings,
  Refresh and Add account (opens the Connect sheet) there, each an icon
  with a title, and the drawn header drops its two buttons; a sheet's
  Done (`SheetDoneButton`) becomes a checkmark. In `DashboardSplitView`
  the system lays only the detail's bar vertically: the three items go
  on it there, beside the detail's account settings, and the Dashboard's
  header drops its buttons. Elsewhere (other
  iPhones, iPad, the inner display in portrait) the navigation bar stays
  hidden and the drawn header shows as always.

## App Intents (`Intents/`)

"Refresh Usage", "Show Usage", "Account Usage", "Next Resets" and "Open
Account" (`AccountEntity` from the registry), all requiring an unlocked
device. Their titles stay in English in every language.
