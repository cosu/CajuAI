# CLAUDE.md — CajuAI Developer Context

This file gives Claude Code the context needed to work effectively on this project.

## Project

macOS menu bar app (macOS 26.3+) that displays Anthropic Claude subscription usage stats by calling Anthropic's private OAuth-protected usage API.

## Architecture

| File | Role |
|------|------|
| `CajuAI/CajuAIApp.swift` | App entry point. `MenuBarExtra` with `.window` style, holds `@State var viewModel` |
| `CajuAI/ContentView.swift` | All UI: `MenuBarView`, `UsageView`, `LoginView`, `UsageRow`, `UsageProgressBar`, `DebugStatsView`, `CursorView` |
| `CajuAI/ClaudeModels.swift` | Codable structs: `ClaudeUsageResponse`, `ClaudeProfileResponse`, `TokenResponse`, `ClaudeAuthError` |
| `CajuAI/ClaudeUsageService.swift` | OAuth 2.0 + PKCE, Keychain token storage, API calls. Singleton with `private init()` |
| `CajuAI/ClaudeUsageViewModel.swift` | `@Observable @MainActor` class — drives all UI state, auto-refresh loop |
| `CajuAI/CursorModels.swift` | Structs: `CursorTokenInfo`, `CursorBillingInfo`, `CursorUsageEvent`, `CursorUsageData`, `CursorServiceError` |
| `CajuAI/CursorService.swift` | Reads Cursor auth token from local SQLite DB, calls Cursor REST API |
| `CajuAI/CursorUsageViewModel.swift` | `@Observable @MainActor` class — drives Cursor tab UI state |
| `CajuAI/CajuAI.entitlements` | App sandbox + `com.apple.security.network.client` |
| `CajuAI/Persistence.swift` | Unused CoreData boilerplate from the original Xcode template — leave in place |

## Key Swift Patterns

- `@Observable` (not `ObservableObject`) — required because `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is set in build settings
- `@State private var viewModel` in App (not `@StateObject`)
- `.environment(viewModel)` to pass down / `@Environment(ClaudeUsageViewModel.self)` to receive
- `@Bindable var bvm = viewModel` inside view `body` to create bindings to `@Observable` properties
- `.onChange(of:)` used for ALL persistent side effects from `@Observable` properties — more reliable than `didSet` (applies to refresh interval, debugMode toggle, etc.)
- Auto-refresh uses a `Task` with `Task.sleep` loop rather than `Timer` to avoid actor isolation issues
- `refresh()` guards `isLoading` at the top in both viewmodels to prevent concurrent fetches

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

## Auth Flow

1. App generates PKCE verifier + S256 challenge + random `state`
2. Opens auth URL in browser via `NSWorkspace`
3. User authenticates → browser lands on `console.anthropic.com/oauth/code/callback?code=XXX&state=YYY`
4. User copies the full URL from the address bar and pastes into the app text field
5. Service extracts `code` from the URL, exchanges it (with verifier + state) for tokens
6. Tokens stored as a single JSON-encoded Keychain item (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, non-syncable)

## Keychain Storage

All three values (access token, refresh token, expiry) are stored as one JSON blob under:
- service: `ro.cosu.CajuAI`
- account: `claude_tokens`

This avoids multiple Keychain prompts. Migration from the old multi-item layout (and from UserDefaults) runs automatically on first launch via `migrateIfNeeded()`.

## Usage API Response Shape

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
| Usage events | `https://cursor.com/api/dashboard/get-filtered-usage-events` (POST, paginated) |
| Period start | `https://cursor.com/api/usage?user=userId` → `startOfMonth` field |
| Fast request count | Sum of `requestsCosts` across all events in the period (not `events.count` — single events can cost >1 unit) |
| Plan limits | Pro/Business = 500 fast requests/month, Free = 50. Hardcoded — check Cursor changelog if these look wrong |

## Colour Thresholds

- White: < 40%
- Yellow: 40–69%
- Red: ≥ 70%

## Manual Xcode Setup (required after cloning)

1. Target → **Signing & Capabilities** → App Sandbox → check **Outgoing Connections (Client)**
2. Target → **Info** tab → add `Application is agent (UIElement)` = `YES`

## Build Target

macOS 26.3 (`MACOSX_DEPLOYMENT_TARGET = 26.3`), Swift 5, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
