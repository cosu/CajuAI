# AGENTS.md — CajuAI Developer Context

Project instructions for coding agents working in this repo.

## Project

macOS menu bar app (macOS 26.3+) that shows usage for Claude, Cursor, DeepSeek, and OpenRouter in a segmented popover.

## Architecture

| File | Role |
|------|------|
| `CajuAI/CajuAIApp.swift` | App entry. `MenuBarExtra` with `.window` style. Holds `@State` view models for every provider and injects them with `.environment(...)` |
| `CajuAI/ContentView.swift` | All UI: tabs (`AppTab`), `MenuBarView`, Claude `UsageView`/`LoginView`, `CursorView`, `DeepSeekView`, `OpenRouterView`, shared `UsageRow`/`UsageProgressBar` |
| `CajuAI/ClaudeModels.swift` | Codable structs: `ClaudeUsageResponse`, `ClaudeProfileResponse`, `TokenResponse`, `ClaudeAuthError` |
| `CajuAI/ClaudeUsageService.swift` | OAuth 2.0 + PKCE, Keychain token storage, Anthropic API calls. Singleton with `private init()` |
| `CajuAI/ClaudeUsageViewModel.swift` | `@Observable @MainActor` — Claude UI state, auto-refresh loop |
| `CajuAI/CursorModels.swift` | `CursorTokenInfo`, `CursorBillingInfo`, `CursorUsageEvent`, `CursorUsageData`, `CursorServiceError` |
| `CajuAI/CursorService.swift` | Reads Cursor auth token from local SQLite DB, calls Cursor REST API |
| `CajuAI/CursorUsageViewModel.swift` | `@Observable @MainActor` — Cursor tab UI state |
| `CajuAI/DeepSeekModels.swift` | `DeepSeekBalanceResponse`, `DeepSeekServiceError` |
| `CajuAI/DeepSeekService.swift` | Keychain API key + `GET https://api.deepseek.com/user/balance` |
| `CajuAI/DeepSeekUsageViewModel.swift` | `@Observable @MainActor` — DeepSeek tab UI state |
| `CajuAI/OpenRouterModels.swift` | `OpenRouterKeyResponse`, `OpenRouterServiceError` |
| `CajuAI/OpenRouterService.swift` | Keychain API key + `GET https://openrouter.ai/api/v1/key` |
| `CajuAI/OpenRouterUsageViewModel.swift` | `@Observable @MainActor` — OpenRouter tab UI state |
| `CajuAI/KeychainStore.swift` | One Keychain item (`ro.cosu.CajuAI` / `claude_tokens`) holding Claude tokens + DeepSeek/OpenRouter keys. In-memory cache so launch only prompts once |
| `CajuAI/CajuAI.entitlements` | Currently empty. Outgoing network is enabled via build settings (`ENABLE_OUTGOING_NETWORK_CONNECTIONS = YES`); App Sandbox is off so Cursor can read its local DB |
| `CajuAI/Persistence.swift` | Unused CoreData boilerplate from the Xcode template — leave in place |
| `scripts/rebuild-install.sh` | Clean Release build, copy to `/Applications/CajuAI.app`, relaunch |
| `.vscode/tasks.json` | Default Cursor/VS Code **build** task runs that script |

New providers follow the DeepSeek/OpenRouter pattern: Models + Service + UsageViewModel + a tab in `ContentView`, wired from `CajuAIApp`.

## Key Swift Patterns

- `@Observable` (not `ObservableObject`) — required because `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is set in build settings
- `@State private var viewModel` in App (not `@StateObject`)
- `.environment(viewModel)` to pass down / `@Environment(SomeUsageViewModel.self)` to receive
- `@Bindable var bvm = viewModel` inside view `body` to create bindings to `@Observable` properties
- `.onChange(of:)` used for ALL persistent side effects from `@Observable` properties — more reliable than `didSet` (applies to refresh interval, debugMode toggle, etc.)
- Auto-refresh uses a `Task` with `Task.sleep` loop rather than `Timer` to avoid actor isolation issues
- `refresh()` guards `isLoading` at the top in every view model to prevent concurrent fetches

## Anthropic OAuth

| Item | Value |
|------|-------|
| client_id | `9d1c250a-e61b-44d9-88ed-5944d1962f5e` |
| Auth URL | `https://claude.ai/oauth/authorize` |
| Token URL | `https://console.anthropic.com/v1/oauth/token` |
| Redirect URI | `https://console.anthropic.com/oauth/code/callback` |
| Scope | `org:create_api_key user:profile user:inference` |
| Token request format | `application/x-www-form-urlencoded` (not JSON) |
| Required API header | `anthropic-beta: oauth-2025-04-20` |
| Usage endpoint | `https://api.anthropic.com/api/oauth/usage` |
| Profile endpoint | `https://api.anthropic.com/api/oauth/profile` |

The `state` parameter is required in both the auth URL and the token exchange request body. When the user pastes the full redirect URL, `state` is extracted and validated against `pendingState` before the token exchange (CSRF protection). If the user pastes only the bare code, state validation is skipped.

## Auth Flow (Claude)

1. App generates PKCE verifier + S256 challenge + random `state`
2. Opens auth URL in browser via `NSWorkspace`
3. User authenticates → browser lands on `console.anthropic.com/oauth/code/callback?code=XXX&state=YYY`
4. User copies the full URL from the address bar and pastes into the app text field
5. Service extracts `code` from the URL, exchanges it (with verifier + state) for tokens
6. Tokens stored as a single JSON-encoded Keychain item (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, non-syncable)

