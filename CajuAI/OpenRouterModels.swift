import Foundation

struct OpenRouterCreditsResponse: Decodable {
    let data: Credits

    struct Credits: Decodable {
        let totalCredits: Double
        let totalUsage: Double

        var remaining: Double { totalCredits - totalUsage }

        var fraction: Double {
            guard totalCredits > 0 else { return 0 }
            return min(max(totalUsage / totalCredits, 0), 1)
        }
    }
}

struct OpenRouterKeysResponse: Decodable {
    let data: [ManagedKey]

    struct ManagedKey: Decodable, Identifiable {
        var id: String { hash }
        let hash: String
        let name: String?
        let label: String?
        let disabled: Bool?
        let usage: Double?
        let usageDaily: Double?
        let usageWeekly: Double?
        let usageMonthly: Double?
        let byokUsage: Double?
        let limit: Double?
        let limitRemaining: Double?
        let limitReset: String?

        var displayName: String {
            if let name, !name.isEmpty { return name }
            if let label, !label.isEmpty { return label }
            return "API key"
        }
    }
}

struct OpenRouterAccountUsage {
    let credits: OpenRouterCreditsResponse.Credits
    let keys: [OpenRouterKeysResponse.ManagedKey]

    var usageDaily: Double { keys.reduce(0) { $0 + ($1.usageDaily ?? 0) } }
    var usageWeekly: Double { keys.reduce(0) { $0 + ($1.usageWeekly ?? 0) } }
    var usageMonthly: Double { keys.reduce(0) { $0 + ($1.usageMonthly ?? 0) } }
    var byokUsage: Double { keys.reduce(0) { $0 + ($1.byokUsage ?? 0) } }

    var rankedKeys: [OpenRouterKeysResponse.ManagedKey] {
        keys.sorted { ($0.usageMonthly ?? 0) > ($1.usageMonthly ?? 0) }
    }
}

enum OpenRouterServiceError: Error, LocalizedError {
    case notAuthenticated
    case apiError(String)
    case invalidAPIKey
    case notManagementKey

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "No management key configured. Please add your OpenRouter management key."
        case .apiError(let msg):
            return "OpenRouter API error: \(msg)"
        case .invalidAPIKey:
            return "Invalid management key. Please check your OpenRouter management key."
        case .notManagementKey:
            return "This endpoint needs an OpenRouter management key, not a regular API key."
        }
    }
}
