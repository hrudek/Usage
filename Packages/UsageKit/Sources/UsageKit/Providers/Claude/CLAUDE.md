## Claude provider (`Providers/Claude/`)

`ClaudeProvider.providerID` is `"claude"`, display name "Claude". The
endpoints are undocumented ones Claude Code uses; a server change should
only touch this folder.

### Endpoints

- `GET https://api.anthropic.com/api/oauth/usage`: the usage windows.
  The `limits` array (kinds `session`, `weekly_all`, `weekly_scoped` with
  `scope.model.display_name`) maps to `.session`, `.weekly` and
  `.modelSpecific(<model>)`; unknown kinds are skipped. Top-level
  `five_hour` / `seven_day` are a fallback when `limits` is missing.
  `spend` (`amount_minor` scaled by `exponent`) maps to `SpendStatus`,
  `extra_usage` (credits scaled by `decimal_places`) to
  `ExtraUsageStatus`, `seven_day_breakdown.rows` to `UsageBreakdown`.
  `resets_at` is ISO 8601 and null for a window with no usage yet. Ultra
  has no `session` entry. Scoped weekly windows share the weekly window's
  reset date. Each window carries its length (5 h, 7 days).
- `GET https://api.anthropic.com/api/oauth/profile`: the plan, which the
  usage response does not carry. `account.has_claude_pro` /
  `has_claude_max` give "pro" / "max" (max wins); a Max whose
  `organization.rate_limit_tier` contains `max_20x` or `ultra` is
  "ultra". The plan is stored in the credentials (`subscriptionType`,
  `planCheckedAt`) and re-checked after `planRecheckInterval` (6 h); a
  failed call keeps the last plan.
- Headers: `Authorization: Bearer <access token>`,
  `anthropic-beta: oauth-2025-04-20`, `User-Agent: claude-code/<version>`
  (other agents get persistent 429s).
- Statuses: 401 triggers one refresh (app only) and a retry, then
  `notAuthenticated`; 429 is `rateLimited`; anything else `httpError`.

### Sign-in and tokens

- PKCE against `https://claude.ai/oauth/authorize`, client ID
  `9d1c250a-e61b-44d9-88ed-5944d1962f5e`, redirect
  `https://console.anthropic.com/oauth/code/callback`, scope
  `user:profile` only (`user:inference` is never requested). The user
  pastes `<code>#<state>`; a missing or different state throws.
  Exchange and refresh at `https://console.anthropic.com/v1/oauth/token`.
- Token endpoint: 400 or 401 is `notAuthenticated`, 429 `rateLimited`,
  anything else `httpError`.
- Refresh goes through `TokenRefresher` (see the repo-root CLAUDE.md):
  one rotation per login at a time, a rejected refresh re-reads the
  store (again after `rejectionRecheckDelay`, 1.5 s) before it counts as
  a dead login, and the plan write-back saves only the plan fields onto
  what the store holds once no rotation runs.
- `ClaudeKeychainCredentialSource`: the app's own copy in the shared
  Keychain group, key `ClaudeKeychainCredentialSource.storageKey(for:)`
  (`claude.credentials.<accountID>`). With `allowsRefresh == false` (the
  widget extension) an expired token throws `tokenExpired` instead of
  refreshing.

### Fixtures

`Tests/UsageKitTests/Fixtures/claude-usage-response.json` (Pro or Max)
and `claude-usage-response-ultra.json` (Ultra, no session) are captured
responses; the mapping tests assert against them.
