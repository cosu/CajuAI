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

    // MARK: - Token storage

    private func saveStoredTokens(_ stored: KeychainStore.ClaudeTokens) {
        KeychainStore.update { $0.claude = stored }
    }

    private func loadStoredTokens() -> KeychainStore.ClaudeTokens? {
        KeychainStore.load().claude
    }

    func hasStoredToken() -> Bool {
        loadStoredTokens() != nil
    }

    private func storeTokens(_ response: TokenResponse) {
        let expiresAt = Date().addingTimeInterval(TimeInterval(response.expiresIn)).timeIntervalSince1970
        saveStoredTokens(KeychainStore.ClaudeTokens(accessToken: response.accessToken, refreshToken: response.refreshToken, expiresAt: expiresAt))
    }

    func clearTokens() {
        KeychainStore.update { $0.claude = nil }
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
