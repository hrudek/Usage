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
app, so there is no refresh button and no `widgetURL`.

Every home screen card opens with `WidgetCardHeader`
(`UsageWidgets/WidgetCard.swift`): the account's name, its plan as a
small pill while both fit on the line, the provider mark
(`WidgetMetrics.markSize`, 32 pt, accent glyph on the accent wash) in
the top-right corner, with no rule under it. The `UsageLimits` small
and medium families add the "updated X ago" hint under the name; the
ring style puts the window's name there, the condensed
layout the next session reset. Below the header: the small family
and each account of the standard all-accounts layout show the leading
window's name, its figure large with the reset beside it, a thick bar,
then the other windows as compact lines (name, bar, figure); the medium
family shows one column per window (name, figure, bar, reset line),
split by vertical hairlines. A reset countdown has no icon before it.

A figure is the bare percentage ("42%", or "--" without a window):
never "used", "left" or "remaining" beside it, in any widget kind,
since the user picked the mode in the app. A figure never truncates:
`WidgetFigure` is one line that shrinks (`minimumScaleFactor`) before
it would cut and takes its width first (`layoutPriority`); a compact
row's, the condensed layout's and the rectangular accessory's figure is
`fixedSize` and the bar or name beside it gives way.

The widget configurations turn the system content margins off
(`contentMarginsDisabled`) so the button reaches the edges; `widgetMargins()` puts them back as padding inside it
(and on the accessory and StandBy views), so the layout is unchanged.

A Claude account can hide its per-model window (Fable) from widgets on
its settings page (`WidgetModelWindowPreference`, App Group key
`widget.showsModelWindow.<accountID>`, stored only while off). The
`UsageLimits` and `UsageAllAccounts` views (and the latter's urgency
order), the single limit widget's window and the control all read the
snapshot through `UsageSnapshot.forWidgets(of:)`, which drops its
per-model windows, so every surface behaves as for a plan with none:
the third slot follows "Usage rows", a single limit widget set to that
window shows it empty, and the gauge and control fall back from it as
`glanceMetric` does. Display only: the stored snapshot, the stale check
and the reload schedule keep every window.

Every home screen widget's container background is `WidgetBackdrop`:
a gradient of its own, darker than the app's `Theme.backdrop` (fixed sRGB colors, #292A3C to #0F1015 in
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
