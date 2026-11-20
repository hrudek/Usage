## Codex provider (`Providers/Codex/`)

`CodexProvider.providerID` is `"codex"`, display name "Codex": a ChatGPT
account's Codex limits, from the undocumented endpoint the Codex CLI's
`/status` reads. A server change should only touch this folder.

### Endpoint

- `GET https://chatgpt.com/backend-api/wham/usage` with
  `Authorization: Bearer <access token>`, `ChatGPT-Account-Id` (when
  known) and `Accept: application/json`.
- Decoded: `plan_type` (the plan pill), `rate_limit`
  (`limit_reached`, `primary_window`, `secondary_window`; each
  `used_percent`, `limit_window_seconds`, `reset_after_seconds`,
  `reset_at`), `additional_rate_limits[]`, and
  `spend_control.individual_limit` (workspaces).
- Mapping (`CodexUsageResponse.usageWindows`): the primary window is the
  session when it is at most 24 h long, else the overall period; the
  secondary is the week. Codex Free reports one 30-day primary window, so
  it has one `.weekly` window of 30 days (titled "Monthly"). Each
  additional limit becomes `.modelSpecific(limit_name)`. `limit_reached`
  marks full windows `.exceeded`. A window without `used_percent` is
  skipped, and so is a secondary window beside a long primary (never
  seen), which already took `.weekly`.
  `spend_control.individual_limit` maps to `SpendStatus`.
- Statuses: 401 triggers one refresh (app only) and a retry, then
  `notAuthenticated`; 429 `rateLimited`; anything else `httpError`.

### Sign-in and tokens

- Device code (`CodexDeviceAuth`, the CLI's `codex login --device-auth`):
  `POST https://auth.openai.com/api/accounts/deviceauth/usercode` with
  `{"client_id"}` returns `device_auth_id`, `user_code`, `interval` (a
  string or a number) and `expires_at`. The user enters the code at
  `https://auth.openai.com/codex/device` (device code login must be
  allowed in ChatGPT's security settings). `POST
  /api/accounts/deviceauth/token` answers 403/404 until approved, then
  `authorization_code` and `code_verifier`, exchanged at
  `https://auth.openai.com/oauth/token` (`grant_type=authorization_code`,
  `redirect_uri=https://auth.openai.com/deviceauth/callback`).
- Client: the CLI's public PKCE client `app_EMoamEEZ73f0CkXaXp7hrann`.
  Refresh: `POST /oauth/token`, form-encoded `grant_type=refresh_token`.
  OpenAI rotates the refresh token and revokes the token family when a
  spent one is reused, so every refresh goes through `TokenRefresher`.
  400 or 401 is `notAuthenticated`, 429 `rateLimited`, anything else
  `httpError`.
- Tokens are JWTs. `JWTClaims` reads only `exp` and, under
  `https://api.openai.com/auth`, `chatgpt_account_id`. The `id_token` is not stored: the account id is
  taken from the access token, else from the `id_token`, at sign-in and
  refresh, and kept as `CodexCredentials.accountID`.
- `CodexKeychainCredentialSource`: key `codex.credentials.<accountID>`
  in the shared Keychain group. With `allowsRefresh == false` (the widget
  extension) an expired token is not refreshed.

### Fixtures

`Tests/UsageKitTests/Fixtures/codex-usage-response-free.json` is a real
Free account capture (ids redacted);
`codex-usage-response-plus-synthetic.json` is hand-built on the CLI's
schema for a paid plan.
