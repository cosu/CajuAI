//
//  CursorModels.swift
//  CajuAI
//

import Foundation

// MARK: - Token

struct CursorTokenInfo {
    let token: String
    let userId: String
}

// MARK: - Billing

struct CursorBillingInfo: Decodable {
    let membershipType: String        // "pro", "free", "business", etc.
    let subscriptionStatus: String    // "active", etc.
    let isYearlyPlan: Bool
    let isTeamMember: Bool
    let teamMembershipType: String?

    /// Monthly fast-request budget for this plan.
    var fastRequestLimit: Double {
        switch membershipType.lowercased() {
        case "pro", "business": return 500
        case "free":            return 50
        default:                return 0   // usage-based — no hard cap
        }
    }
}

// MARK: - Usage events

struct CursorUsageEvent {
    let timestamp: Date
    let model: String
    let kind: String              // e.g. "USAGE_EVENT_KIND_INCLUDED_IN_PRO"
    let requestsCosts: Double     // fast-request units consumed
    let totalCents: Double        // actual compute cost in cents
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheWriteTokens: Int
}

// MARK: - Aggregated usage

struct CursorUsageData {
    let billing: CursorBillingInfo
    let fastRequestsUsed: Double              // sum of requestsCosts this period
    let periodStart: Date
    let modelBreakdown: [(model: String, requests: Double, cents: Double)]
    let recentEvents: [CursorUsageEvent]

    var fastRequestLimit: Double { billing.fastRequestLimit }
    var hasLimit: Bool { fastRequestLimit > 0 }

    var usageFraction: Double {
        guard hasLimit else { return 0 }
        return fastRequestsUsed / fastRequestLimit
    }

    var totalCents: Double {
        recentEvents.reduce(0) { $0 + $1.totalCents }
    }
}

// MARK: - Errors

enum CursorServiceError: LocalizedError {
    case dbNotFound
    case dbReadFailed(String)
    case tokenNotFound
    case invalidToken
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .dbNotFound:
            return "Cursor database not found — is Cursor installed and logged in?"
        case .dbReadFailed(let msg):
            return "Failed to read Cursor database: \(msg)"
        case .tokenNotFound:
            return "No auth token in Cursor database — please sign in to Cursor first"
        case .invalidToken:
            return "Could not extract user ID from Cursor token"
        case .apiError(let msg):
            return "Cursor API error: \(msg)"
        }
    }
}
