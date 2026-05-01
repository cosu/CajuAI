import Foundation

// MARK: - Usage Response

struct ClaudeUsageResponse: Codable {
    let fiveHour: UsagePeriod?
    let sevenDay: UsagePeriod?
    let sevenDaySonnet: UsagePeriod?
    let extraUsage: ExtraUsage?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDaySonnet = "seven_day_sonnet"
        case extraUsage = "extra_usage"
    }
}

struct UsagePeriod: Codable {
    let utilization: Double
    let resetsAt: Date

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

struct ExtraUsage: Codable {
    let isEnabled: Bool
    let utilization: Double?
    let usedCredits: Double?
    let monthlyLimit: Double?

    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case utilization
        case usedCredits = "used_credits"
        case monthlyLimit = "monthly_limit"
    }

    // API returns cents, display as dollars
    var usedCreditsDisplay: Double { (usedCredits ?? 0) / 100 }
    var monthlyLimitDisplay: Double { (monthlyLimit ?? 0) / 100 }
}

// MARK: - Profile Response

struct ClaudeProfileResponse: Codable {
    let account: Account

    struct Account: Codable {
        let displayName: String?
        let fullName: String?
        let email: String?
        let hasClaudeMax: Bool?
        let hasClaudePro: Bool?

        enum CodingKeys: String, CodingKey {
            case displayName = "display_name"
            case fullName = "full_name"
            case email
            case hasClaudeMax = "has_claude_max"
            case hasClaudePro = "has_claude_pro"
        }

        var planName: String {
            if hasClaudeMax == true { return "Max" }
            if hasClaudePro == true { return "Pro" }
            return "Free"
        }

        var displayTitle: String {
            let name = displayName ?? fullName ?? email ?? "Unknown"
            return "\(name) · \(planName)"
        }
    }
}

// MARK: - Token Response

struct TokenResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

// MARK: - Errors

enum ClaudeAuthError: Error, LocalizedError {
    case noCode
    case noPendingVerifier
    case stateMismatch
    case tokenExchangeFailed(String)
    case notAuthenticated
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .noCode: return "No authorization code found in the pasted text."
        case .noPendingVerifier: return "No pending auth session. Please start the sign-in flow again."
        case .stateMismatch: return "Security check failed: state mismatch. Please start the sign-in flow again."
        case .tokenExchangeFailed(let msg): return "Token exchange failed: \(msg)"
        case .notAuthenticated: return "Not signed in. Please sign in again."
        case .apiError(let msg): return "API error: \(msg)"
        }
    }
}
