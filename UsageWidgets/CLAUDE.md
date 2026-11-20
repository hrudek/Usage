## Widgets

The widget extension (`dev.rudek.usage.widgets`) reads what the app
stored in the App Group: the account registry, each account's snapshot,
the display preferences. `UsageWidgetsBundle` lists, in gallery order:

- `UsageWidget`, kind `UsageLimits` ("Usage Limits"): one account's
  windows. `.systemSmall`, `.systemMedium` and the Lock Screen
  accessories (`.accessoryCircular`, `.accessoryRectangular`,
  `.accessoryInline`, views in `WidgetsShared/AccessoryUsageViews.swift`).
  The account is picked per instance (`UsageAccountConfigurationIntent`);
  unset, the first connected account (`WidgetAccountFallback`). The
  circular gauge and the control show the `glanceMetric` window. A small
  widget without its container background (StandBy) draws
  `StandByUsageView`, one large figure. The small family and each
  account of `AllAccountsWidget` lead with the session, as the
  Dashboard card does (`AccountCardLayout`).
- `SingleUsageWidget`, kind `UsageSingleLimit` ("Single Limit"):
  `.systemSmall`, one window the user picks (`SingleUsageConfigurationIntent`:
  the limit, and a bar or a ring).
- `AllAccountsWidget`, kind `UsageAllAccounts` ("All Accounts"):
  `.systemLarge`, every connected account, layout standard or condensed
  (`AllAccountsConfigurationIntent`), in the urgency order when that
  preference is on.
- `UsageControl`, kind `UsageControl` (iOS 18+): one account's figure
  in Control Center, on the Lock Screen or the Action button; a tap runs
  `RefreshAccountIntent`. It never fetches on its own.

Every home screen widget is one button (`refreshesOnTap`, plain style,
labelled "Refresh"): a tap anywhere refreshes it instead of opening the
app, so there is no refresh button and no `widgetURL`. The provider mark
(`WidgetMetrics.markSize`, 48 pt) sits in the top-right corner of a
`WidgetMarkBand`: a band as tall as the mark whose left side stacks the
account's name (a staleness hint under it) over the first window's name,
so the mark adds no height (small, single limit, each account of the
standard all-accounts layout; the condensed layout puts the next session
reset under its title there). The medium family gives the mark a column
of its own right of the header and the window columns: a band over the
columns would cost height they need. The ring style's figure is 24 pt,
since the band leaves the ring less height. A reset
countdown has no icon before it. A used percentage stands alone, with no
"used" after it; in remaining mode "left" follows it
(`DisplayMode.widgetSuffix`). The widget configurations turn
the system content margins off (`contentMarginsDisabled`) so the button
reaches the edges; `widgetMargins()` puts them back as padding inside it
(and on the accessory and StandBy views), so the layout is unchanged.

A Claude account can hide its per-model window (Fable) from widgets on
its settings page (`WidgetModelWindowPreference`, App Group key
`widget.showsModelWindow.<accountID>`, stored only while off). The
`UsageLimits` and `UsageAllAccounts` views, and the latter's urgency
order, draw `shownSnapshot` (`UsageSnapshot.forWidgets(of:)`), the
snapshot without its per-model windows; the third slot then follows
"Usage rows" as for a plan with none. Display only: the stored snapshot,
the stale check and the reload schedule keep every window. The single
limit widget and the control show the window the user picked, so they
ignore it.

Every home screen widget's container background is `WidgetBackdrop`:
the app's backdrop gradient (fixed sRGB colors, #2B2D42 to #0D0E14 in
dark, top-leading to bottom-trailing) in full color, nothing in the
accented and vibrant rendering modes, where the system draws its own.

## Timeline and fetching

- One entry per timeline, reloaded at
  `max(refreshCadence, AppConfig.widgetRefreshFloor)` (30 min floor, to
  stay within WidgetKit's budget) or a minute after the soonest reset
  ahead (`WidgetSchedule.nextReload`), whichever is first. Reset lines
  under a day count down live (`ResetLine`, `Text(timerInterval:)`)
  without a reload.
- When the stored snapshot is stale (`WidgetSchedule.isStale`: older than
  that interval, or overtaken by a reset), `WidgetRefresher.fetchIfStale`
  fetches for that account with a 15 s request timeout (only for an
  account in the registry; the pickers' placeholder never fetches). Instances of one
  account share an in-flight stamp in the App Group so only one fetches.
  The result is saved to `SnapshotStore` and both histories
  (`UsageRecorder`).
- `RefreshAccountIntent` (a tap on a home screen widget, and the control)
  fetches now, at most once every 5 s per account, then reloads the
  widget kinds. `RefreshAllAccountsIntent` does it for every account (the
  all-accounts widget).
- Every widget provider is built with `allowsRefresh: false`: the
  extension reads the Keychain item and never rotates a token. With an
  expired access token the fetch fails and the widget keeps the stored
  snapshot until the app refreshes.
- A snapshot older than `AppConfig.staleAfter` (30 min) shows an
  "updated X ago" hint.
- The app reloads every timeline and the control through
  `WidgetReload.all()` once per refresh sweep, on foreground, and after a
  change to a widget-visible preference.
