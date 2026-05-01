import Foundation
import SwiftUI
import Observation
import ServiceManagement

@Observable
@MainActor
class ClaudeUsageViewModel {
    var isAuthenticated = false
    var usage: ClaudeUsageResponse?
    var profile: ClaudeProfileResponse?
    var isLoading = false
    var error: String?
    var lastUpdated: Date?
    var authURLOpened = false

    private let service = ClaudeUsageService.shared
    private var autoRefreshTask: Task<Void, Never>?

    var refreshIntervalMinutes: Double

    // MARK: - Debug Stats
    var debugMode: Bool
    var apiCallCount = 0
    var apiSuccessCount = 0
    var apiErrorCount = 0

    init() {
        let stored = UserDefaults.standard.double(forKey: "refreshIntervalMinutes")
        refreshIntervalMinutes = stored == 0 ? 1.5 : stored.clamped(to: 1...60)
        debugMode = UserDefaults.standard.bool(forKey: "debugMode")
        isAuthenticated = service.hasStoredToken()
        if isAuthenticated {
            Task { await refresh() }
            startAutoRefresh()
        }
    }

    // MARK: - Auth

    func openAuthPage() {
        service.openAuthPage()
        authURLOpened = true
        error = nil
    }

    func submitCode(_ input: String) async {
        isLoading = true
        error = nil
        do {
            try await service.exchangeCode(input)
            isAuthenticated = true
            authURLOpened = false
            await refresh()
            startAutoRefresh()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func signOut() {
        service.clearTokens()
        isAuthenticated = false
        usage = nil
        profile = nil
        lastUpdated = nil
        error = nil
        authURLOpened = false
        stopAutoRefresh()
    }

    // MARK: - Popover open

    /// Called every time the user opens the menu bar popover.
    /// - Refreshes data only if at least 60 s have passed since the last refresh.
    /// - Always resets the auto-refresh countdown so the next scheduled fetch is
    ///   `refreshIntervalMinutes` from *now*, not from whenever the last timer fired.
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
        apiCallCount += 1
        do {
            if profile == nil {
                profile = try await service.fetchProfile()
            }
            usage = try await service.fetchUsage()
            lastUpdated = Date()
            apiSuccessCount += 1
        } catch ClaudeAuthError.notAuthenticated {
            isAuthenticated = false
            stopAutoRefresh()
            error = "Session expired. Please sign in again."
            apiErrorCount += 1
        } catch {
            self.error = error.localizedDescription
            apiErrorCount += 1
        }
        isLoading = false
    }

    func resetDebugStats() {
        apiCallCount = 0
        apiSuccessCount = 0
        apiErrorCount = 0
    }

    // MARK: - Auto Refresh

    func refreshIntervalDidChange() {
        UserDefaults.standard.set(refreshIntervalMinutes, forKey: "refreshIntervalMinutes")
        if isAuthenticated { startAutoRefresh() }
    }

    func debugModeDidChange() {
        UserDefaults.standard.set(debugMode, forKey: "debugMode")
    }

    private func startAutoRefresh() {
        stopAutoRefresh()
        let interval = refreshIntervalMinutes * 60
        autoRefreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                await refresh()
            }
        }
    }

    private func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }

    // MARK: - Computed

    var menuBarLabel: String {
        guard let utilization = usage?.fiveHour?.utilization else { return "" }
        return String(format: "%.0f%%", utilization)
    }

    // MARK: - Login Item

    var launchAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func toggleLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            self.error = "Could not update login item: \(error.localizedDescription)"
        }
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
