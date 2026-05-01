import Foundation
import CryptoKit
import AppKit
import Security

/// Handles Anthropic OAuth authentication and usage API calls.
/// Uses the same client_id and redirect URI as the hass-claude-usage integration.
class ClaudeUsageService {
    static let shared = ClaudeUsageService()
    private init() {}

    private let clientId = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private let redirectURI = "https://console.anthropic.com/oauth/code/callback"
    private let scope = "org:create_api_key user:profile user:inference"

    private static let tokenURL = URL(string: "https://console.anthropic.com/v1/oauth/token")!
    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let profileURL = URL(string: "https://api.anthropic.com/api/oauth/profile")!

    private let keychainService = "ro.cosu.CajuAI"
    private let keychainAccount = "claude_tokens" // single item stores all token data

    // Legacy UserDefaults keys — used only for one-time migration
    private let legacyAccessTokenKey = "claude_access_token"
    private let legacyRefreshTokenKey = "claude_refresh_token"
    private let legacyExpiresAtKey = "claude_token_expires_at"

    private struct StoredTokens: Codable {
        var accessToken: String
        var refreshToken: String?
        var expiresAt: TimeInterval // Unix timestamp
    }

    /// Stored during the OAuth flow so we can exchange the code later
    private(set) var pendingVerifier: String?
    private(set) var pendingState: String?

    // MARK: - PKCE Helpers

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Auth URL

    /// Generates the OAuth authorization URL and stores the PKCE verifier.
    /// Opens the URL in the default browser. The user will be redirected to
    /// console.anthropic.com/oauth/code/callback — they should copy that URL
    /// (or the code from it) and paste it back into the app.
    func openAuthPage() {
        let verifier = generateCodeVerifier()
        let state = generateCodeVerifier()
        pendingVerifier = verifier
        pendingState = state
        let challenge = generateCodeChallenge(from: verifier)

        var components = URLComponents()
        components.scheme = "https"
        components.host = "claude.ai"
        components.path = "/oauth/authorize"
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]

        if let url = components.url {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Token Exchange

    /// Accepts either the full redirect URL or just the authorization code.
    func exchangeCode(_ input: String) async throws {
        guard let verifier = pendingVerifier,
              let expectedState = pendingState else {
            throw ClaudeAuthError.noPendingVerifier
        }

        let (code, returnedState) = extractCodeAndState(from: input)
        guard !code.isEmpty else {
            throw ClaudeAuthError.noCode
        }
        if let returnedState, returnedState != expectedState {
            throw ClaudeAuthError.stateMismatch
        }

        var formComponents = URLComponents()
        formComponents.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "state", value: expectedState),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_verifier", value: verifier),
        ]

