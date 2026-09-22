import Foundation

struct DeepSeekBalanceResponse: Decodable {
    let isAvailable: Bool
    let balanceInfos: [BalanceInfo]

    enum CodingKeys: String, CodingKey {
        case isAvailable = "is_available"
        case balanceInfos = "balance_infos"
    }

    struct BalanceInfo: Decodable {
        let currency: String
        let totalBalance: String
        let grantedBalance: String
        let toppedUpBalance: String

        enum CodingKeys: String, CodingKey {
            case currency
            case totalBalance = "total_balance"
            case grantedBalance = "granted_balance"
            case toppedUpBalance = "topped_up_balance"
        }

        var totalBalanceDouble: Double { Double(totalBalance) ?? 0 }
        var grantedBalanceDouble: Double { Double(grantedBalance) ?? 0 }
        var toppedUpBalanceDouble: Double { Double(toppedUpBalance) ?? 0 }
    }
}

enum DeepSeekServiceError: Error, LocalizedError {
    case notAuthenticated
    case apiError(String)
    case invalidAPIKey

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "No API key configured. Please add your DeepSeek API key."
        case .apiError(let msg):
            return "DeepSeek API error: \(msg)"
        case .invalidAPIKey:
            return "Invalid API key. Please check your DeepSeek API key."
        }
    }
}
