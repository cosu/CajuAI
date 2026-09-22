import Foundation
import Observation

@Observable
@MainActor
final class OpenRouterUsageViewModel {
    var isAuthenticated = false
    var usage: OpenRouterAccountUsage?
    var isLoading = false
    var error: String?
    var lastUpdated: Date?
    var lastUsageChange: Date?
    private var lastUsageSignature: String?

    private let service = OpenRouterService()
    private var autoRefreshTask: Task<Void, Never>?

    init() {
        isAuthenticated = service.hasAPIKey()
        if isAuthenticated {
            Task { await refresh() }
            startAutoRefresh()
        }
    }

    // MARK: - Auth

    func saveKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        service.saveAPIKey(trimmed)
        isAuthenticated = true
        error = nil
        Task { await refresh() }
        startAutoRefresh()
    }

    func signOut() {
        service.deleteAPIKey()
        isAuthenticated = false
        usage = nil
        lastUpdated = nil
        lastUsageChange = nil
        lastUsageSignature = nil
        error = nil
        stopAutoRefresh()
    }

    // MARK: - Popover open

    func userOpenedPopover() async {
        if isAuthenticated { startAutoRefresh() }
        let eligible = lastUpdated.map { Date().timeIntervalSince($0) >= 60 } ?? true
        if eligible { await refresh() }
    }

    // MARK: - Data Fetching

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        do {
            usage = try await service.fetchAccountUsage()
            recordUsageChange(usageSignature)
            lastUpdated = Date()
        } catch OpenRouterServiceError.invalidAPIKey {
            isAuthenticated = false
            error = "Invalid management key. Please re-enter your OpenRouter management key."
        } catch OpenRouterServiceError.notManagementKey {
            isAuthenticated = false
            error = "Need an OpenRouter management key, not a regular API key. Create one at openrouter.ai/settings/keys."
        } catch OpenRouterServiceError.notAuthenticated {
            isAuthenticated = false
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    var menuBarLabel: String {
        guard let credits = usage?.credits else { return "" }
        return String(format: "$%.2f", credits.remaining)
    }

    var menuBarUsage: MenuBarUsage {
        MenuBarUsage(text: menuBarLabel, systemImage: "o.circle.fill", changedAt: lastUsageChange)
    }

    private var usageSignature: String? {
        guard let credits = usage?.credits else { return nil }
        return String(format: "%.4f", credits.totalUsage)
    }

    private func recordUsageChange(_ signature: String?) {
        if let previous = lastUsageSignature, previous != signature {
            lastUsageChange = Date()
        }
        lastUsageSignature = signature
    }

    // MARK: - Auto Refresh

    private func startAutoRefresh() {
        stopAutoRefresh()
        autoRefreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5 * 60))
                guard !Task.isCancelled else { break }
                await refresh()
            }
        }
    }

    private func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }
}
