import Foundation

struct DeepSeekService {
    private static let balanceURL = URL(string: "https://api.deepseek.com/user/balance")!

    func saveAPIKey(_ key: String) {
        KeychainStore.update { $0.deepseekApiKey = key }
    }

    func loadAPIKey() -> String? {
        KeychainStore.load().deepseekApiKey
    }

    func hasAPIKey() -> Bool {
        loadAPIKey() != nil
    }

    func deleteAPIKey() {
        KeychainStore.update { $0.deepseekApiKey = nil }
    }

    // MARK: - API

    func fetchBalance() async throws -> DeepSeekBalanceResponse {
        guard let apiKey = loadAPIKey() else {
            throw DeepSeekServiceError.notAuthenticated
        }

        var request = URLRequest(url: DeepSeekService.balanceURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DeepSeekServiceError.apiError("Invalid response")
        }
        guard http.statusCode == 200 else {
            if http.statusCode == 401 {
                throw DeepSeekServiceError.invalidAPIKey
            }
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw DeepSeekServiceError.apiError("HTTP \(http.statusCode): \(body)")
        }

        return try JSONDecoder().decode(DeepSeekBalanceResponse.self, from: data)
    }
}
