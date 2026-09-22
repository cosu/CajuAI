import Foundation
import Observation

@Observable
@MainActor
final class DeepSeekUsageViewModel {
    var isAuthenticated = false
    var balance: DeepSeekBalanceResponse?
    var isLoading = false
    var error: String?
    var lastUpdated: Date?
    var showAPIKeyField = false
    var lastUsageChange: Date?
    private var lastUsageSignature: String?

    private let service = DeepSeekService()
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
        showAPIKeyField = false
        error = nil
        Task { await refresh() }
        startAutoRefresh()
    }

    func signOut() {
        service.deleteAPIKey()
        isAuthenticated = false
        balance = nil
        lastUpdated = nil
        lastUsageChange = nil
        lastUsageSignature = nil
        error = nil
        showAPIKeyField = false
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
            balance = try await service.fetchBalance()
            recordUsageChange(usageSignature)
            lastUpdated = Date()
        } catch DeepSeekServiceError.invalidAPIKey {
            isAuthenticated = false
            error = "Invalid API key. Please re-enter your DeepSeek API key."
        } catch DeepSeekServiceError.notAuthenticated {
            isAuthenticated = false
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    var menuBarLabel: String {
        guard let info = balance?.balanceInfos.first else { return "" }
        return String(format: "%@ %.2f", info.currency, info.totalBalanceDouble)
    }

    var menuBarUsage: MenuBarUsage {
        MenuBarUsage(text: menuBarLabel, systemImage: "d.circle.fill", changedAt: lastUsageChange)
    }

    private var usageSignature: String? {
        guard let infos = balance?.balanceInfos, !infos.isEmpty else { return nil }
        return infos.map { "\($0.currency):\($0.totalBalance)" }.joined(separator: ",")
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
