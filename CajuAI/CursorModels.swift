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
}

// MARK: - Usage summary (Plans & Usage)

struct CursorUsageSummary: Decodable {
    let billingCycleStart: Date
    let billingCycleEnd: Date
    let membershipType: String
    let isUnlimited: Bool?
    let autoModelSelectedDisplayMessage: String?
    let namedModelSelectedDisplayMessage: String?
    let individualUsage: CursorIndividualUsage?
}

struct CursorIndividualUsage: Decodable {
    let plan: CursorPlanUsage?
    let onDemand: CursorOnDemandUsage?
}

struct CursorPlanUsage: Decodable {
    let enabled: Bool?
    let used: Double?
    let limit: Double?
    let autoPercentUsed: Double?
    let apiPercentUsed: Double?
    let totalPercentUsed: Double?
}

struct CursorOnDemandUsage: Decodable {
    let enabled: Bool?
    let used: Double?
    let limit: Double?
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
    let billingCycleStart: Date
    let billingCycleEnd: Date
    let totalPercentUsed: Double
    let autoPercentUsed: Double
    let apiPercentUsed: Double
    let displayMessage: String?
    let onDemandEnabled: Bool
    let onDemandUsed: Double
    let isUnlimited: Bool
    let modelBreakdown: [(model: String, requests: Double, cents: Double)]
    let recentEvents: [CursorUsageEvent]

    var usageFraction: Double {
        min(max(totalPercentUsed / 100, 0), 1)
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
