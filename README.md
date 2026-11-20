# AIMeter (iOS fork)

An iPhone and iPad app with widgets that shows how much of your AI
subscription is used and when each limit resets. No server, no account,
no analytics.

This is a cut-down fork of [AIMeter](https://github.com/MikeAlvarado/AIMeter)
by Mike Alvarado: the iOS app and its widgets only, with Claude and Codex.
The original's Mac app, Apple Watch app, notch island, iCloud sync,
GitHub Copilot support, Live Activity and status-page checks are not in
this fork.

Supported: **Claude** Pro, Max and Ultra (session, weekly and per-model
windows; Ultra has no session limit) and **Codex** on any ChatGPT plan
(5-hour and weekly windows, or Free's single 30-day window).

## What it does

- **One card per account**: every limit as a bar with its reset, the one
  closest to its limit large, a 24-hour sparkline, the plan. Bars turn
  yellow past 70 % and red past 85 % used (can be turned off).
- **Several accounts**, Claude and Codex side by side, each with its own
  name, icon and alerts. Drag to reorder, or order by urgency.
- **Account detail**: history (24 hours to 90 days), pace, a forecast of
  what runs out early, today's share of a long window, the week by app,
  spend and extra usage.
- **Widgets**: one account's limits (small, medium, Lock Screen), a
  single limit as a bar or ring, or all accounts at once (large). StandBy
  shows one large figure. On iOS 18, a control for Control Center, the
  Lock Screen or the Action button.
- **Notifications**, all per account and off by default except the
  sign-in one: at each reset, near a limit, at a limit, early resets,
  projected run-outs, ahead of pace, a renewal reminder, and when a
  sign-in stops working.
- **Shortcuts**: Refresh Usage, Show Usage, Account Usage, Next Resets,
  Open Account.
- English, German, Spanish, French, Japanese, Korean, Brazilian
  Portuguese and Simplified Chinese.

## How it connects

- **Claude**: you sign in on Claude's own page in your browser (OAuth with
  PKCE, scope `user:profile` only) and paste back the code it shows.
- **Codex**: AIMeter shows a one-time code you enter on ChatGPT's device
  page (device code login must be allowed in ChatGPT's security
  settings).

Tokens are stored only in the iOS Keychain, on this device
(`AfterFirstUnlockThisDeviceOnly`, never synced or backed up to another
device), shared with the widget extension. Only the app refreshes tokens;
the widgets read them and never rotate them.

## Privacy and data

The app talks only to:

- `api.anthropic.com` (usage and profile), `console.anthropic.com`
  (token exchange and refresh), and `claude.ai` (the sign-in page, in
  your browser);
- `chatgpt.com` (Codex usage) and `auth.openai.com` (device code sign-in,
  token exchange and refresh).

Snapshots, up to 90 days of usage percentages and preferences stay in the
app's App Group container on the device. Disconnecting an account deletes
its token, data and alerts.

## Disclaimer

AIMeter reads usage from **undocumented endpoints**
(`https://api.anthropic.com/api/oauth/usage`,
`https://chatgpt.com/backend-api/wham/usage`) with your own token. They
may change or disappear at any time and are not officially supported. It
uses the public OAuth clients of Claude Code and the Codex CLI.
Anthropic's published policy reserves Claude.ai OAuth for its own
applications; AIMeter claims no exemption, and a provider may restrict
these endpoints, clients or tokens at any time. The Codex token has the
same access the Codex CLI gets, though AIMeter only reads usage with it.

This project is not affiliated with, endorsed by, or sponsored by
Anthropic or OpenAI. "Claude" is a trademark of Anthropic, PBC;
"ChatGPT", "Codex" and "OpenAI" of OpenAI. Use at your own risk and in
accordance with each service's terms.

## Building

Requires Xcode 26 or later for iOS 17+.

1. Copy `Config.local.xcconfig.example` to `Config.local.xcconfig` and set
   your Team ID (`DEVELOPMENT_TEAM`).
2. Open `AIMeter.xcodeproj`, scheme `AIMeter`, and run on a device or
   simulator. Both targets need the App Group `group.dev.rudek.aimeter`
   and the matching keychain access group; change the identifiers to your
   own if you sign under another team.

CI (`.github/workflows/ios-build.yml`) builds the app unsigned for the iOS
Simulator on every pull request and every push to `ios-minimal`.

## Architecture

```
AIMeter/              app: services, views, App Intents
AIMeterWidgets/       widget extension
WidgetsShared/        code shared by the widget kinds
Shared/               code compiled into both targets, strings catalog
Packages/UsageKit/    Swift package: core types, providers, stores
AIMeterTests/         app unit tests
```

UsageKit has no UI dependencies. Each provider implements `UsageProvider`
and returns `UsageWindow`s; `Shared/ProviderCatalog.swift` is the one
place that maps a provider id to its provider and credential store.
Details for contributors are in `CLAUDE.md` and the nested `CLAUDE.md`
files.

## License

[MIT](LICENSE)