## Keychain Storage

All provider secrets live in **one** Keychain item so macOS only prompts once:

- service: `ro.cosu.CajuAI`
- account: `claude_tokens` (name kept so existing ACLs still apply)
- access: `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, non-syncable

JSON shape:

```json
{
  "claude": { "accessToken": "...", "refreshToken": "...", "expiresAt": 0 },
  "deepseekApiKey": "...",
  "openrouterApiKey": "..."
}
```

`KeychainStore` loads once per process and caches. Claude sign-out only clears the `claude` field; it must not delete DeepSeek/OpenRouter keys.

On first launch of this layout, leftover `deepseek_api_key` / `openrouter_api_key` items (and the old Claude-only JSON) are merged in, then the extra items are deleted. That merge can prompt once per old item; later launches prompt at most once.

## Claude Usage API Response Shape

```json
{
  "five_hour":       { "utilization": 42.5, "resets_at": "2026-03-28T15:00:00Z" },
  "seven_day":       { "utilization": 67.3, "resets_at": "2026-04-01T00:00:00Z" },
  "seven_day_sonnet":{ "utilization": 55.0, "resets_at": "2026-04-01T00:00:00Z" },
  "extra_usage":     { "is_enabled": true, "utilization": 12.0, "used_credits": 450, "monthly_limit": 5000 }
}
```

`used_credits` and `monthly_limit` are in cents — divide by 100 for display.

## Cursor Integration

Cursor usage is read entirely locally — no additional auth flow required.

| Item | Detail |
|------|--------|
| Token source | SQLite DB at `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`, key `cursorAuth/accessToken` |
| Token format | Either `user_XXX::JWT` (cookie format) or a plain JWT |
| userId extraction | Split on `::` to get prefix, or decode JWT payload and read `sub` field |
| Cookie header | `WorkosCursorSessionToken=userId%3A%3Ajwt` — decode the raw DB token before building cookie to avoid double-encoding |
| Billing endpoint | `https://cursor.com/api/auth/stripe` — returns snake_case JSON, **must use `keyDecodingStrategy = .convertFromSnakeCase`** |
| Usage summary | `GET https://cursor.com/api/usage-summary` — **this is what Plans & Usage shows**. Use `individualUsage.plan.totalPercentUsed` (0–100). Do **not** use `used`/`limit` (those are a different unit) or a hardcoded 500 fast-request cap |
| Usage events | `https://cursor.com/api/dashboard/get-filtered-usage-events` (POST, paginated) — model breakdown only |
| Period | `billingCycleStart` / `billingCycleEnd` from usage-summary |

## DeepSeek Integration

User pastes an API key (`sk-...` from platform.deepseek.com/api_keys). Invalid keys (HTTP 401) clear auth and ask the user to re-enter.

| Item | Detail |
|------|--------|
| Balance endpoint | `GET https://api.deepseek.com/user/balance` |
| Auth | `Authorization: Bearer <api key>` |
| Response | `is_available`, `balance_infos[]` with `currency`, `total_balance`, `granted_balance`, `topped_up_balance` (string amounts) |

## OpenRouter Integration

User pastes a **management API key** (from openrouter.ai/settings/keys), not a regular inference key. Stored in Keychain as `openrouter_api_key`. HTTP 401 clears auth. HTTP 403 means a regular key was used — prompt for a management key.

| Item | Detail |
|------|--------|
| Credits | `GET https://openrouter.ai/api/v1/credits` → `total_credits`, `total_usage` (remaining = credits − usage) |
| Keys | `GET https://openrouter.ai/api/v1/keys?offset=` — paginated, 100 per page, cap 5 pages |
| Auth | `Authorization: Bearer <management key>` |
| Decoding | snake_case JSON — **must use `keyDecodingStrategy = .convertFromSnakeCase`** |
| Display | Account credit bar; today / week / month summed across keys; top keys by monthly spend |
| Do not | Call `/api/v1/key` (current-key, inference keys only), or create/update/delete keys |

## Colour Thresholds

- White: < 40%
- Yellow: 40–69%
- Red: ≥ 70%

## Manual Xcode Setup (required after cloning)

1. Target → **Signing & Capabilities** → enable **Outgoing Connections (Client)**
2. Target → **Info** tab → add `Application is agent (UIElement)` = `YES` (already set as `INFOPLIST_KEY_LSUIElement = YES` in build settings)

## Build / Install

After any feature or bugfix that changes the app, **always** run `scripts/rebuild-install.sh` before treating the work as done. Do not stop at a compile-only `xcodebuild`. Skip install only for docs-only / non-code edits.

- Deployment target: macOS 26.3 (`MACOSX_DEPLOYMENT_TARGET = 26.3`), Swift 5, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
- `scripts/rebuild-install.sh` — `xcodebuild clean build` (Release), `ditto` to `/Applications/CajuAI.app`, launch
- Menu bar extra shows the provider whose usage number moved on the latest refresh (Claude 5h %, Cursor fast-request %, DeepSeek remaining balance, OpenRouter remaining credits). Until something changes, it falls back to Claude.
- Xcode **Install** scheme: quit running app, Release build, copy to `/Applications`, open
- Xcode **CajuAI** scheme: normal run/debug (LaunchAction is Release)
- Local `xcodebuild` output lives under `build/DerivedData/` (gitignored)
