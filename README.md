# Usage

An iPhone and iPad app with widgets that shows how much of your Claude and
Codex subscriptions is used and when each limit resets: Claude Pro, Max
and Ultra, and Codex on any ChatGPT plan. Several accounts side by side,
history, alerts near a limit, Lock Screen and Home Screen widgets.

No server, no account, no analytics. Sign-in tokens are stored only in the
iOS Keychain on the device and shared with the widget extension; only the
app renews them. The app talks only to Anthropic's and OpenAI's own
endpoints.

## Building

- CI: `.github/workflows/ios-build.yml` builds the app unsigned for the
  iOS Simulator on every pull request and every push to `main`.
- Xcode 26 or later: copy `Config.local.xcconfig.example` to
  `Config.local.xcconfig`, set your own Team ID (`DEVELOPMENT_TEAM`), open
  `Usage.xcodeproj` and run the `Usage` scheme. Both targets need the App
  Group `group.dev.rudek.usage` and the matching keychain access group;
  change the identifiers to your own if you sign under another team.

Contributor notes are in `CLAUDE.md`.

## Disclaimer

Usage reads limits from undocumented endpoints with your own token, using
the public OAuth clients of Claude Code and the Codex CLI. They may change
or stop working at any time. Usage is not affiliated with, endorsed by, or
sponsored by Anthropic or OpenAI. "Claude" is a trademark of Anthropic,
PBC; "ChatGPT", "Codex" and "OpenAI" are trademarks of OpenAI. Use at your
own risk and in line with each service's terms.

## Acknowledgments

Usage started from AIMeter by Mike Alvarado (https://github.com/MikeAlvarado/AIMeter, MIT), which served as its model.

## License

[MIT](LICENSE)