        var request = URLRequest(url: ClaudeUsageService.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formComponents.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown"
            throw ClaudeAuthError.tokenExchangeFailed(errorBody)
        }

        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        storeTokens(token)
        pendingVerifier = nil
        pendingState = nil
    }

    private func extractCodeAndState(from input: String) -> (code: String, state: String?) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("http"),
           let url = URL(string: trimmed),
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            let code = components.queryItems?.first(where: { $0.name == "code" })?.value ?? ""
            let state = components.queryItems?.first(where: { $0.name == "state" })?.value
            return (code, state)
        }
        return (trimmed, nil)
    }

    // MARK: - Keychain Storage (single item, JSON encoded)

    private func keychainBaseQuery() -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount,
            kSecAttrSynchronizable: false,
        ]
    }

    private func saveStoredTokens(_ stored: StoredTokens) {
        guard let data = try? JSONEncoder().encode(stored) else { return }
        var query = keychainBaseQuery()
        let updateFields: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        if SecItemUpdate(query as CFDictionary, updateFields as CFDictionary) == errSecItemNotFound {
            query[kSecValueData] = data
            query[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(query as CFDictionary, nil)
        }
    }

    private func loadStoredTokens() -> StoredTokens? {
        var query = keychainBaseQuery()
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(StoredTokens.self, from: data)
    }

    func hasStoredToken() -> Bool {
        migrateIfNeeded()
        return loadStoredTokens() != nil
    }

    /// One-time migration from old UserDefaults storage and old multi-item Keychain storage.
    private func migrateIfNeeded() {
        guard loadStoredTokens() == nil else { return } // already migrated

        let defaults = UserDefaults.standard
        let accessToken = defaults.string(forKey: legacyAccessTokenKey)
            ?? loadLegacyKeychainItem(account: legacyAccessTokenKey)

        guard let accessToken else { return }

        let refreshToken = defaults.string(forKey: legacyRefreshTokenKey)
            ?? loadLegacyKeychainItem(account: legacyRefreshTokenKey)

        var expiresAt: TimeInterval = Date().addingTimeInterval(3600).timeIntervalSince1970
        if let expiresAtStr = defaults.string(forKey: legacyExpiresAtKey) ?? loadLegacyKeychainItem(account: legacyExpiresAtKey),
           let interval = TimeInterval(expiresAtStr) {
            expiresAt = interval
        } else if let date = defaults.object(forKey: legacyExpiresAtKey) as? Date {
            expiresAt = date.timeIntervalSince1970
        }

        saveStoredTokens(StoredTokens(accessToken: accessToken, refreshToken: refreshToken, expiresAt: expiresAt))

        // Clean up legacy storage
        [legacyAccessTokenKey, legacyRefreshTokenKey, legacyExpiresAtKey].forEach {
            defaults.removeObject(forKey: $0)
            deleteLegacyKeychainItem(account: $0)
        }
    }

    private func loadLegacyKeychainItem(account: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: account,
            kSecAttrSynchronizable: false,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteLegacyKeychainItem(account: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: account,
            kSecAttrSynchronizable: false,
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func storeTokens(_ response: TokenResponse) {
        let expiresAt = Date().addingTimeInterval(TimeInterval(response.expiresIn)).timeIntervalSince1970
        saveStoredTokens(StoredTokens(accessToken: response.accessToken, refreshToken: response.refreshToken, expiresAt: expiresAt))
    }

    func clearTokens() {
        SecItemDelete(keychainBaseQuery() as CFDictionary)
    }

    // MARK: - Token Refresh

    private func validAccessToken() async throws -> String {
        guard var stored = loadStoredTokens() else {
            throw ClaudeAuthError.notAuthenticated
        }
        // Refresh proactively 60 seconds before expiry
        if Date(timeIntervalSince1970: stored.expiresAt).timeIntervalSinceNow < 60,
           let refreshToken = stored.refreshToken {
            try await refreshAccessToken(using: refreshToken)
            guard let refreshed = loadStoredTokens() else { throw ClaudeAuthError.notAuthenticated }
            stored = refreshed
        }
        return stored.accessToken
    }

    private func refreshAccessToken(using refreshToken: String) async throws {
        var formComponents = URLComponents()
        formComponents.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "client_id", value: clientId),
        ]

        var request = URLRequest(url: ClaudeUsageService.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formComponents.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            clearTokens()
            throw ClaudeAuthError.notAuthenticated
        }

        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        storeTokens(token)
    }

    // MARK: - API Calls

    private func authorizedData(from url: URL) async throws -> Data {
        let token = try await validAccessToken()

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ClaudeAuthError.apiError(body)
        }
        return data
    }

    func fetchUsage() async throws -> ClaudeUsageResponse {
        let data = try await authorizedData(from: ClaudeUsageService.usageURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ClaudeUsageResponse.self, from: data)
    }

    func fetchProfile() async throws -> ClaudeProfileResponse {
        let data = try await authorizedData(from: ClaudeUsageService.profileURL)
        return try JSONDecoder().decode(ClaudeProfileResponse.self, from: data)
    }
}
