import Foundation

struct OpenRouterService {
    private static let creditsURL = URL(string: "https://openrouter.ai/api/v1/credits")!
    private static let keysURL = URL(string: "https://openrouter.ai/api/v1/keys")!

    private static let keysPageSize = 100
    private static let keysMaxPages = 5

    func saveAPIKey(_ key: String) {
        KeychainStore.update { $0.openrouterApiKey = key }
    }

    func loadAPIKey() -> String? {
        KeychainStore.load().openrouterApiKey
    }

    func hasAPIKey() -> Bool {
        loadAPIKey() != nil
    }

    func deleteAPIKey() {
        KeychainStore.update { $0.openrouterApiKey = nil }
    }

    // MARK: - API

    func fetchAccountUsage() async throws -> OpenRouterAccountUsage {
        async let credits = fetchCredits()
        async let keys = fetchAllKeys()
        return try await OpenRouterAccountUsage(credits: credits.data, keys: keys)
    }

    private func fetchCredits() async throws -> OpenRouterCreditsResponse {
        let data = try await get(OpenRouterService.creditsURL)
        return try decoder.decode(OpenRouterCreditsResponse.self, from: data)
    }

    private func fetchAllKeys() async throws -> [OpenRouterKeysResponse.ManagedKey] {
        var all: [OpenRouterKeysResponse.ManagedKey] = []
        for page in 0..<OpenRouterService.keysMaxPages {
            let offset = page * OpenRouterService.keysPageSize
            var components = URLComponents(url: OpenRouterService.keysURL, resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "offset", value: String(offset)),
            ]
            guard let url = components.url else {
                throw OpenRouterServiceError.apiError("Invalid keys URL")
            }
            let data = try await get(url)
            let pageKeys = try decoder.decode(OpenRouterKeysResponse.self, from: data).data
            all.append(contentsOf: pageKeys)
            if pageKeys.count < OpenRouterService.keysPageSize { break }
        }
        return all
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    private func get(_ url: URL) async throws -> Data {
        guard let apiKey = loadAPIKey() else {
            throw OpenRouterServiceError.notAuthenticated
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenRouterServiceError.apiError("Invalid response")
        }
        guard http.statusCode == 200 else {
            if http.statusCode == 401 {
                throw OpenRouterServiceError.invalidAPIKey
            }
            if http.statusCode == 403 {
                throw OpenRouterServiceError.notManagementKey
            }
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OpenRouterServiceError.apiError("HTTP \(http.statusCode): \(body)")
        }
        return data
    }
}
